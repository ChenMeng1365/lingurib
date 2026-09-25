# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fofa"

# FOFA 客户端单元测试（不联网）
# 运行: ruby -Ilib spec/fofa_spec.rb
class TestFofa < Minitest::Test
  def setup
    # 隔离环境变量，避免本机配置影响测试
    ENV.delete("FOFA_KEY")
  end

  def teardown
    ENV.delete("FOFA_KEY")
  end
  def test_encode_query_official_example
    # 官方文档示例: ip="103.35.168.38" -> aXA9IjEwMy4zNS4xNjguMzgi
    assert_equal "aXA9IjEwMy4zNS4xNjguMzgi",
                 Fofa::Client.encode_query('ip="103.35.168.38"')
  end

  def test_encode_query_chinese
    decoded = Base64.strict_decode64(Fofa::Client.encode_query('title="百度"'))
    decoded.force_encoding(Encoding::UTF_8)
    assert_equal 'title="百度"', decoded
  end

  def test_validate_size
    v = Fofa::Client.method(:validate_size)
    assert_equal 100, v.call("ip,port", nil)       # 默认 100
    assert_equal 500, v.call("ip,body", 5000)      # body 上限 500
    assert_equal 2000, v.call("cert,ip", 5000)     # cert 上限 2000
    assert_equal 2000, v.call("banner", 9999)       # banner 上限 2000
    assert_equal 10000, v.call("ip,port", 99999)   # 普通上限 10000
    assert_equal 1, v.call("ip", -5)                # 非法值兜底
  end

  def test_rows_to_dicts
    d = Fofa::Client.rows_to_dicts("ip,port,host", [["1.1.1.1", "80", "a.com"]])
    assert_equal [{ "ip" => "1.1.1.1", "port" => "80", "host" => "a.com" }], d
  end

  def test_cert_extract_domains
    cert = <<~CERT
      Certificate:
          Data:
              Subject: CN=www.example.com, O=Example Inc
              Subject Alternative Name:
                  DNS:www.example.com, DNS:example.com, DNS:*.cdn.example.com
    CERT
    domains = Fofa::Cert.extract_domains(cert)
    assert_equal ["*.cdn.example.com", "example.com", "www.example.com"], domains.sort
  end

  def test_cert_filters_non_domain
    assert_empty Fofa::Cert.extract_domains("CN=Example Inc")
    assert_empty Fofa::Cert.extract_domains(nil)
    assert_empty Fofa::Cert.extract_domains("")
  end

  def test_no_key_raises_auth_error
    error = assert_raises(Fofa::AuthError) { Fofa::Client.new(key: "", lookup: false) }
    assert_match(/FOFA Key/, error.message)
  end

  def test_key_provider_explicit_priority
    ENV["FOFA_KEY"] = "env_key"
    assert_equal "explicit_key", Fofa::KeyProvider.resolve(explicit: "explicit_key")
  end

  def test_key_provider_env_over_file
    ENV["FOFA_KEY"] = "env_key"
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      File.write(path, "FOFA_KEY=file_key\n")
      assert_equal "env_key", Fofa::KeyProvider.resolve(paths: [path])
    end
  end

  def test_key_provider_from_env_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      File.write(path, "# 注释\nFOFA_KEY = \"file_key\"\nOTHER=nope\n")
      assert_equal "file_key", Fofa::KeyProvider.resolve(paths: [path])
    end
  end

  def test_key_provider_file_priority_order
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.env")
      b = File.join(dir, "b.env")
      File.write(a, "FOFA_KEY=first\n")
      File.write(b, "FOFA_KEY=second\n")
      assert_equal "first", Fofa::KeyProvider.resolve(paths: [a, b])
    end
  end

  def test_key_provider_inline_comment_and_quotes
    assert_equal "k", Fofa::KeyProvider.parse_line("FOFA_KEY=k # comment")
    assert_equal "abc 123", Fofa::KeyProvider.parse_line("FOFA_KEY='abc 123'")
    assert_nil Fofa::KeyProvider.parse_line("# FOFA_KEY=no")
    assert_nil Fofa::KeyProvider.parse_line("OTHER=nope")
    assert_nil Fofa::KeyProvider.parse_line("FOFA_KEY=")
  end

  def test_key_provider_missing_file_returns_nil
    missing = File.join(Dir.tmpdir, "fofa_not_exist_#{Process.pid}.env")
    assert_nil Fofa::KeyProvider.resolve(paths: [missing])
  end

  def test_key_provider_handles_utf8_bom
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".env")
      File.binwrite(path, "\xEF\xBB\xBFFOFA_KEY=bom_key\n") # UTF-8 BOM 开头
      assert_equal "bom_key", Fofa::KeyProvider.resolve(paths: [path])
    end
  end

  def test_fields_match_official_appendix
    assert_equal 51, Fofa::FIELDS.size       # 附录 1：51 个查询字段
    assert_equal 12, Fofa::STATS_FIELDS.size # 附录 2：12 个统计字段
    %w[ip port host domain title cert body icon_hash product icp].each do |f|
      assert_includes Fofa::FIELDS, f, "缺少常用字段 #{f}"
    end
  end

  def test_api_error_carries_code_and_payload
    e = Fofa::APIError.new("F点不足", 803, { "error" => true })
    assert_equal 803, e.code
    assert_equal "[FOFA 803] F点不足", e.message
    assert_equal true, e.payload["error"]
  end

  def test_endpoint_rate_official_limits
    assert_equal 5.0, Fofa::ENDPOINT_RATE["/search/stats"] # stats 5秒/次
    assert_equal 1.0, Fofa::ENDPOINT_RATE["/host"]         # host 1秒/次
    assert_operator Fofa::ENDPOINT_RATE["/search/all"], :>=, 0.5 # 2次/s -> 间隔>=0.5s
  end
end
