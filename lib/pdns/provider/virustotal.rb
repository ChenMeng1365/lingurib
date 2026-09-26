# frozen_string_literal: true

require "net/http"
require "net/https"
require "json"
require "time"
require "openssl"
require_relative "../provider"

module Pdns
  module Provider
    # VirusTotal 被动 DNS 数据库
    # 官网: https://www.virustotal.com
    # 认证: URL 参数 apikey
    # 响应: JSON { resolutions: [{ ip_address, hostname, last_resolved }] }
    class VirusTotal < Base
      def self.display_name; "VirusTotal"; end
      def self.option_letter; "v"; end

      def self.configured?(config)
        !config["APIKEY"].to_s.empty?
      end

      def initialize(config: {}, **opts)
        super
        @apikey = config["APIKEY"] || raise(Pdns::AuthError, "VirusTotal 需要 APIKEY")
        @url    = config["URL"] || "https://www.virustotal.com/vtapi/v2/"
      end

      def lookup(label, limit: nil)
        if ip?(label)
          url = "#{@url}ip-address/report?ip=#{label}&apikey=#{@apikey}"
        else
          url = "#{@url}domain/report?domain=#{URI.encode_www_form_component(label)}&apikey=#{@apikey}"
        end

        t1 = Time.now
        response = http_get(url, headers: { "User-Agent" => ua })

        # VirusTotal 限流时返回 HTTP 204（空响应）
        if response.code.to_i == 204
          debug_log("HTTP 204: 限流，跳过")
          return []
        end

        recs = parse_response(response.body, label, Time.now - t1)
        limit ? recs.first(limit) : recs
      end

      private

      def parse_response(body, query, response_time)
        data = JSON.parse(body.to_s)
        results = []

        Array(data["resolutions"]).each do |row|
          last = parse_time(row["last_resolved"])
          if row["ip_address"]
            results << Pdns::Result.new(
              self.class.display_name, response_time,
              query, row["ip_address"], "A", nil, nil, last, nil
            )
          elsif row["hostname"]
            results << Pdns::Result.new(
              self.class.display_name, response_time,
              row["hostname"], query, "A", nil, nil, last, nil
            )
          end
        end

        if data["response_code"] == 0 && @debug
          debug_log("服务端消息: #{data['verbose_msg']}")
        end

        results
      rescue JSON::ParserError => e
        debug_log("JSON 解析失败: #{e.message}")
        []
      end

      def parse_time(str)
        Time.parse(str.to_s + " +0000")
      rescue ArgumentError
        nil
      end
    end
  end
end
