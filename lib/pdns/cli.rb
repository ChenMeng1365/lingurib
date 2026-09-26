# frozen_string_literal: true

require "json"
require "csv"
require "optparse"
require_relative "client"
require_relative "selftest"

module Pdns
  # 命令行工具
  #
  #   pdns query example.com -d dv --json        查询
  #   pdns query 1.2.3.4 -d dnsdb --limit 100    限制条数
  #   pdns recursive example.com --depth 2      递归查询
  #   pdns providers                              列出可用数据源
  #   pdns --selftest                            内置自检（不联网）
  module CLI
    module_function

    # @return [Integer] 进程退出码
    def run(argv)
      global = {}
      parser = OptionParser.new do |op|
        op.banner = "Passive DNS 命令行工具\n" \
                    "\n用法: pdns [全局选项] <命令> [选项]\n" \
                    "\n命令:\n" \
                    "  query <ip|domain>     [-d cdprv] [--limit N] [--json|--csv FILE]  查询\n" \
                    "  recursive <ip|domain> [--depth N] [--wait N] [--limit N]      递归查询\n" \
                    "  providers                                                    列出数据源\n" \
                    "\n全局选项:"
        op.on("-d", "--providers X", "数据源字母组合（如 cdprv）或逗号分隔名称（如 dnsdb,virustotal）") { |v| global[:providers] = v }
        op.on("--limit N", Integer, "每数据源最大返回条数") { |v| global[:limit] = v }
        op.on("--json", "JSON 格式输出") { global[:json] = true }
        op.on("--csv FILE", "导出 CSV 文件") { |v| global[:csv] = v }
        op.on("--config FILE", "配置文件路径") { |v| global[:configfile] = v }
        op.on("--debug", "调试日志") { global[:debug] = true }
        op.on("--selftest", "运行内置自检（不联网）") { global[:selftest] = true }
        op.on("-h", "--help", "显示帮助") { puts op; return 0 }
      end

      begin
        parser.order!(argv)
      rescue OptionParser::InvalidOption => e
        warn "[pdns] 参数错误: #{e.message}（用 --help 查看用法）"
        return 1
      end

      return Pdns::SelfTest.run if global[:selftest]

      cmd = argv.shift
      if cmd.nil?
        puts parser
        return 0
      end

      case cmd
      when "providers"
        cmd_providers
      when "query"
        cmd_query(argv, global)
      when "recursive"
        cmd_recursive(argv, global)
      else
        warn "[pdns] 未知命令: #{cmd}（用 --help 查看用法）"
        return 1
      end
    rescue Pdns::AuthError => e
      warn "[pdns] 认证错误: #{e.message}"
      2
    rescue Pdns::APIError => e
      warn "[pdns] API 错误: #{e.message}"
      4
    rescue Pdns::NetworkError => e
      warn "[pdns] 网络错误: #{e.message}"
      5
    rescue Interrupt
      warn "\n[pdns] 用户中断"
      130
    end

    # ---------------------------------------------------------------- #

    def cmd_providers
      puts "已注册的被动 DNS 数据源:"
      Pdns::Client.list_providers.each do |klass|
        cfg = Pdns::Config.for_provider(Pdns::Config.resolve, klass.config_section)
        status = klass.configured?(cfg) ? "已配置" : "未配置"
        puts "  -d#{klass.option_letter}  #{klass.display_name.ljust(14)} [#{status}]"
      end
      0
    end

    def cmd_query(args, global)
      opts = parse_recursive_opts(args)
      item = args.shift || raise(Pdns::Error, "缺少参数 <ip|domain>")
      client = build_client(global)
      results = client.query(item, limit: global[:limit] || opts[:limit])
      output_results(results, global, opts)
      0
    end

    def cmd_recursive(args, global)
      opts = parse_recursive_opts(args)
      item = args.shift || raise(Pdns::Error, "缺少参数 <ip|domain>")
      client = build_client(global)
      depth = opts[:depth] || 1
      if depth > 3
        warn "[pdns] 警告: 递归深度 > 3 会对数据源造成压力，请谨慎使用"
        sleep 3
      end
      results = client.query_recursive(item, depth: depth, limit: global[:limit], wait: opts[:wait])
      output_results(results, global, opts)
      0
    end

    # ---------------------------------------------------------------- #

    private

    def parse_recursive_opts(args)
      opts = { depth: 1, wait: 0, limit: nil }
      OptionParser.new do |op|
        op.on("--depth N", Integer, "递归深度（默认 1）") { |v| opts[:depth] = v }
        op.on("--wait N", Integer, "查询间隔秒数（默认 0）") { |v| opts[:wait] = v }
        op.on("--limit N", Integer, "每数据源最大返回条数") { |v| opts[:limit] = v }
      end.order!(args)
      opts
    end

    def build_client(global)
      names = parse_providers(global[:providers])
      config = global[:configfile] ? load_custom_config(global[:configfile]) : nil
      Pdns::Client.new(*names, config: config, debug: global[:debug])
    end

    def parse_providers(spec)
      return [:all] unless spec
      # 支持逗号分隔名称（dnsdb,virustotal）
      return spec.split(",").map(&:strip) if spec.include?(",")
      # 支持字母组合（cdprv）
      letter_map = {}
      Pdns::Client.list_providers.each { |k| letter_map[k.option_letter] = k.config_section }
      spec.chars.map { |c| letter_map[c] }.compact
    end

    def load_custom_config(path)
      Pdns::Config.resolve(paths: [path])
    end

    def output_results(results, global, opts)
      if global[:csv]
        write_csv(global[:csv], results)
        puts "已导出 #{results.size} 条到 #{global[:csv]}"
      elsif global[:json]
        puts JSON.pretty_generate(results.map(&:to_h))
      else
        puts Pdns::Result.header
        results.each { |r| puts r.to_s }
      end
    end

    def write_csv(path, results)
      require "csv"
      CSV.open(path, "w", encoding: "bom|utf-8") do |csv|
        csv << %w[source query answer rrtype ttl firstseen lastseen count]
        results.each { |r| csv << r.to_csv_row }
      end
    end
  end
end
