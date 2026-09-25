# frozen_string_literal: true

# FOFA (fofa.info) API 客户端 —— Ruby 封装，覆盖官方全部 5 个接口。
#
# 官方文档: https://fofa.info/api/introd
#
#   1. 查询接口     GET /api/v1/search/all    资产搜索（分页）
#   2. 统计聚合     GET /api/v1/search/stats  按字段聚合统计（前 5 排名）
#   3. Host 聚合   GET /api/v1/host/{host}   单 IP 资产画像（端口/协议/产品）
#   4. 账号信息     GET /api/v1/info/my       账号余额 / 配额 / 会员等级
#   5. 连续翻页     GET /api/v1/search/next   大规模数据导出（防错位、可续传）
#
# 扩展功能:
#   - domains_for_ip: IP 被动绑定域名查询（host/domain/cert 证书 SAN 提取 + Host 聚合）
#
# 快速上手:
#   require "fofa"
#   client = Fofa::Client.new(key: "你的key")  # 或环境变量 FOFA_KEY
#
#   client.user_info                                     # 账号配额
#   client.search('title="后台登录"')                     # 资产搜索
#   client.search_dicts('domain="example.com"')          # 结果转 Hash
#   client.count('domain="example.com"')                # 只查总量
#   client.search_all('app="Apache"', max_records: 5000) # 批量拉取
#   client.stats('domain="example.com"')                # 统计聚合
#   client.get_host("1.2.3.4", detail: true)             # 单 IP 画像
#   client.domains_for_ip("1.2.3.4")                     # IP 被动绑定域名
#
# 命令行（bin/fofa 或 gem 安装后的 fofa 命令）:
#   fofa info
#   fofa search 'title="test"' --size 10 --json
#   fofa count 'domain="example.com"'
#   fofa stats 'domain="example.com"' --fields protocol,port
#   fofa host 1.2.3.4 --detail
#   fofa domains 1.2.3.4
#   fofa all 'app="Apache"' --max 2000 --csv out.csv
#   fofa --selftest                                     # 内置自检（不联网）

require_relative "fofa/version"
require_relative "fofa/errors"
require_relative "fofa/fields"
require_relative "fofa/cert"
require_relative "fofa/key_provider"
require_relative "fofa/client"

module Fofa
end
