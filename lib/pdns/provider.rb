# frozen_string_literal: true

require "net/http"
require "net/https"
require "uri"
require "json"
require "openssl"
require "socket"
require "time"
require_relative "version"
require_relative "errors"
require_relative "result"
require_relative "config"

module Pdns
  # 数据源命名空间，所有适配器类定义在 Pdns::Provider 下
  module Provider
    # 抽象基类：所有数据源适配器继承此类并实现 #lookup
    #
    # 适配器需实现的类方法:
    #   display_name     短名（如 "CIRCL"），用于结果 source 字段
    #   config_section   配置节名（如 "circl"），默认取 display_name 小写
    #   option_letter    CLI 单字母（如 "c"）
    #   configured?      该数据源是否有可用配置（用于 :all 自动选择）
    #
    # 适配器需实现的实例方法:
    #   lookup(label, limit: nil)  返回 Array<Pdns::Result>
    class Base
      attr_accessor :debug, :timeout
      attr_reader :max_retries, :backoff

      # @param config [Hash] 该数据源的配置（已去掉 PDNS_ 前缀）
      # @param debug [Boolean] 调试模式
      # @param timeout [Integer] 单次请求超时（秒）
      # @param max_retries [Integer] 网络错误自动重试次数
      # @param backoff [Float] 重试基础退避秒数
      def initialize(config: {}, debug: false, timeout: 20, max_retries: 2, backoff: 2.0)
        @debug = debug
        @timeout = timeout.to_i
        @max_retries = max_retries.to_i
        @backoff = backoff.to_f
      end

      class << self
        def display_name
          raise NotImplementedError, "请实现 self.display_name"
        end

        def config_section
          display_name.downcase
        end

        def option_letter
          raise NotImplementedError, "请实现 self.option_letter"
        end

        # 该数据源是否有足够配置可用，子类覆盖
        def configured?(config)
          true
        end
      end

      # 查询，子类必须实现
      # @param label [String] IP 或域名
      # @param limit [Integer, nil] 每数据源最大返回条数
      # @return [Array<Pdns::Result>]
      def lookup(label, limit: nil)
        raise NotImplementedError, "请实现 #lookup"
      end

      protected

      IP_RE = /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(\/\d{1,2})?\z/.freeze

      def ip?(label)
        IP_RE.match?(label.to_s)
      end

      # User-Agent
      def ua
        "pdns-rb/#{Pdns::VERSION}"
      end

      # 统一 HTTP GET 入口：重试 + 错误包装
      # @yield [Net::HTTP::Get] 允许调用方在 request 上追加认证等
      def http_get(url, headers: {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        last_err = nil
        (@max_retries + 1).times do |i|
          begin
            request = Net::HTTP::Get.new(uri.request_uri)
            headers.each { |k, v| request.add_field(k, v) }
            yield request if block_given?
            response = http.request(request)
            debug_log("HTTP #{response.code} #{response.body&.bytesize || 0}B #{url}")
            return response
          rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError,
                 SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED,
                 Errno::EHOSTUNREACH, Errno::ENETUNREACH => e
            last_err = Pdns::NetworkError.new("#{e.class}: #{e.message}")
            debug_log("网络错误 #{e.class}: #{e.message}，#{i < @max_retries ? "重试中" : "放弃"}")
            sleep(@backoff * (2**i)) if i < @max_retries
          end
        end
        raise last_err
      end

      def debug_log(msg)
        warn "[pdns] #{self.class.display_name}: #{msg}" if @debug
      end
    end
  end
end

# 自动加载所有数据源适配器（provider/*.rb）
Dir.glob(File.join(__dir__, "provider", "*.rb")).sort.each do |f|
  require f
end
