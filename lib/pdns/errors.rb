# frozen_string_literal: true

module Pdns
  # 被动 DNS 客户端异常体系
  #
  #   Pdns::Error         —— 基础异常
  #   Pdns::AuthError     —— 认证类错误（缺少 API Key / 凭据无效）
  #   Pdns::APIError      —— 数据源业务错误（配额耗尽、服务端错误等）
  #   Pdns::NetworkError  —— 网络层错误（超时、DNS、连接拒绝等）
  class Error < StandardError; end

  class AuthError < Error; end

  class APIError < Error
    attr_reader :code, :payload

    def initialize(message, code = nil, payload = {})
      @code = code
      @payload = payload
      super(message.to_s)
    end
  end

  class NetworkError < Error; end
end
