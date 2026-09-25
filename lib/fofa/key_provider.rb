# frozen_string_literal: true

module Fofa
  # FOFA Key 查找链（优先级从高到低）:
  #
  #   1. 显式传入     Client.new(key: "xxx") / CLI --key xxx
  #   2. 环境变量     FOFA_KEY
  #   3. 项目 .env    当前目录 .env 文件:  FOFA_KEY=你的key
  #   4. 全局配置     ~/.fofa/credentials: FOFA_KEY=你的key（推荐，永不进 git）
  #
  # 配置文件均为 dotenv 风格，支持注释、空格、引号:
  #
  #   # 这是注释
  #   FOFA_KEY = "你的key"
  #
  # 安全提示: 项目根目录的 .env 会被 git 追踪（本仓库 .gitignore 未忽略它），
  # 请务必将其加入 .gitignore，或直接使用 ~/.fofa/credentials。
  module KeyProvider
    ENV_NAME = "FOFA_KEY"
    FILE_LINE_RE = /\A#{ENV_NAME}\s*=\s*(.*)\z/i

    module_function

    # 查找 key。explicit 显式传入时直接使用；否则按查找链获取。
    # @param explicit [String, nil] 显式传入的 key
    # @param paths [Array<String>] 配置文件查找路径（可注入用于测试）
    # @return [String, nil]
    def resolve(explicit: nil, paths: default_paths)
      v = explicit.to_s.strip
      return v unless v.empty?
      from_env || from_files(Array(paths))
    end

    # @return [String, nil]
    def from_env
      v = ENV[ENV_NAME]
      v.nil? ? nil : v.to_s.strip
    end

    # 按顺序遍历配置文件，取第一个有效值
    # @return [String, nil]
    def from_files(paths)
      paths.each do |path|
        v = from_file(path)
        return v if v && !v.empty?
      end
      nil
    end

    # 从单个配置文件解析 FOFA_KEY
    # @return [String, nil]
    def from_file(path)
      return nil unless path && File.file?(path) && File.readable?(path)

      File.foreach(path, encoding: "UTF-8") do |line|
        v = parse_line(line)
        return v if v
      end
      nil
    rescue StandardError
      nil
    end

    # 解析 dotenv 风格的一行，非 FOFA_KEY 行返回 nil。
    # 兼容 UTF-8 BOM（Windows 编辑器/Powershell 写出的文件常带 BOM）。
    # @return [String, nil]
    def parse_line(line)
      line = line.to_s.sub(/\A\uFEFF/, "").strip
      return nil if line.empty? || line.start_with?("#")
      return nil unless (m = FILE_LINE_RE.match(line))

      val = m[1].to_s.strip
      val = val.sub(/\s+#.*\z/, "").strip # 剥离行内注释: FOFA_KEY=xxx # comment
      val = val.sub(/\A["'](.*)["']\z/, '\1') # 剥离包裹引号
      val.empty? ? nil : val
    end

    # 默认查找路径: 当前目录 .env -> 用户主目录 ~/.fofa/credentials
    def default_paths
      [
        File.join(Dir.pwd, ".env"),
        File.join(home_dir, ".fofa", "credentials"),
      ]
    end

    def home_dir
      Dir.home
    rescue StandardError
      ENV["USERPROFILE"] || Dir.pwd
    end
  end
end
