# frozen_string_literal: true

# Passive DNS (pDNS) 客户端 —— Ruby 封装，统一查询多个被动 DNS 数据库。
#
# 被动 DNS 通过记录"他人查询 DNS 时得到的回答"来建立 IP ↔ 域名映射历史，
# 是安全调查、威胁情报、资产测绘的常用手段。
#
# 支持的数据源:
#   1. CIRCL         https://www.circl.lu/services/passive-dns/
#   2. DNSDB         https://api.dnsdb.info/
#   3. PassiveTotal   https://www.passivetotal.org
#   4. RiskIQ        https://community.riskiq.com
#   5. VirusTotal    https://www.virustotal.com
#
# 快速上手:
#   require "pdns"
#   client = Pdns::Client.new(:dnsdb, :virustotal)
#   results = client.query("example.com")
#   results = client.query("1.2.3.4", limit: 100)
#   results = client.query_recursive("example.com", depth: 2, wait: 1)
#
#   client = Pdns::Client.new(:all)  # 自动选择所有已配置的数据源
#
# 命令行（bin/pdns 或 gem 安装后的 pdns 命令）:
#   pdns query example.com -d dv --json
#   pdns query 1.2.3.4 --limit 100
#   pdns recursive example.com --depth 2 --csv out.csv
#   pdns providers
#   pdns --selftest
#
# 配置:
#   环境变量（优先级最高）或配置文件 ~/.pdns/credentials
#   详见 PDNS.md 文档。

require_relative "pdns/version"
require_relative "pdns/errors"
require_relative "pdns/result"
require_relative "pdns/config"
require_relative "pdns/provider"
require_relative "pdns/state"
require_relative "pdns/client"

# 自动加载所有数据源适配器
Dir.glob(File.join(__dir__, "pdns", "provider", "*.rb")).sort.each do |f|
  require f
end

module Pdns
end
