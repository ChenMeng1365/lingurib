# frozen_string_literal: true

module Pdns
  # 多数据源配置管理
  #
  # 配置查找链（优先级从高到低）:
  #   1. 环境变量       PDNS_CIRCL_AUTH_TOKEN / PDNS_DNSDB_APIKEY / ...
  #   2. 项目 .env      当前目录 .env 文件（dotenv 风格）
  #   3. 全局配置       ~/.pdns/credentials（推荐，永不进 git）
  #
  # 配置文件格式（dotenv 风格，所有 key 以 PDNS_ 前缀开头）:
  #
  #   # CIRCL
  #   PDNS_CIRCL_AUTH_TOKEN=your_token
  #
  #   # DNSDB
  #   PDNS_DNSDB_APIKEY=your_apikey
  #
  #   # VirusTotal
  #   PDNS_VIRUSTOTAL_APIKEY=your_apikey
  #
  # 环境变量同名会覆盖配置文件中的值。
  module Config
    PREFIX = "PDNS_"

    module_function

    # 解析全部配置，返回 { "PDNS_DNSDB_APIKEY" => "xxx", ... } 形式的哈希
    # @param paths [Array<String>] 配置文件查找路径（可注入用于测试）
    # @return [Hash{String => String}]
    def resolve(paths: default_paths)
      config = {}
      paths.each do |path|
        read_file(path).each { |k, v| config[k] ||= v }
      end
      # 环境变量覆盖文件配置
      ENV.each do |k, v|
        next unless k.to_s.start_with?(PREFIX)
        config[k.to_s] = v.to_s.strip
      end
      config
    end

    # 从全局配置中提取某个数据源的配置子集，去掉前缀
    # @param config [Hash] resolve() 返回的全局配置
    # @param section [String] 数据源配置节名，如 "dnsdb"
    # @return [Hash{String => String}] 如 { "APIKEY" => "xxx" }
    def for_provider(config, section)
      prefix = PREFIX + section.to_s.upcase + "_"
      result = {}
      config.each do |k, v|
        next unless k.to_s.start_with?(prefix)
        result[k.to_s.sub(prefix, "")] = v
      end
      result
    end

    def default_paths
      [
        File.join(Dir.pwd, ".env"),
        File.join(home_dir, ".pdns", "credentials"),
      ]
    end

    def home_dir
      Dir.home
    rescue StandardError
      ENV["USERPROFILE"] || Dir.pwd
    end

    # 读取并解析单个配置文件
    # @return [Hash{String => String}]
    def read_file(path)
      return {} unless path && File.file?(path) && File.readable?(path)

      result = {}
      File.foreach(path, encoding: "UTF-8") do |line|
        parsed = parse_line(line)
        result[parsed[0]] = parsed[1] if parsed
      end
      result
    rescue StandardError
      {}
    end

    # 解析 dotenv 风格的一行
    # 兼容 UTF-8 BOM、注释、引号、行内注释
    # @return [Array(String, String), nil] [key, value] 或 nil
    def parse_line(line)
      line = line.to_s.sub(/\A\uFEFF/, "").strip
      return nil if line.empty? || line.start_with?("#")
      m = line.match(/\A(#{PREFIX}\w+)\s*=\s*(.*)\z/)
      return nil unless m

      key = m[1]
      val = m[2].to_s.strip
      val = val.sub(/\s+#.*\z/, "").strip      # 剥离行内注释
      val = val.sub(/\A["'](.*)["']\z/, '\1')   # 剥离包裹引号
      val.empty? ? nil : [key, val]
    end
  end
end
