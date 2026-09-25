# frozen_string_literal: true

require_relative "lib/fofa/version"

Gem::Specification.new do |spec|
  spec.name = "lingurib"
  spec.version = Fofa::VERSION
  spec.authors = ["lingurib"]
  spec.summary = "通用安全工具库（SEC toolkit）：网络空间测绘、资产收集、威胁情报等安全 API 的 Ruby 统一封装"
  spec.description = <<~DESC
    lingurib 是一个面向安全从业者的 Ruby 工具库，目标是统一封装各类安全相关 API，
    覆盖网络空间测绘、资产收集、威胁情报、IP/域名关联分析等场景。

    FOFA（fofa.info）网络空间测绘 API 全部 5 个接口：
    查询接口（search/all）、统计聚合（search/stats）、Host 聚合（host/{host}）、
    账号信息（info/my）、连续翻页（search/next）。
    特性：查询语句自动 base64、按官方限制自动限速、size 上限自动钳制、
    网络错误自动重试、结果转 Hash、TLS 证书域名提取。
    扩展：domains_for_ip —— IP 被动绑定域名查询（host/domain/cert + Host 聚合）。
    附带命令行工具：fofa info/search/count/stats/host/domains/all。

    后续计划接入更多安全平台 API，逐步打造通用 SEC 接口层。
  DESC
  spec.homepage = "https://github.com/lingurib/lingurib"
  spec.license = "AGPL-3.0"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb"] + %w[bin/fofa LICENSE lingurib.gemspec Gemfile]
  spec.bindir = "bin"
  spec.executables = %w[fofa]
  spec.require_paths = %w[lib]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
