# frozen_string_literal: true

require "json"
require "time"

module Pdns
  # 统一结果结构体，所有数据源返回均归一化为此格式。
  #
  # 字段:
  #   source         数据源名称（如 "CIRCL"、"DNSDB"）
  #   response_time  请求耗时（秒）
  #   query          查询词（域名或 IP）
  #   answer        应答值（IP 或域名）
  #   rrtype        记录类型（A / AAAA / NS / CNAME / PTR）
  #   ttl           TTL（部分数据源不提供，为 nil）
  #   firstseen     首次观测时间（Time 对象或 nil）
  #   lastseen      最后观测时间（Time 对象或 nil）
  #   count         观测次数（部分数据源提供）
  Result = Struct.new(:source, :response_time, :query, :answer,
                      :rrtype, :ttl, :firstseen, :lastseen, :count) do
    # 转为字符串键的 Hash，日期序列化为 ISO 8601
    def to_h
      {
        "source"        => source,
        "response_time" => response_time,
        "query"         => query,
        "answer"        => answer,
        "rrtype"        => rrtype,
        "ttl"           => ttl,
        "firstseen"     => firstseen&.iso8601,
        "lastseen"      => lastseen&.iso8601,
        "count"         => count,
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def to_s(sep = "\t")
      [source, query, answer, rrtype, ttl,
       firstseen&.iso8601, lastseen&.iso8601, count].join(sep)
    end

    def to_csv_row
      [source, query, answer, rrtype, ttl,
       firstseen&.iso8601, lastseen&.iso8601, count]
    end

    # 表头，与 to_csv_row / to_s 对应
    def self.header(sep = "\t")
      %w[source query answer rrtype ttl firstseen lastseen count].join(sep)
    end
  end
end
