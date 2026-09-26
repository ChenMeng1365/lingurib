# frozen_string_literal: true

require_relative "result"

module Pdns
  # 递归查询状态管理（纯内存）
  #
  # 核心思路：
  #   1. 维护待查队列（去重）
  #   2. 每次查询结果中的 answer 和 query 都加入队列，实现递归扩展
  #   3. 通过 level 控制递归深度，超过 max_level 的条目标记为 queried 但不执行
  class State
    Entry = Struct.new(:query, :state, :level)

    attr_reader :results

    def initialize
      @queue = []
      @results = []
      @seen = {}
      @current_level = 0
    end

    # 添加待查询条目（自动去重）
    # @param query [String] IP 或域名
    # @param level [Integer] 递归层级
    def add(query, level = 0)
      q = query.to_s.strip
      return if q.empty? || @seen.key?(q)
      @seen[q] = true
      @queue << Entry.new(q, "pending", level)
    end

    # 将查询结果加入记录，并把 answer 和 query 加入待查队列
    def add_result(result)
      @results << result
      next_level = @current_level + 1
      add(result.answer.to_s, next_level) if result.answer
      add(result.query.to_s, next_level) if result.query
    end

    # 遍历所有 pending / failed 的查询条目
    # 超过 max_level 的标记为 queried 但不 yield
    # @yield [String] 待查询的 IP 或域名
    def each_pending(max_level: 20)
      @queue.each do |entry|
        next unless %w[pending failed].include?(entry.state)
        entry.state = "queried"
        next if entry.level >= max_level
        @current_level = entry.level
        yield entry.query
      end
    end
  end
end
