# frozen_string_literal: true

require "net/http"
require "net/https"
require "json"
require "time"
require "openssl"
require_relative "../provider"

module Pdns
  module Provider
    # PassiveTotal 被动 DNS 数据库
    # 官网: https://www.passivetotal.org
    # 认证: Basic Auth (USERNAME + APIKEY)
    # 响应: JSON { results: [{ resolve, firstSeen, lastSeen, source }] }
    class PassiveTotal < Base
      def self.display_name; "PassiveTotal"; end
      def self.option_letter; "p"; end

      def self.configured?(config)
        !config["USERNAME"].to_s.empty? && !config["APIKEY"].to_s.empty?
      end

      def initialize(config: {}, **opts)
        super
        @username = config["USERNAME"] || raise(Pdns::AuthError, "PassiveTotal 需要 USERNAME")
        @apikey   = config["APIKEY"]   || raise(Pdns::AuthError, "PassiveTotal 需要 APIKEY")
        @url      = config["URL"] || "https://api.passivetotal.org/v2/dns/passive"
      end

      def lookup(label, limit: nil)
        url = "#{@url}?query=#{URI.encode_www_form_component(label)}"
        t1  = Time.now

        response = http_get(url, headers: { "User-Agent" => ua }) do |req|
          req.basic_auth(@username, @apikey)
        end

        recs = parse_response(response.body, Time.now - t1)
        limit ? recs.first(limit) : recs
      end

      private

      def parse_response(body, response_time)
        data = JSON.parse(body.to_s)
        raise Pdns::APIError, data["message"].to_s if data["message"]

        query_val = data["queryValue"]
        Array(data["results"]).map do |row|
          first_seen = parse_time(row["firstSeen"])
          last_seen  = parse_time(row["lastSeen"])
          Pdns::Result.new(
            self.class.display_name, response_time,
            query_val, row["resolve"], "A", 0,
            first_seen, last_seen, nil
          )
        end
      rescue JSON::ParserError => e
        debug_log("JSON 解析失败: #{e.message}")
        []
      end

      def parse_time(str)
        return nil if str.nil? || str == "None"
        Time.parse(str.to_s + " +0000")
      rescue ArgumentError
        nil
      end
    end
  end
end
