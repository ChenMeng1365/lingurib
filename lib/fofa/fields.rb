# frozen_string_literal: true

module Fofa
  # 接口接入域名（官方文档：https://fofa.info/api/introd）
  DEFAULT_BASE_URL = "https://fofa.info/api/v1"

  # 查询接口 / 连续翻页接口支持的字段（官方文档附录 1，共 51 个）
  # 注：带权限标注的字段需要对应会员等级（个人版/专业版/商业版/企业会员）
  FIELDS = %w[
    ip port protocol country country_name region city longitude latitude
    asn org host domain os server icp title jarm header banner cert
    base_protocol link cert.issuer.org cert.issuer.cn cert.subject.org
    cert.subject.cn tls.ja3s tls.version cert.sn cert.not_before
    cert.not_after cert.domain status_code
    header_hash banner_hash banner_fid
    cname lastupdatetime product product_category
    product.version icon_hash cert.is_valid cname_domain body
    cert.is_match cert.is_equal
    icon fid structinfo
  ].freeze

  # 统计聚合接口支持的字段（官方文档附录 2，共 12 个）
  STATS_FIELDS = %w[
    protocol domain port title os server country asn org asset_type fid icp
  ].freeze

  # 官方错误码 -> 中文说明（不同账号等级可能触发不同错误）
  ERROR_MESSAGES = {
    -1 => "服务器内部错误，请稍后重试",
    -700 => "账号无效（key 已失效或被删除）",
    800 => "非VIP用户，无法使用该功能",
    801 => "key 不存在或错误",
    802 => "请求超过次数限制（速率过快）",
    803 => "F点不足，请充值",
    804 => "无权限访问此数据（字段权限不足或数据超出权限）",
    805 => "无权限使用该 API",
    806 => "账号已被封禁",
    807 => "账号已过期",
    810 => "查询语句语法错误",
  }.freeze

  # 各端点官方最小请求间隔（秒），客户端按此自动限速
  #   /search/all   官方建议请求速率 < 2次/s
  #   /search/next  同查询接口
  #   /search/stats 官方限制 5秒/次
  #   /host         官方限制 1秒/次
  ENDPOINT_RATE = {
    "/search/all"   => 0.55,
    "/search/next"  => 0.55,
    "/search/stats" => 5.0,
    "/host"         => 1.0,
    "/info/my"      => 0.55,
  }.freeze
end
