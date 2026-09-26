# frozen_string_literal: true

require "net/http"
require "net/https"
require "json"
require "time"
require "openssl"
require_relative "../provider"

module Pdns
  module Provider
    # DNSDB（FarSight Security）被动 DNS 数据库
    # 官网: https://api.dnsdb.info/
    # 认证: X-API-Key 头
    # 响应: NDJSON
    class Dnsdb < Base
      def self.display_name; "DNSDB"; end
      def self.option_letter; "d"; end

      def self.configured?(config)
        !config["APIKEY"].to_s.empty?
      end

      def initialize(config: {}, **opts)
        super
        @apikey = config["APIKEY"] || raise(Pdns::AuthError, "DNSDB 需要 APIKEY")
        @base   = config["URL"] || "https://api.dnsdb.info/lookup"
      end

      def lookup(label, limit: nil)
        if ip?(label)
          label = label.gsub("/", ",")  # CIDR: 1.2.3.0/24 -> 1.2.3.0,24
          url  = "#{@base}/rdata/ip/#{label}"
        else
          url  = "#{@base}/rrset/name/#{label}"
        end
        url << "?limit=#{limit}" if limit

        response = http_get(url, headers: {
          "User-Agent" => ua,
          "X-API-Key"  => @apikey,
          "Accept"     => "application/json",
        })

        t1 = Time.now
        parse_response(response.body, Time.now - t1)
      end

      private

      def parse_response(body, response_time)
        results = []
        body.to_s.each_line do |line|
          line.strip!
          next if line.empty?
          record = JSON.parse(line)
          rrname  = record["rrname"].to_s.sub(/\.\z/, "")
          rrtype  = record["rrtype"]
          first   = record["time_first"] ? Time.at(record["time_first"].to_i) : nil
          last    = record["time_last"]  ? Time.at(record["time_last"].to_i)  : nil
          count   = record["count"]

          answers = record["rdata"]
          answers = [answers] if answers.is_a?(String)
          Array(answers).each do |ans|
            ans = ans.to_s.sub(/\.\z/, "")
            results << Pdns::Result.new(
              self.class.display_name, response_time,
              rrname, ans, rrtype, 0, first, last, count
            )
          end
        end
        results
      rescue JSON::ParserError => e
        debug_log("JSON 解析失败: #{e.message}")
        results
      end
    end
  end
end
