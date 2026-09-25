# frozen_string_literal: true

module Fofa
  # TLS 证书域名提取
  #
  # 用途：IP 被动绑定域名查询（domains_for_ip）。
  # FOFA 的 cert 字段返回 TLS 证书原文，其中 SAN（Subject Alternative Name）
  # 的 DNS 条目与 Subject 的 CN，是"该 IP 被动绑定过哪些域名"最可靠的证据来源之一。
  module Cert
    # 宽松的域名样式校验：允许通配符前缀与多级子域
    DOMAIN_RE = /\A(\*\.)?[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+\z/i.freeze

    module_function

    # 从证书文本中提取所有域名（SAN 的 DNS: 条目 + Subject 的 CN）
    # @param cert_text [String, nil] FOFA cert 字段的证书原文（PEM 或转义文本均可）
    # @return [Array<String>] 去重后的域名列表（小写）
    def extract_domains(cert_text)
      return [] if cert_text.nil?
      text = cert_text.to_s
      return [] if text.empty?

      out = []
      # SAN 条目：DNS:example.com, DNS:*.example.com
      text.scan(/DNS:([^,\s"'\)\]]+)/i) { |m| out << m[0] }
      # Subject 通用名称：CN=example.com
      text.scan(/\bCN\s*=\s*([^,\/\s"']+)/i) { |m| out << m[0] }

      out.map { |d| normalize(d) }.compact.uniq
    end

    # 清洗并校验单个域名，非法值返回 nil
    # @return [String, nil]
    def normalize(domain)
      d = domain.to_s.strip
      return nil if d.empty?
      d = d.sub(/\.\z/, "")                 # 去尾部 FQDN 点
      d = d.gsub(/\A["'\(\[]+/, "").gsub(/["'\)\]]+\z/, "") # 去包裹符号
      return nil if d.empty? || d.length > 253
      return nil unless DOMAIN_RE.match?(d)
      d.downcase
    end
  end
end
