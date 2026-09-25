# frozen_string_literal: true

module Fofa
  # 内置自检（不联网）：验证编码、限速钳制、结果映射、证书提取、异常结构
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

      # 1. base64 编码（对齐官方文档示例）
      check.call("encode_query 官方示例",
                 Fofa::Client.encode_query('ip="103.35.168.38"') == "aXA9IjEwMy4zNS4xNjguMzgi")
      # 2. 中文编码稳定性
      decoded = Base64.strict_decode64(Fofa::Client.encode_query('title="百度"'))
      decoded = decoded.force_encoding(Encoding::UTF_8)
      check.call("encode_query 中文", decoded == 'title="百度"')
      # 3. size 钳制规则
      v = Fofa::Client.method(:validate_size)
      check.call("size 默认 100", v.call("ip,port", nil) == 100)
      check.call("size body<=500", v.call("ip,body", 5000) == 500)
      check.call("size cert<=2000", v.call("cert,ip", 5000) == 2000)
      check.call("size banner<=2000", v.call("banner", 9999) == 2000)
      check.call("size 普通<=10000", v.call("ip,port", 99999) == 10000)
      # 4. 二维结果 -> Hash 映射
      d = Fofa::Client.rows_to_dicts("ip,port,host", [["1.1.1.1", "80", "a.com"]])
      check.call("rows_to_dicts", d == [{ "ip" => "1.1.1.1", "port" => "80", "host" => "a.com" }])
      # 5. 证书域名提取（IP 被动绑定域名的核心解析）
      cert = <<~CERT
        Certificate:
            Data:
                Version: 3 (0x2)
                Subject: CN=www.example.com, O=Example Inc
                Subject Alternative Name:
                    DNS:www.example.com, DNS:example.com, DNS:*.cdn.example.com
      CERT
      cdomains = Fofa::Cert.extract_domains(cert)
      check.call("cert 提取 SAN+CN",
                 cdomains.sort == ["*.cdn.example.com", "example.com", "www.example.com"].sort)
      check.call("cert 过滤非法项",
                 Fofa::Cert.extract_domains("CN=Example Inc").empty?)
      # 6. 无任何 key 来源时报 AuthError（lookup: false 隔离环境变量/配置文件）
      begin
        Fofa::Client.new(key: "", lookup: false)
        check.call("无 key 抛 AuthError", false)
      rescue Fofa::AuthError
        check.call("无 key 抛 AuthError", true)
      rescue StandardError
        check.call("无 key 抛 AuthError", false)
      end
      # 6b. key 查找链：dotenv 风格行解析
      check.call("KeyProvider 解析 FOFA_KEY=xxx",
                 Fofa::KeyProvider.parse_line("FOFA_KEY=abc123") == "abc123")
      check.call("KeyProvider 解析引号/空格",
                 Fofa::KeyProvider.parse_line('FOFA_KEY = "abc 123"') == "abc 123")
      check.call("KeyProvider 忽略注释与其它变量",
                 Fofa::KeyProvider.parse_line("# FOFA_KEY=no\n").nil? &&
                 Fofa::KeyProvider.parse_line("OTHER=nope").nil?)
      check.call("KeyProvider 剥离行内注释",
                 Fofa::KeyProvider.parse_line("FOFA_KEY=k # comment") == "k")
      # 7. 字段清单与官方文档附录一致
      check.call("查询字段共 51 个", Fofa::FIELDS.size == 51)
      check.call("统计字段共 12 个", Fofa::STATS_FIELDS.size == 12)

      total = passed.size + failed.size
      puts "\n自检结果: #{passed.size}/#{total} 通过#{failed.empty? ? '' : "（失败: #{failed.inspect}）"}"
      failed.empty? ? 0 : 1
    end
  end
end
