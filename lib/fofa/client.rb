# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"
require "socket"
require "openssl"
require_relative "version"
require_relative "errors"
require_relative "fields"
require_relative "cert"
require_relative "key_provider"

module Fofa
  # FOFA API 客户端，封装 fofa.info 官方全部 5 个接口。
  #
  # 官方文档: https://fofa.info/api/introd
  #
  #   1. 查询接口     GET /api/v1/search/all    资产搜索（分页）
  #   2. 统计聚合     GET /api/v1/search/stats  按字段聚合统计（前 5 排名）
  #   3. Host 聚合   GET /api/v1/host/{host}   单 IP 资产画像（端口/协议/产品）
  #   4. 账号信息     GET /api/v1/info/my       账号余额 / 配额 / 会员等级
  #   5. 连续翻页     GET /api/v1/search/next   大规模数据导出（防错位、可续传）
  #
  # 另含：IP 被动绑定域名查询 domains_for_ip（组合 host/domain/cert 字段与 Host 聚合）
  #
  # 特性:
  #   - 零第三方依赖（仅 Ruby 标准库）
  #   - 查询语句自动 base64 编码（直接传明文即可）
  #   - 按官方限制自动限速（查询 <2/s，stats 5s/次，host 1s/次）
  #   - size 上限自动钳制（cert/banner<=2000，body<=500，其余<=10000）
  #   - 网络错误自动重试（指数退避），FOFA 业务错误转为异常并给出中文说明
  #   - 结果可自动映射为 Hash（search_dicts / iter_dicts）
  #
  # 使用示例:
  #   client = Fofa::Client.new(key: "你的key")   # 或设置环境变量 FOFA_KEY
  #   client.user_info                                        # 账号配额
  #   client.search('title="后台登录"')                        # 资产搜索
  #   client.search_dicts('domain="example.com"')             # 结果转 Hash
  #   client.count('domain="example.com"')                   # 只查总量
  #   client.search_all('app="Apache"', max_records: 5000)    # 批量拉取
  #   client.stats('domain="example.com"')                   # 统计聚合
  #   client.get_host("1.2.3.4", detail: true)                # 单 IP 画像
  #   client.domains_for_ip("1.2.3.4")                        # IP 被动绑定域名
  class Client
    attr_reader :key, :base_url, :timeout

    # @param key:        [String, nil] FOFA API Key；为空时按查找链自动获取：
    #                     环境变量 FOFA_KEY -> 项目根 .env -> ~/.fofa/credentials
    # @param base_url:   [String] API 地址，默认 https://fofa.info/api/v1
    # @param timeout:    [Numeric] 单次请求超时（秒）
    # @param max_retries [Integer] 网络类错误自动重试次数
    # @param backoff:    [Numeric] 重试基础退避秒数，指数递增（backoff * 2^n）
    # @param proxy:      [String, nil] HTTP(S) 代理，如 "http://127.0.0.1:8080"
    # @param debug:      [Boolean] 调试模式，打印每次请求与响应摘要到 stderr
    # @param lookup:     [Boolean] key 为空时是否查找环境变量/配置文件（默认 true）
    def initialize(key: nil, base_url: Fofa::DEFAULT_BASE_URL, timeout: 30,
                   max_retries: 2, backoff: 2.0, proxy: nil, debug: false, lookup: true)
      @key = key.to_s.strip
      @key = Fofa::KeyProvider.resolve.to_s.strip if @key.empty? && lookup
      raise Fofa::AuthError,
            "缺少 FOFA Key：请传入 key: 参数，或配置其中之一：\n" \
            "  1) 环境变量 FOFA_KEY\n" \
            "  2) 项目根目录 .env 文件（FOFA_KEY=你的key，注意加入 .gitignore）\n" \
            "  3) 用户主目录 ~/.fofa/credentials（FOFA_KEY=你的key，推荐）" if @key.empty?

      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @timeout = timeout.to_f
      @max_retries = max_retries.to_i
      @backoff = backoff.to_f
      @proxy = proxy
      @debug = debug
      @rate_mutex = Mutex.new
      @rate_last = {}
    end

    class << self
      # 查询语句 -> qbase64（官方要求 UTF-8 编码后 base64）
      # 官方示例: ip="103.35.168.38" -> aXA9IjEwMy4zNS4xNjguMzgi
      def encode_query(query)
        Base64.strict_encode64(query.to_s)
      end

      # 将官方返回的 results 二维数组按 fields 顺序映射为 Hash 数组
      # @param fields [String] 逗号分隔字段名
      # @param results [Array<Array>] 官方 results
      # @return [Array<Hash>]
      def rows_to_dicts(fields, results)
        names = fields.to_s.split(",").map(&:strip).reject(&:empty?)
        (results || []).map { |row| names.zip(row.map(&:to_s)).to_h }
      end

      # 按官方规则钳制每页数量：
      #   含 cert/banner 时 <= 2000；含 body 时 <= 500；其余 <= 10000；默认 100
      def validate_size(fields, size)
        size = 100 if size.nil?
        size = size.to_i
        fl = fields.to_s.split(",").map { |f| f.strip.downcase }.reject(&:empty?)
        cap = if fl.include?("body") then 500
              elsif fl.include?("cert") || fl.include?("banner") then 2000
              else 10000
              end
        size.negative? ? 1 : [size, cap].min
      end
    end

    # ==================================================================== #
    # 接口 1：账号信息  GET /api/v1/info/my
    # ==================================================================== #

    # 账号信息：email、用户名、F点/F币、会员等级、月度剩余查询次数与返回条数。
    # 该接口不消耗 F 点，常用于启动时校验 key 是否有效。
    # @return [Hash]
    def user_info
      request("/info/my", "key" => @key)
    end
    alias_method :my_info, :user_info

    # ==================================================================== #
    # 接口 2：查询接口  GET /api/v1/search/all
    # ==================================================================== #

    # 资产搜索（分页，按更新时间排序）
    #
    # @param query  [String] FOFA 查询语句明文，如 'title="后台登录" && country="CN"'（自动 base64）
    # @param fields [String] 返回字段，逗号分隔，默认 host,ip,port；完整列表见 Fofa::FIELDS
    # @param size   [Integer] 每页数量，默认 100（cert/banner<=2000，body<=500，自动钳制）
    # @param page   [Integer] 页码，默认 1
    # @param full   [Boolean] true 搜索全部历史数据；默认只搜一年内数据
    # @return [Hash] error/consumed_fpoint/required_fpoints/size/page/query/results
    def search(query, fields: "host,ip,port", size: 100, page: 1, full: false)
      size = self.class.validate_size(fields, size)
      warn_unknown_fields(fields, Fofa::FIELDS)
      request("/search/all",
              "key" => @key,
              "qbase64" => self.class.encode_query(query),
              "fields" => fields,
              "size" => size,
              "page" => page.to_i,
              "full" => full ? "true" : "false",
              "r_type" => "json")
    end

    # 同 #search，但 results 自动映射为 [{field => value}] 数组
    # @return [Array<Hash>]
    def search_dicts(query, fields: "host,ip,port", size: 100, page: 1, full: false)
      resp = search(query, fields: fields, size: size, page: page, full: full)
      self.class.rows_to_dicts(fields, resp["results"])
    end

    # 只获取查询结果总量（仅返回 1 条计费，消耗极小）
    # @return [Integer]
    def count(query, full: false)
      resp = search(query, fields: "ip", size: 1, page: 1, full: full)
      resp["size"].to_i
    end

    # ==================================================================== #
    # 接口 3：连续翻页  GET /api/v1/search/next
    # ==================================================================== #

    # 连续翻页迭代器：大规模数据获取，逐条 yield，不会因页码翻页导致数据错位。
    # 不带 block 调用时返回 Enumerator。
    #
    # @param size        [Integer] 每批数量，默认 1000（自动按字段规则钳制）
    # @param max_records [Integer, nil] 最多拉取条数，nil 表示拉到尽头
    # @yield [Array] 单条结果（按 fields 顺序的数组）
    def search_iter(query, fields: "host,ip,port", size: 1000, full: true, max_records: nil)
      unless block_given?
        return to_enum(__method__, query, fields: fields, size: size,
                       full: full, max_records: max_records)
      end
      batch = self.class.validate_size(fields, size)
      warn_unknown_fields(fields, Fofa::FIELDS)

      next_id = nil
      fetched = 0
      loop do
        params = {
          "key" => @key,
          "qbase64" => self.class.encode_query(query),
          "fields" => fields,
          "size" => batch,
          "full" => full ? "true" : "false",
          "r_type" => "json",
        }
        params["next"] = next_id if next_id && !next_id.empty?
        resp = request("/search/next", params)
        rows = resp["results"] || []
        rows.each do |row|
          yield row
          fetched += 1
          return nil if max_records && fetched >= max_records
        end
        next_id = resp["next"]
        break if next_id.nil? || next_id.empty? || rows.size < batch
      end
      nil
    end

    # 同 #search_iter，但 yield 出 Hash 形式
    # @yield [Hash]
    def iter_dicts(query, fields: "host,ip,port", size: 1000, full: true, max_records: nil, &block)
      names = fields.to_s.split(",").map(&:strip).reject(&:empty?)
      enum = search_iter(query, fields: fields, size: size, full: full,
                         max_records: max_records)
      enum.each do |row|
        block.call(names.zip(row.map(&:to_s)).to_h)
      end
    end

    # 连续翻页一次性拉全量数据并返回数组。
    # 注意：数据量大时会占用大量内存，建议优先使用 search_iter / iter_dicts 流式处理。
    # @return [Array<Array>]
    def search_all(query, fields: "host,ip,port", size: 1000, full: true, max_records: nil)
      search_iter(query, fields: fields, size: size, full: full,
                  max_records: max_records).to_a
    end

    # ==================================================================== #
    # 接口 4：统计聚合  GET /api/v1/search/stats
    # ==================================================================== #

    # 统计聚合：按查询语句生成全球统计，每个字段返回前 5 排名与去重计数。
    # 官方限制 5 秒 1 次（客户端已自动限速）。
    #
    # @param fields [String] 聚合字段，逗号分隔；可选见 Fofa::STATS_FIELDS
    #   （protocol/domain/port/title/os/server/country/asn/org/asset_type/fid/icp）
    # @return [Hash] size/distinct/aggs/lastupdatetime
    def stats(query, fields: "protocol,port,title", full: false)
      warn_unknown_fields(fields, Fofa::STATS_FIELDS)
      request("/search/stats",
              "key" => @key,
              "qbase64" => self.class.encode_query(query),
              "fields" => fields,
              "full" => full ? "true" : "false")
    end

    # ==================================================================== #
    # 接口 5：Host 聚合  GET /api/v1/host/{host}
    # ==================================================================== #

    # Host 聚合：查询单个 IP（或 host）的资产画像。官方限制 1 秒 1 次（已自动限速）。
    #
    # @param host   [String] 通常为 IP，如 "1.2.3.4"
    # @param detail [Boolean] false 返回端口/协议/分类/产品标签列表（普通模式）；
    #                 true 返回每端口产品详情（产品名/分类/分层 level，5 应用层~0 硬件层）
    # @return [Hash] ip/asn/org/country_name/protocol/port/category/product/update_time
    def get_host(host, detail: false)
      path = "/host/" + URI.encode_www_form_component(host.to_s)
      request(path, "key" => @key, "detail" => detail ? "true" : "false")
    end

    # ==================================================================== #
    # 扩展：IP 被动绑定域名查询（组合 FOFA 多个被动数据源）
    # ==================================================================== #

    # 查询某个 IP 被动绑定过的域名（不主动解析，全部来自 FOFA 测绘观测数据）。
    #
    # 数据来源（自动组合）:
    #   1. 查询接口  ip="x" fields=host,domain,cert
    #      - host  字段: FOFA 观测到的主机名（域名:端口 / 裸域名）
    #      - domain 字段: 观测到的根域名
    #      - cert  字段: TLS 证书原文 -> 提取 SAN/CN 中的域名（证书是最强证据）
    #   2. Host 聚合接口 /host/{ip} 的 domain 域名列表（失败不影响主结果）
    #
    # 若需更全的"历史解析记录"（passive DNS），可另接第三方数据源：
    #   VirusTotal / SecurityTrails / Microsoft Defender TI(RiskIQ) / 微步在线
    #   X 情报 / crt.sh 证书透明度日志；PTR 反查可用 dig -x <ip>。
    #
    # @param ip   [String] 目标 IP
    # @param size [Integer] 查询接口采样条数（含 cert 字段上限 2000）
    # @return [Hash] hosts/domains/cert_domains/all(去重合并)/sources(来源统计)
    def domains_for_ip(ip, size: 1000)
      ip = ip.to_s.strip
      raise Fofa::Error, "ip 不能为空" if ip.empty?

      fields = "host,domain,cert"
      sample = [size.to_i, 2000].min
      hosts = []
      domains = []
      cert_domains = []
      sources = {}

      # 来源 1：查询接口（观测到的 host / domain / cert）
      resp = search(build_query("ip", ip), fields: fields, size: sample, full: true)
      rows = resp["results"] || []
      sources["search/all"] = rows.size
      hosts += rows.map { |r| r[0].to_s }.reject(&:empty?)
      domains += rows.map { |r| r[1].to_s }.reject(&:empty?)
      cert_domains += rows.flat_map { |r| Fofa::Cert.extract_domains(r[2]) }

      # 来源 2：Host 聚合接口的 domain 列表
      begin
        agg = get_host(ip)
        agg_domains = (agg["domain"] || []).map(&:to_s).reject(&:empty?)
        domains += agg_domains
        sources["host"] = agg_domains.size
      rescue Fofa::Error => e
        sources["host"] = e.message # 不影响主结果
      end

      hosts = hosts.uniq.sort
      domains = domains.uniq.sort
      cert_domains = cert_domains.uniq.sort
      {
        "ip" => ip,
        "hosts" => hosts,            # 主机名（host 字段观测值）
        "domains" => domains,        # 根域名（domain 字段 + Host 聚合）
        "cert_domains" => cert_domains, # TLS 证书 SAN/CN 中的域名
        "all" => (hosts + domains + cert_domains).uniq.sort,
        "sources" => sources,
      }
    end

    # ==================================================================== #
    # 常用查询语法便捷方法（search_ip / search_title / search_cert ...）
    # ==================================================================== #

    # 动态生成 search_ip / search_domain / search_host / search_title / search_body
    # / search_header / search_server / search_cert / search_icon_hash / search_product
    # / search_icp / search_org / search_country
    # 用法: client.search_title("后台登录", size: 10, as_dicts: true)
    QUICK_QUERY_FIELDS = %w[ip domain host title body header server cert
                            icon_hash product icp org country].freeze
    QUICK_QUERY_FIELDS.each do |field|
      define_method(:"search_#{field}") do |value, fields: quick_default_fields(field),
                                                          size: 100, page: 1, full: false, as_dicts: false|
        query = build_query(field, value)
        if as_dicts
          search_dicts(query, fields: fields, size: size, page: page, full: full)
        else
          search(query, fields: fields, size: size, page: page, full: full)
        end
      end
    end

    private

    # ------------------------------------------------------------------ #
    # 内部工具
    # ------------------------------------------------------------------ #

    # 构造单条件查询语法: build_query("title", '后台') -> title="后台"
    def build_query(field, value)
      escaped = value.to_s.gsub('"', '\\"')
      %(#{field}="#{escaped}")
    end

    def quick_default_fields(field)
      case field
      when "title", "server", "product", "icp" then "host,ip,port,#{field}"
      else "host,ip,port"
      end
    end

    def warn_unknown_fields(fields, allowed)
      fl = fields.to_s.split(",").map(&:strip).reject(&:empty?)
      bad = fl.reject { |f| allowed.any? { |a| a.casecmp?(f) } }
      return if bad.empty?
      warn "[fofa] 警告: 字段 #{bad.inspect} 不在官方支持列表中，可能报错或无权限"
    end

    def debug_log(msg)
      return unless @debug
      warn "[fofa] #{msg}"
    end

    # /host/1.2.3.4 等动态路径统一归并到 /host 限速键
    def rate_key(path)
      path.start_with?("/host/") ? "/host" : path
    end

    # 按端点独立限速（Mutex + 单调时钟），保证不超出官方频率限制
    def rate_wait!(path, min_interval)
      key = rate_key(path)
      @rate_mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last = @rate_last[key] || 0.0
        sleep(min_interval - (now - last)) if now - last < min_interval
        @rate_last[key] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def http_for(uri)
      if @proxy
        pu = URI.parse(@proxy.to_s)
        http = Net::HTTP.new(uri.host, uri.port, pu.host, pu.port, pu.user, pu.password)
      else
        http = Net::HTTP.new(uri.host, uri.port)
      end
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http
    end

    # 统一请求入口：限速 -> GET -> JSON 解析 -> 业务错误转异常 -> 网络错误重试
    def request(path, params)
      raise Fofa::AuthError, "缺少 FOFA Key" if @key.empty?

      query = params.reject { |_, v| v.nil? }
                   .map { |k, v| "#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v)}" }
                   .join("&")
      uri = URI.parse(@base_url + path)
      uri.query = query unless query.empty?
      rate = Fofa::ENDPOINT_RATE.fetch(rate_key(path), 0.55)

      data = nil
      last_err = nil
      attempts = @max_retries + 1
      attempts.times do |i|
        rate_wait!(path, rate)
        debug_log("GET #{uri}")
        begin
          res = http_for(uri).get(uri.request_uri,
                                  "User-Agent" => "fofa-rb/#{Fofa::VERSION}",
                                  "Accept" => "application/json")
          body = res.body.to_s.dup
          body.force_encoding(Encoding::UTF_8)
          debug_log("HTTP #{res.code} #{body.bytesize}B")
          data = JSON.parse(body)
          break
        rescue JSON::ParserError => e
          last_err = Fofa::NetworkError.new("响应不是合法 JSON: #{e.message}")
        rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError,
               SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED,
               Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
          last_err = Fofa::NetworkError.new("网络错误: #{e.class}: #{e.message}")
        end
        if i < @max_retries
          delay = @backoff * (2**i)
          debug_log("重试 #{i + 1}/#{@max_retries}（#{delay}s 后）")
          sleep(delay)
        end
      end
      raise last_err if data.nil?

      # FOFA 业务错误（error=true）
      if data["error"]
        code = data["code"]
        code = nil unless code.is_a?(Integer)
        msg = data["errmsg"] || data["message"] || data["msg"] ||
              Fofa::ERROR_MESSAGES[code] || "未知错误"
        if [801, 806, 807].include?(code)
          raise Fofa::AuthError.new("[FOFA #{code}] #{msg}")
        end
        raise Fofa::APIError.new(msg, code, data)
      end
      data
    end
  end
end
