# frozen_string_literal: true

require "optparse"
require "json"
require "csv"
require_relative "client"
require_relative "selftest"

module Fofa
  # 命令行工具
  #
  #   fofa info                                        账号信息与配额
  #   fofa search 'title="test"' --size 10 --json      资产搜索
  #   fofa count 'domain="example.com"'               结果总量
  #   fofa stats 'domain="example.com"'                统计聚合（前5排名）
  #   fofa host 1.2.3.4 --detail                        单 IP 画像
  #   fofa domains 1.2.3.4                              IP 被动绑定域名
  #   fofa all 'app="Apache"' --max 2000 --csv out.csv 连续翻页批量拉取
  #
  #   key 来自 --key 或环境变量 FOFA_KEY
  module CLI
    module_function

    # @return [Integer] 进程退出码：0 正常；1 参数错误；2 缺 key；3 认证错误；4 API 错误；5 网络错误
    def run(argv)
      global = {}
      parser = OptionParser.new do |op|
        op.banner = "FOFA API 命令行工具\n" \
                    "\n用法: fofa [全局选项] <命令> [选项]\n" \
                    "\n命令:\n" \
                    "  info                                        账号信息与配额\n" \
                    "  search <query>     [--fields --size --page --full --json] 资产搜索\n" \
                    "  count <query>                               结果总量\n" \
                    "  stats <query>      [--fields --full]        统计聚合（前5排名）\n" \
                    "  host <ip>          [--detail]             单 IP 画像\n" \
                    "  domains <ip>       [--size]                IP 被动绑定域名\n" \
                    "  all <query>        [--fields --size --max --csv]      批量拉取\n" \
                    "  --selftest                                  内置自检（不联网）\n" \
                    "\nkey 配置（优先级从高到低）:\n" \
                    "  1. --key 参数\n" \
                    "  2. 环境变量 FOFA_KEY\n" \
                    "  3. 项目根目录 .env:       FOFA_KEY=你的key\n" \
                    "  4. ~/.fofa/credentials:   FOFA_KEY=你的key（推荐，不会进 git）\n" \
                    "\n示例:\n" \
                    '  fofa search "title=\"后台登录\"" --size 10' + "\n" \
                    '  fofa domains 1.2.3.4' + "\n" \
                    '  fofa all "app=\"Apache\"" --max 2000 --csv out.csv' + "\n" \
                    "\n全局选项:"
        op.on("--key KEY", "FOFA Key（未指定时依次查找: 环境变量 FOFA_KEY -> ./.env -> ~/.fofa/credentials）") { |v| global[:key] = v }
        op.on("--proxy URL", "HTTP(S) 代理，如 http://127.0.0.1:8080") { |v| global[:proxy] = v }
        op.on("--debug", "打印调试日志") { global[:debug] = true }
        op.on("--selftest", "运行内置自检（不联网）") { global[:selftest] = true }
        op.on("-h", "--help", "显示帮助") { puts op; return 0 }
      end

      begin
        parser.order!(argv)
      rescue OptionParser::InvalidOption => e
        warn "[fofa] 参数错误: #{e.message}（用 --help 查看用法）"
        return 1
      end

      return Fofa::SelfTest.run if global[:selftest]

      cmd = argv.shift
      if cmd.nil?
        puts parser
        return 0
      end

      client =
        begin
          Fofa::Client.new(key: global[:key], proxy: global[:proxy], debug: global[:debug])
        rescue Fofa::AuthError => e
          warn "[fofa] #{e.message}"
          return 2
        end

      dispatch(client, cmd, argv.dup)
    rescue Fofa::AuthError => e
      warn "[fofa] 认证错误: #{e.message}"
      3
    rescue Fofa::APIError => e
      warn "[fofa] API 错误: #{e.message}"
      4
    rescue Fofa::NetworkError => e
      warn "[fofa] 网络错误: #{e.message}"
      5
    rescue Interrupt
      warn "\n[fofa] 用户中断"
      130
    end

    def dispatch(client, cmd, args)
      case cmd
      when "info"   then puts pretty(client.user_info)
      when "count"  then puts client.count(required_arg(args, "query", cmd))
      when "search" then cmd_search(client, args)
      when "stats"  then cmd_stats(client, args)
      when "host"   then cmd_host(client, args)
      when "domains" then cmd_domains(client, args)
      when "all"    then cmd_all(client, args)
      else
        warn "[fofa] 未知命令: #{cmd}（用 --help 查看用法）"
        return 1
      end
      0
    end

    # ------------------------------------------------------------------ #

    def cmd_search(client, args)
      opts = { fields: "host,ip,port", size: 100, page: 1, full: false, json: false }
      OptionParser.new do |op|
        op.banner = "用法: fofa search <query> [选项]"
        op.on("--fields F", "返回字段，逗号分隔（默认 host,ip,port）") { |v| opts[:fields] = v }
        op.on("--size N", Integer, "每页数量（默认 100）") { |v| opts[:size] = v }
        op.on("--page N", Integer, "页码（默认 1）") { |v| opts[:page] = v }
        op.on("--full", "搜索全部历史数据") { opts[:full] = true }
        op.on("--json", "输出完整 JSON（默认简表）") { opts[:json] = true }
      end.order!(args)
      query = required_arg(args, "query", "search")

      resp = client.search(query, fields: opts[:fields], size: opts[:size],
                           page: opts[:page], full: opts[:full])
      if opts[:json]
        puts pretty(resp)
      else
        puts "总量: #{resp['size']}  当前页: #{resp['page']}  本页: #{(resp['results'] || []).size} 条  扣费: #{resp['consumed_fpoint'] || '-'} F点"
        (resp["results"] || []).each { |row| puts "  #{row.join('  |  ')}" }
      end
    end

    def cmd_stats(client, args)
      opts = { fields: "protocol,port,title", full: false }
      OptionParser.new do |op|
        op.banner = "用法: fofa stats <query> [选项]"
        op.on("--fields F", "聚合字段，逗号分隔") { |v| opts[:fields] = v }
        op.on("--full", "搜索全部历史数据") { opts[:full] = true }
      end.order!(args)
      query = required_arg(args, "query", "stats")
      puts pretty(client.stats(query, fields: opts[:fields], full: opts[:full]))
    end

    def cmd_host(client, args)
      detail = false
      OptionParser.new do |op|
        op.banner = "用法: fofa host <ip> [选项]"
        op.on("--detail", "显示端口产品详情") { detail = true }
      end.order!(args)
      host = required_arg(args, "ip", "host")
      puts pretty(client.get_host(host, detail: detail))
    end

    def cmd_domains(client, args)
      size = 1000
      OptionParser.new do |op|
        op.banner = "用法: fofa domains <ip> [选项]  —— IP 被动绑定域名查询"
        op.on("--size N", Integer, "采样条数（默认 1000，上限 2000）") { |v| size = v }
      end.order!(args)
      ip = required_arg(args, "ip", "domains")
      puts pretty(client.domains_for_ip(ip, size: size))
    end

    def cmd_all(client, args)
      opts = { fields: "host,ip,port", size: 1000, recent: false,
               max: nil, csv: nil }
      OptionParser.new do |op|
        op.banner = "用法: fofa all <query> [选项]"
        op.on("--fields F", "返回字段，逗号分隔") { |v| opts[:fields] = v }
        op.on("--size N", Integer, "每批数量（默认 1000）") { |v| opts[:size] = v }
        op.on("--recent", "仅搜索一年内数据（默认全部历史数据）") { opts[:recent] = true }
        op.on("--max N", Integer, "最多拉取条数") { |v| opts[:max] = v }
        op.on("--csv FILE", "导出 CSV 文件路径") { |v| opts[:csv] = v }
      end.order!(args)
      query = required_arg(args, "query", "all")

      rows = []
      n = 0
      client.search_iter(query, fields: opts[:fields], size: opts[:size],
                         full: !opts[:recent], max_records: opts[:max]).each do |row|
        rows << row
        n += 1
        warn "\r[fofa] 已拉取 #{n} 条..." if (n % 1000).zero?
      end

      if opts[:csv]
        write_csv(opts[:csv], opts[:fields], rows)
        puts "已导出 #{n} 条到 #{opts[:csv]}"
      else
        puts pretty({ "total_fetched" => n, "results" => rows })
      end
    end

    # ------------------------------------------------------------------ #

    def required_arg(args, name, cmd)
      args.shift || (raise Fofa::Error, "缺少参数 <#{name}>（用法见: fofa #{cmd} --help）")
    end

    def pretty(obj)
      JSON.pretty_generate(obj)
    end

    # UTF-8 BOM，Excel 打开中文不乱码
    def write_csv(path, fields, rows)
      names = fields.to_s.split(",").map(&:strip).reject(&:empty?)
      CSV.open(path, "w", encoding: "bom|utf-8") do |csv|
        csv << names
        rows.each { |row| csv << row }
      end
    end
  end
end
