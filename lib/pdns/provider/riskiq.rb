# frozen_string_literal: true

require "net/http"
require "net/https"
require "json"
require "time"
require "openssl"
require_relative "../provider"

module Pdns
  module Provider
    # RiskIQ 被动 DNS 数据库
    # 官网: https://community.riskiq.com
    # 认证: Basic Auth (API_TOKEN + API_PRIVATE_KEY)
    # 响应: JSON { records: [{ name, rrtype, data[], firstSeen, lastSeen, count }] }
    class Riskiq < Base
      def self.display_name; "RiskIQ"; end
      def self.option_letter; "r"; end

      def self.configured?(config)
        !config["API_TOKEN"].to_s.empty? && !config["API_PRIVATE_KEY"].to_s.empty?
      end

      def initialize(config: {}, **opts)
        super
        @token   = config["API_TOKEN"]      || raise(Pdns::AuthError, "RiskIQ 需要 API_TOKEN")
        @privkey = config["API_PRIVATE_KEY"] || raise(Pdns::AuthError, "RiskIQ 需要 API_PRIVATE_KEY")
        @server  = config["API_SERVER"] || "ws.riskiq.net"
        @version = (config["API_VERSION"] || "v1").to_s
        @url     = "https://#{@server}/#{@version}"
      end

      def lookup(label, limit: nil)
        if ip?(label)
          url = "#{@url}/dns/data"
          params = { "ip" => label, "rrType" => "", "maxResults" => (limit || 1000).to_s }
        else
          url = "#{@url}/dns/name"
          params = { "name" => label, "rrType" => "", "maxResults" => (limit || 1000).to_s }
        end
        url << "?" + params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join("&")

        t1 = Time.now
        response = http_get(url, headers: {
          "User-Agent"   => ua,
          "Accept"       => "application/json",
          "Content-Type" => "application/json",
        }) do |req|
          req.basic_auth(@token, @privkey)
        end

        recs = parse_response(response.body, Time.now - t1)
        limit ? recs.first(limit) : recs
      end

      private

      def parse_response(body, response_time)
        data = JSON.parse(body.to_s)

        if data["message"].to_s =~ /quota_exceeded/
          debug_log("配额耗尽")
          return []
        end

        results = []
        Array(data["records"]).each do |record|
          name  = record["name"].to_s.sub(/\.\z/, "")
          type  = record["rrtype"]
          first = parse_time(record["firstSeen"])
          last  = parse_time(record["lastSeen"])
          count = record["count"]
          Array(record["data"]).each do |datum|
            results << Pdns::Result.new(
              self.class.display_name, response_time,
              name, datum.to_s.sub(/\.\z/, ""), type, 0,
              first, last, count
            )
          end
        end
        results
      rescue JSON::ParserError => e
        debug_log("JSON 解析失败: #{e.message}")
        []
      end

      def parse_time(str)
        Time.parse(str.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
