# frozen_string_literal: true

require "net/http"
require "net/https"
require "json"
require "time"
require "openssl"
require_relative "../provider"

module Pdns
  module Provider
    # CIRCL 被动 DNS 数据库
    # 官网: https://www.circl.lu/services/passive-dns/
    # 认证: AUTH_TOKEN（Authorization 头）或 USERNAME + PASSWORD（Basic Auth）
    # 响应: NDJSON（每行一个 JSON 对象）
    class Circl < Base
      def self.display_name; "CIRCL"; end
      def self.option_letter; "c"; end

      def self.configured?(config)
        !!config["AUTH_TOKEN"] || (!config["USERNAME"].to_s.empty? && !config["PASSWORD"].to_s.empty?)
      end

      def initialize(config: {}, **opts)
        super
        @auth_token = config["AUTH_TOKEN"]
        @username   = config["USERNAME"]
        @password   = config["PASSWORD"]
        @url        = config["URL"] || "https://www.circl.lu/pdns/query"
        unless @auth_token || (@username && @password)
          raise Pdns::AuthError, "CIRCL 需要 AUTH_TOKEN 或 USERNAME+PASSWORD"
        end
      end

      def lookup(label, limit: nil)
        recs = []
        url = "#{@url}/#{label}"
        headers = { "User-Agent" => ua, "Accept" => "application/json" }

        response = http_get(url, headers: headers) do |req|
          if @auth_token
            req.add_field("Authorization", @auth_token)
          else
            req.basic_auth(@username, @password)
          end
        end

        t1 = Time.now
        # CIRCL 在限流时返回明文 "Rate Limit Exceeded"，最多重试 5 次
        5.times do
          body = response.body.to_s
          break unless body.strip == "Rate Limit Exceeded"
          sleep 1
          response = http_get(url, headers: headers) do |req|
            if @auth_token
              req.add_field("Authorization", @auth_token)
            else
              req.basic_auth(@username, @password)
            end
          end
        end

        response_time = Time.now - t1
        recs = parse_response(response.body, response_time)
        limit ? recs.first(limit) : recs
      end

      private

      def parse_response(body, response_time)
        results = []
        body.to_s.each_line do |line|
          line.strip!
          next if line.empty?
          row = JSON.parse(line)
          results << Pdns::Result.new(
            self.class.display_name, response_time,
            row["rrname"], row["rdata"], row["rrtype"], 0,
            Time.at(row["time_first"].to_i), Time.at(row["time_last"].to_i),
            row["count"]
          )
        end
        results
      rescue JSON::ParserError => e
        debug_log("JSON 解析失败: #{e.message}")
        results
      end
    end
  end
end
