# frozen_string_literal: true

require_relative "version"
require_relative "config"
require_relative "result"
require_relative "provider"
require_relative "state"
require_relative "client"

module Pdns
  # 内置自检（不联网）：验证配置解析、IP 判定、结果结构、状态管理、数据源注册
  module SelfTest
    module_function

    # @return [Integer] 0 全部通过；1 存在失败
    def run
      passed = []
      failed = []

      check = lambda do |name, cond|
        cond ? passed << name : failed << name
        puts "  [#{cond ? 'PASS' : 'FAIL'}] #{name}"
      end

      # 1. 配置解析
      check.call("Config 解析 PDNS_DNSDB_APIKEY=xxx",
                 Pdns::Config.parse_line("PDNS_DNSDB_APIKEY=abc123") == ["PDNS_DNSDB_APIKEY", "abc123"])
      check.call("Config 解析引号与空格",
                 Pdns::Config.parse_line('PDNS_CIRCL_AUTH_TOKEN = "abc 123"') == ["PDNS_CIRCL_AUTH_TOKEN", "abc 123"])
      check.call("Config 忽略注释",
                 Pdns::Config.parse_line("# PDNS_DNSDB_APIKEY=no").nil? &&
                 Pdns::Config.parse_line("OTHER=nope").nil?)
      check.call("Config 剥离行内注释",
                 Pdns::Config.parse_line("PDNS_DNSDB_APIKEY=k # comment") == ["PDNS_DNSDB_APIKEY", "k"])
      check.call("Config for_provider 提取子集",
                 Pdns::Config.for_provider({ "PDNS_DNSDB_APIKEY" => "x", "PDNS_VT_KEY" => "y" }, "dnsdb") ==
                 { "APIKEY" => "x" })

      # 2. IP 判定
      base = Pdns::Provider::Base.allocate
      check.call("IP 判定 1.2.3.4", base.send(:ip?, "1.2.3.4"))
      check.call("IP 判定 CIDR 1.2.3.0/24", base.send(:ip?, "1.2.3.0/24"))
      check.call("非IP判定 example.com", !base.send(:ip?, "example.com"))

      # 3. Result 结构体
      r = Pdns::Result.new("DNSDB", 0.5, "example.com", "1.2.3.4", "A", 0,
                           Time.parse("2024-01-01"), Time.parse("2024-06-01"), 42)
      check.call("Result to_h 字符串键", r.to_h["source"] == "DNSDB" && r.to_h["query"] == "example.com")
      check.call("Result to_json 包含字段", JSON.parse(r.to_json)["answer"] == "1.2.3.4")
      check.call("Result to_csv_row 8 列", r.to_csv_row.size == 8)
      check.call("Result header 8 列", Pdns::Result.header.split("\t").size == 8)

      # 4. State 状态管理
      s = Pdns::State.new
      s.add("example.com", 0)
      s.add("example.com", 0)  # 去重
      yielded = []
      s.each_pending(max_level: 2) { |q| yielded << q }
      check.call("State 去重 + 遍历", yielded == ["example.com"])
      check.call("State 结果为空", s.results.empty?)

      # 5. State 递归逻辑
      s2 = Pdns::State.new
      s2.add("a.com", 0)
      query_count = 0
      s2.each_pending(max_level: 2) do |q|
        query_count += 1
        s2.add_result(Pdns::Result.new("TEST", 0.1, q, "1.2.3.4", "A", nil, nil, nil, nil))
      end
      # level 0: a.com -> 1.2.3.4 (answer), level 1: 1.2.3.4 -> 1.2.3.4 (answer, 去重)
      check.call("State 递归展开 2 层", query_count == 2)
      check.call("State 递归结果 2 条", s2.results.size == 2)

      # 6. 数据源注册
      providers = Pdns::Client.list_providers
      check.call("已注册 5 个数据源", providers.size == 5)
      check.call("CIRCL 已注册", providers.any? { |k| k.display_name == "CIRCL" })
      check.call("DNSDB 已注册", providers.any? { |k| k.display_name == "DNSDB" })
      check.call("VirusTotal 已注册", providers.any? { |k| k.display_name == "VirusTotal" })
      check.call("PassiveTotal 已注册", providers.any? { |k| k.display_name == "PassiveTotal" })
      check.call("RiskIQ 已注册", providers.any? { |k| k.display_name == "RiskIQ" })

      # 7. 数据源 option_letter 唯一
      letters = providers.map(&:option_letter)
      check.call("option_letter 唯一", letters.size == letters.uniq.size)

      total = passed.size + failed.size
      puts "\n自检结果: #{passed.size}/#{total} 通过#{failed.empty? ? '' : "（失败: #{failed.inspect}）"}"
      failed.empty? ? 0 : 1
    end
  end
end
