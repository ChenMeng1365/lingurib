# frozen_string_literal: true

require_relative "version"
require_relative "errors"
require_relative "result"
require_relative "config"
require_relative "provider"
require_relative "state"

module Pdns
  # 多数据源协调器：并行查询所有已配置的被动 DNS 数据源，结果归一化。
  #
  # 快速上手:
  #   require "pdns"
  #   client = Pdns::Client.new(:dnsdb, :virustotal)
  #   results = client.query("example.com")
  #   results = client.query("1.2.3.4", limit: 100)
  #   results = client.query_recursive("example.com", depth: 2, wait: 1)
  #
  # 使用所有已配置的数据源:
  #   client = Pdns::Client.new(:all)
  class Client
    attr_reader :providers

    # @param names [Array<Symbol, String>] 数据源名称，如 :dnsdb, "virustotal"；:all 自动选择已配置的
    # @param config [Hash, nil] 预解析配置（默认自动从环境变量/文件加载）
    # @param debug [Boolean] 调试模式
    # @param timeout [Integer] 单次请求超时（秒）
    def initialize(*names, config: nil, debug: false, timeout: 20)
      @debug = debug
      @timeout = timeout
      @config = config || Pdns::Config.resolve

      names = available_sections if names.empty? || names.first == :all

      @providers = names.map do |name|
        begin
          instantiate_provider(name.to_s)
        rescue Pdns::AuthError => e
          warn "[pdns] 跳过 #{name}: #{e.message}" if @debug
          nil
        end
      end.compact

      if @providers.empty?
        raise Pdns::AuthError,
              "没有可用的被动 DNS 数据源，请至少配置一个服务的 API Key。\n" \
              "配置方式: 环境变量 PDNS_* 或配置文件 ~/.pdns/credentials\n" \
              "详情请参阅 PDNS.md 文档。"
      end
    end

    # 并行查询所有数据源
    # @param item [String] IP 或域名
    # @param limit [Integer, nil] 每个数据源最大返回条数
    # @return [Array<Pdns::Result>]
    def query(item, limit: nil)
      item = item.to_s.strip
      return [] if item.empty?

      threads = @providers.map do |provider|
        Thread.new(provider) do |p|
          begin
            p.lookup(item, limit: limit)
          rescue Pdns::Error => e
            warn "[pdns] #{p.class.display_name}: #{e.message}" if @debug
            []
          rescue StandardError => e
            warn "[pdns] #{p.class.display_name} 异常: #{e.class}: #{e.message}" if @debug
            []
          end
        end
      end
      threads.flat_map(&:value)
    end

    # 递归查询：查到结果后把 answer/query 加入队列继续查
    # @param item [String] 初始 IP 或域名
    # @param depth [Integer] 递归深度（默认 1 = 不递归）
    # @param limit [Integer, nil] 每数据源每次查询最大返回条数
    # @param wait [Numeric] 每次查询间隔秒数（防止滥用数据源）
    # @return [Array<Pdns::Result>]
    def query_recursive(item, depth: 1, limit: nil, wait: 0)
      state = Pdns::State.new
      state.add(item, 0)
      state.each_pending(max_level: depth) do |q|
        results = query(q, limit: limit)
        results.each { |r| state.add_result(r) }
        sleep wait if wait > 0
      end
      state.results
    end

    # 列出所有已注册的数据源类
    # @return [Array<Class>]
    def self.list_providers
      Pdns::Provider.constants.each_with_object([]) do |const, arr|
        klass = Pdns::Provider.const_get(const)
        next unless klass.is_a?(Class) && klass < Pdns::Provider::Base
        arr << klass
      end
    end

    private

    def available_sections
      self.class.list_providers.each_with_object([]) do |klass, arr|
        pc = Pdns::Config.for_provider(@config, klass.config_section)
        arr << klass.config_section if klass.configured?(pc)
      end
    end

    def instantiate_provider(name)
      klass = self.class.list_providers.find do |k|
        k.config_section == name || k.display_name.casecmp(name).zero?
      end
      raise Pdns::Error, "未知数据源: #{name}" unless klass

      provider_config = Pdns::Config.for_provider(@config, klass.config_section)
      klass.new(config: provider_config, debug: @debug, timeout: @timeout)
    end
  end
end
