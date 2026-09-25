# frozen_string_literal: true

module Fofa
  # FOFA 客户端异常体系
  #
  #   Fofa::Error         —— 基础异常
  #   Fofa::AuthError     —— 认证类错误（key 错误 801 / 账号封禁 806 / 过期 807）
  #   Fofa::APIError      —— FOFA 业务错误（响应 error=true，含错误码）
  #   Fofa::NetworkError  —— 网络层错误（超时、DNS、无法连接等）
  class Error < StandardError; end

  class AuthError < Error; end

  class APIError < Error
    # @return [Integer, nil] FOFA 官方错误码（如 801/802/803/-700）
    attr_reader :code
    # @return [Hash] 官方原始响应（error=true 时的完整 JSON）
    attr_reader :payload

    def initialize(message, code = nil, payload = {})
      @code = code
      @payload = payload
      prefix = code ? "[FOFA #{code}] " : ""
      super(prefix + message.to_s)
    end
  end

  class NetworkError < Error; end
end
