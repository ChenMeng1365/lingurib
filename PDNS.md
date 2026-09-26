# Passive DNS 模块（Pdns）

---

## 支持的数据源

| 数据源 | CLI 字母 | 配置节名 | 认证方式 | 官网 |
|--------|---------|---------|---------|------|
| CIRCL | `c` | `circl` | AUTH_TOKEN 或 USERNAME+PASSWORD | https://www.circl.lu/services/passive-dns/ |
| DNSDB | `d` | `dnsdb` | APIKEY | https://api.dnsdb.info/ |
| PassiveTotal | `p` | `passivetotal` | USERNAME + APIKEY | https://www.passivetotal.org |
| RiskIQ | `r` | `riskiq` | API_TOKEN + API_PRIVATE_KEY | https://community.riskiq.com |
| VirusTotal | `v` | `virustotal` | APIKEY | https://www.virustotal.com |

---

## 配置指南

### 配置查找链（优先级从高到低）

1. **环境变量** — `PDNS_` 前缀，如 `PDNS_DNSDB_APIKEY`
2. **项目 .env** — 当前目录 `.env` 文件（dotenv 风格）
3. **全局配置** — `~/.pdns/credentials`（推荐，永不进 git）

环境变量同名会覆盖配置文件中的值。

### 配置文件格式

文件为 dotenv 风格，每行一个 `KEY=VALUE`，支持注释（`#`）、引号、行内注释。

### 创建配置文件

```bash
# 创建推荐的全局配置目录和文件
mkdir -p ~/.pdns
cat > ~/.pdns/credentials << 'EOF'
# ============================================================
# Passive DNS 配置文件
# 每行一个 KEY=VALUE，以 # 开头为注释
# ============================================================

# --- CIRCL (https://www.circl.lu/services/passive-dns/) ---
# 二选一：AUTH_TOKEN 或 USERNAME+PASSWORD
PDNS_CIRCL_AUTH_TOKEN=your_circl_auth_token
# PDNS_CIRCL_USERNAME=your_username
# PDNS_CIRCL_PASSWORD=your_password

# --- DNSDB / FarSight (https://api.dnsdb.info/) ---
PDNS_DNSDB_APIKEY=your_dnsdb_apikey

# --- PassiveTotal (https://www.passivetotal.org) ---
PDNS_PASSIVETOTAL_USERNAME=your_email@example.com
PDNS_PASSIVETOTAL_APIKEY=your_passivetotal_apikey

# --- RiskIQ (https://community.riskiq.com) ---
PDNS_RISKIQ_API_TOKEN=your_riskiq_token
PDNS_RISKIQ_API_PRIVATE_KEY=your_riskiq_private_key

# --- VirusTotal (https://www.virustotal.com) ---
PDNS_VIRUSTOTAL_APIKEY=your_virustotal_apikey
EOF
```

### 各数据源 API Key 获取方式

#### CIRCL
- 访问 https://www.circl.lu/services/passive-dns/
- 注册账户后获取 USERNAME + PASSWORD
- 或申请 AUTH_TOKEN（推荐，更安全）
- 配置项：`PDNS_CIRCL_AUTH_TOKEN` 或 `PDNS_CIRCL_USERNAME` + `PDNS_CIRCL_PASSWORD`

#### DNSDB (FarSight Security)
- 访问 https://api.dnsdb.info/
- 邮件申请 API Key
- 配置项：`PDNS_DNSDB_APIKEY`

#### PassiveTotal
- 访问 https://www.passivetotal.org
- 注册账户，获取用户名（邮箱）和 API Key
- 配置项：`PDNS_PASSIVETOTAL_USERNAME` + `PDNS_PASSIVETOTAL_APIKEY`

#### RiskIQ
- 访问 https://community.riskiq.com
- 注册账户，获取 API Token 和 API Private Key
- 配置项：`PDNS_RISKIQ_API_TOKEN` + `PDNS_RISKIQ_API_PRIVATE_KEY`
- 注：RiskIQ 已被 Microsoft 收购，API 可能迁移至 Defender TI

#### VirusTotal
- 访问 https://www.virustotal.com
- 注册账户，获取 API Key
- 配置项：`PDNS_VIRUSTOTAL_APIKEY`

### 使用环境变量（替代配置文件）

```bash
export PDNS_DNSDB_APIKEY=your_dnsdb_apikey
export PDNS_VIRUSTOTAL_APIKEY=your_virustotal_apikey
```

---

## 库用法

### 基本查询

```ruby
require "pdns"

# 指定数据源
client = Pdns::Client.new(:dnsdb, :virustotal)
results = client.query("example.com")
results = client.query("1.2.3.4", limit: 100)

# 自动选择所有已配置的数据源
client = Pdns::Client.new(:all)
results = client.query("example.com")
```

### 结果遍历

```ruby
results.each do |r|
  puts "#{r.source} | #{r.query} -> #{r.answer} | #{r.rrtype} | #{r.firstseen} ~ #{r.lastseen}"
end
```

### 递归查询

查到结果后自动把 answer 和 query 加入队列继续查，通过 depth 控制递归深度。

```ruby
client = Pdns::Client.new(:dnsdb, :virustotal)
results = client.query_recursive("example.com", depth: 2, wait: 1)
# depth: 递归深度（1=不递归，2=查一层，...）
# wait: 每次查询间隔秒数（建议 ≥ 1，避免被数据源封禁）
```

### 导出结果

```ruby
require "json"
require "csv"

# JSON
json = JSON.pretty_generate(results.map(&:to_h))
File.write("results.json", json)

# CSV
CSV.open("results.csv", "w", encoding: "bom|utf-8") do |csv|
  csv << %w[source query answer rrtype ttl firstseen lastseen count]
  results.each { |r| csv << r.to_csv_row }
end
```

### 查看可用数据源

```ruby
Pdns::Client.list_providers.each do |klass|
  puts "#{klass.display_name} (#{klass.config_section}) -d#{klass.option_letter}"
end
```

---

## 命令行用法

### 查询

```bash
# 基本查询（默认 VirusTotal）
pdns query example.com

# 指定数据源（字母组合）
pdns query example.com -d dv

# 指定数据源（逗号分隔名称）
pdns query example.com -d dnsdb,virustotal

# 限制返回条数
pdns query 1.2.3.4 --limit 100

# JSON 输出
pdns query example.com --json

# 导出 CSV
pdns query example.com --csv results.csv
```

### 递归查询

```bash
# 递归深度 2，每次查询间隔 1 秒
pdns recursive example.com --depth 2 --wait 1

# 递归 + CSV 导出
pdns recursive example.com --depth 2 --csv out.csv
```

> **警告**: 递归深度 > 3 会对数据源造成巨大压力，请谨慎使用。CLI 在 depth > 3 时会强制等待。

### 列出数据源

```bash
pdns providers
```

### 内置自检

```bash
pdns --selftest
```

不联网验证配置解析、IP 判定、结果结构、状态管理、数据源注册等。

### 指定配置文件

```bash
pdns query example.com --config /path/to/credentials
```

---

## Pdns::Result 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| source | String | 数据源名称（如 "DNSDB"） |
| response_time | Float | 请求耗时（秒） |
| query | String | 查询词（域名或 IP） |
| answer | String | 应答值（IP 或域名） |
| rrtype | String | 记录类型（A / AAAA / NS / CNAME / PTR） |
| ttl | Integer, nil | TTL（部分数据源不提供） |
| firstseen | Time, nil | 首次观测时间 |
| lastseen | Time, nil | 最后观测时间 |
| count | Integer, nil | 观测次数 |

---

## 编写自定义数据源适配器

新增数据源只需在 `lib/pdns/provider/` 下创建一个文件，继承 `Pdns::Provider::Base`：

```ruby
# lib/pdns/provider/mydb.rb
module Pdns
  module Provider
    class MyDb < Base
      def self.display_name; "MyDB"; end
      def self.option_letter; "m"; end

      def self.configured?(config)
        !config["APIKEY"].to_s.empty?
      end

      def initialize(config: {}, **opts)
        super
        @apikey = config["APIKEY"] || raise(Pdns::AuthError, "MyDB 需要 APIKEY")
        @url    = config["URL"] || "https://api.mydb.example.com/lookup"
      end

      def lookup(label, limit: nil)
        url = "#{@url}?q=#{label}&limit=#{limit || 1000}"
        t1  = Time.now

        response = http_get(url, headers: {
          "User-Agent" => ua,
          "X-API-Key"  => @apikey,
          "Accept"     => "application/json",
        })

        parse_response(response.body, Time.now - t1)
      end

      private

      def parse_response(body, response_time)
        data = JSON.parse(body.to_s)
        Array(data["results"]).map do |row|
          Pdns::Result.new(
            self.class.display_name, response_time,
            row["query"], row["answer"], row["type"], 0,
            parse_time(row["first_seen"]), parse_time(row["last_seen"]),
            row["count"]
          )
        end
      rescue JSON::ParserError
        []
      end

      def parse_time(str)
        Time.parse(str.to_s) rescue nil
      end
    end
  end
end
```

文件放入 `lib/pdns/provider/` 后会被 `lib/pdns.rb` 自动 require 和注册。

配置环境变量 `PDNS_MYDB_APIKEY` 即可使用：

```bash
pdns query example.com -d m
```

---

## 架构概览

```
lib/
├── pdns.rb                     # 主入口，require 全部模块 + 自动加载 provider/
└── pdns/
    ├── version.rb              # 版本 1.0.0
    ├── errors.rb              # 异常体系: Error / AuthError / APIError / NetworkError
    ├── result.rb              # Pdns::Result 统一结果结构体
    ├── config.rb              # 多数据源配置管理（env + 文件查找链）
    ├── provider.rb            # Pdns::Provider::Base 抽象基类（http_get + 重试）
    ├── state.rb               # Pdns::State 递归查询状态管理（内存去重队列）
    ├── client.rb              # Pdns::Client 协调器（多线程并行查询）
    ├── cli.rb                 # 命令行工具
    ├── selftest.rb            # 内置自检（不联网）
    └── provider/
        ├── circl.rb           # CIRCL 适配器
        ├── dnsdb.rb           # DNSDB 适配器
        ├── passivetotal.rb    # PassiveTotal 适配器
        ├── riskiq.rb          # RiskIQ 适配器
        └── virustotal.rb      # VirusTotal 适配器
```

### 核心设计

- **适配器模式**: `Pdns::Provider::Base` 定义抽象接口，每个数据源独立实现 `#lookup`
- **统一结果**: 所有数据源返回 `Pdns::Result` 结构体，上层不关心数据来自哪个平台
- **多线程并行**: `Pdns::Client#query` 为每个数据源创建线程，并行查询
- **递归状态**: `Pdns::State` 维护内存队列，去重 + 层级控制
- **零依赖**: 仅使用 Ruby 标准库（net/http, json, openssl, time 等）
- **HTTP 重试**: 基类 `http_get` 提供指数退避重试，子类只需关注业务解析
