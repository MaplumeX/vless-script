# VLESS 一键安装脚本（REALITY / XHTTP）

在 Linux 服务器上安装 Xray，并按选择生成以下两种节点之一。支持 systemd 发行版和使用 OpenRC
的 Alpine Linux，运行结束后会直接输出可供客户端导入的 `vless://` 链接。

1. **VLESS + REALITY + Vision**：Xray 直接监听 443，借用目标站点的 TLS 握手，无需自有域名。
2. **VLESS + XHTTP + TLS（上下行分离）**：Caddy 在 443 上用自己域名的真实证书终止 TLS，
   按路径把 XHTTP 请求以 h2c 转给只监听本地端口的 Xray；上行和下行分别走两个域名、
   两条互不相关的连接。也可以让上行或全程经过 Cloudflare CDN，并可选启用 ECH。

## 功能

- 运行后显示数字菜单选择方案，也可以用 `--mode` 非交互指定；
- 使用 [XTLS/Xray-install](https://github.com/XTLS/Xray-install) 官方脚本安装或升级
  Xray；
- 自动识别 systemd 或 Alpine/OpenRC；Alpine 使用 XTLS 官方 Alpine 安装器；
- 自动生成 UUID；REALITY 方案另生成 X25519 密钥对和 8 字节 Short ID，XHTTP 方案另生成
  随机路径；
- XHTTP 方案通过系统包管理器安装 Caddy（Debian/Ubuntu 官方 apt 源、Fedora/RHEL 官方
  COPR、Alpine 和 openSUSE 系统源），自动申请证书，并为每个域名各准备一个空的伪装站点目录；
- XHTTP 方案可选上行或全程经过 Cloudflare CDN，并可选 ECH，同时输出对应的 CDN 链接和
  Cloudflare 设置清单；
- 下载 Loyalsoldier 的 `geoip.dat` 和 `geosite.dat`，每周一 04:30 通过 Xray 自动更新；
- 写入前使用 Xray 内核和 Caddy 校验配置；
- 检查所需端口是否被其他程序占用；
- 在已启用 UFW 或 firewalld 时自动放行所需端口；
- 启动服务并输出客户端导入链接。

## 配置概览

REALITY 方案：

| 项目 | 值 |
| --- | --- |
| 协议 | VLESS |
| 传输 | RAW/TCP |
| 安全 | REALITY |
| Flow | `xtls-rprx-vision` |
| 监听地址 | `::` |
| 监听端口 | `443` |
| REALITY 回落入口 | `127.0.0.1:4431` |
| 客户端指纹 | 默认 `chrome`，可用 `--fingerprint` 修改 |

客户端导入链接使用 `type=tcp`，与服务端的 `network: raw` 兼容，并能被更多客户端
识别。

XHTTP 方案：

| 项目 | 值 |
| --- | --- |
| 协议 | VLESS |
| 传输 | XHTTP，服务端 `mode: auto`；客户端直连链接 `stream-up`，CDN 链接 `packet-up` |
| 前端 | Caddy 监听 80/443，证书由 Caddy 自动申请 |
| 回源 | `127.0.0.1:30001`，h2c，`flush_interval -1` |
| 上行 | 上行域名，ALPN `h2` |
| 下行 | 下行域名（`extra.downloadSettings`），ALPN `h2`；全程 CDN 时与上行同一域名 |
| CDN | 可选，`--cdn up` 或 `--cdn full`（Cloudflare），可选 ECH |
| 客户端指纹 | 默认 `chrome`，可用 `--fingerprint` 修改，含 `unsafe`（原生 Go TLS） |
| 其他路径 | 各域名独立的伪装站点 `/var/www/<域名>`（默认为空，需自行填充） |

两种方案共用的路由规则：国内域名与 IP 阻断，Google 及 Google CN 规则直连。

## 环境要求

- 使用 systemd 的 Linux 发行版，或使用 OpenRC 的 Alpine Linux；
- root 或 sudo 权限；
- Bash；
- 服务器能够访问 GitHub；
- 云厂商安全组和外部防火墙允许所需端口入站；
- REALITY 方案：TCP 443 没有被 Nginx、Caddy、Apache 等其他服务占用；
- XHTTP 方案：两个不同的域名（全程 CDN 时一个）都已解析到本机；TCP 80、443 没有被 Caddy 以外的程序
  占用（Xray 占用 443 时会自动改为只监听本地端口）。

脚本支持通过 `apk`、`apt-get`、`dnf`、`yum` 或 `zypper` 安装所需依赖。

## 快速开始

直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh | sudo bash
```

Alpine 默认可能没有 Bash 和 curl，可用一条命令补齐依赖并安装：

```bash
sudo apk add --no-cache bash curl &&
  curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh |
  sudo bash
```

脚本会先显示方案菜单：

```text
请选择安装方案：
  1. VLESS + REALITY + Vision（Xray 直接监听 443，借用目标站点的 TLS）
  2. VLESS + XHTTP + TLS（Caddy 前置终止 TLS；可上下行分离，也可经过 Cloudflare CDN）

请输入数字 [1-2]:
```

选择 1 后输入 REALITY 目标域名。选择 2 后先选择 CDN 方式（默认不走 CDN），再输入域名：
不走 CDN 或上行走 CDN 时依次输入上行域名和下行域名，全程走 CDN 时只输入一个域名。这里只
填写域名，不要包含 `https://`、端口、路径或通配符。

如果服务器上还没有安装 `curl`，可以先安装：

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y curl

# CentOS / RHEL / Fedora
sudo dnf install -y curl

# Alpine Linux
sudo apk add --no-cache bash curl
```

安装成功后，脚本会显示节点参数（REALITY 方案为地址、UUID、公钥、Short ID、SNI；
XHTTP 方案为上下行域名、UUID、路径）和完整的 `vless://` 客户端导入链接。

请妥善保存导入链接，其中包含节点连接凭据。

## 命令行参数

```text
用法：
  sudo bash install.sh
  sudo bash install.sh --mode reality --domain example.com [--address 203.0.113.10] [--force]
  sudo bash install.sh --mode xhttp --up-domain up.example.com --down-domain down.example.com
                       [--cdn up [--cdn-address 104.16.0.1] [--ech]] [--force]
  sudo bash install.sh --mode xhttp --cdn full --domain cdn.example.com
                       [--cdn-address 104.16.0.1] [--ech] [--force]

参数：
  -m, --mode         安装方案：reality 或 xhttp
  -d, --domain       REALITY 目标域名；--cdn full 时为经过 Cloudflare 的域名
  -a, --address      REALITY 方案中客户端连接的服务器公网 IP 或域名
      --up-domain    XHTTP 方案的上行域名
      --down-domain  XHTTP 方案的下行域名，需与上行域名不同
      --cdn          XHTTP 方案的 CDN 方式：none（默认）、up（上行走 Cloudflare、下行直连）、
                     full（一个域名，全程走 Cloudflare）
      --cdn-address  CDN 链接使用的优选 IP 或优选域名，默认使用经过 CDN 的域名
      --ech          为 CDN 链接启用 ECH，需要客户端支持
      --ech-config   ECH 配置来源，默认 cloudflare-ech.com+https://dns.alidns.com/dns-query；
                     指定时自动启用 --ech
      --fingerprint  客户端 TLS 指纹，默认 chrome；unsafe（原生 Go TLS）仅 XHTTP 可用
  -f, --force        无交互覆盖已有 Xray / Caddy 配置
  -h, --help         显示帮助
```

未指定 `--mode` 时，给出 `--cdn`、`--up-domain` 或 `--down-domain` 视为 XHTTP 方案，只给出
`--domain` 视为 REALITY 方案，否则显示菜单。旧的 `--domain` 用法保持不变。

非交互安装示例：

```bash
# REALITY
curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh |
  sudo bash -s -- \
    --domain www.example.com \
    --address 203.0.113.10 \
    --force

# XHTTP
curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh |
  sudo bash -s -- \
    --mode xhttp \
    --up-domain up.example.com \
    --down-domain down.example.com \
    --force

# XHTTP，全程走 Cloudflare 并启用 ECH
curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh |
  sudo bash -s -- \
    --mode xhttp \
    --cdn full \
    --domain cdn.example.com \
    --ech \
    --force
```

`--address` 可以省略，脚本会通过公网服务探测服务器地址。自动探测失败且当前是
交互式终端时，脚本会要求手动输入。

也可以克隆仓库后运行：

```bash
git clone https://github.com/MaplumeX/vless-reality.git
cd vless-reality
sudo ./install.sh
```

如果已经存在 Xray 配置（XHTTP 方案还包括非本脚本生成的 `/etc/caddy/Caddyfile`），
交互模式会要求确认后再覆盖；非交互模式必须显式添加 `--force`。每次重新运行都会
生成新的凭据，原导入链接将随之失效。

## XHTTP 方案说明

### 准备域名

准备两个不同的域名（可以是同一主域名下的两个子域名，如 `up.example.com` 和
`down.example.com`；全程走 CDN 时只需要一个），都添加 A/AAAA 记录指向服务器。Caddy 需要通过 80 或 443
完成 ACME 验证，所以请在云安全组中放行 TCP 80、TCP 443（以及可选的 UDP 443）。

默认情况下，**两个域名在 Cloudflare 等 DNS 服务商处都应保持“仅 DNS”（灰云）**，直接
连到服务器。不要直接开启 CDN 代理（橙云）：默认链接的上行使用 `stream-up`，未经设置
的 CDN 通常无法流式转发上行请求，而 SSL 模式设置不当还会造成无限重定向。如需经过
CDN，请看下文“进阶：经过 Cloudflare CDN”。

脚本会检查每个域名的解析结果是否包含本机公网地址；不包含时只给出提醒，不会中断，
以兼容经过 CDN 的场景。Caddy 启动后，脚本会等待最多约 90 秒确认每个域名的 HTTPS
可用。

### 进阶：上行和下行分走 IPv4 / IPv6

两个域名都解析到同一个地址时，上行和下行虽然已经拆成两条连接，但外部观察者仍可以
按“同一客户端、同一服务器 IP、同时建立”把它们配成一对。如果服务器有公网 IPv6，
可以只靠 DNS 让两条连接落在不同的地址上：**每个域名只配一种记录**。脚本和服务端
配置都不需要改。

| 配法 | 上行域名 | 下行域名 | 效果 |
| --- | --- | --- | --- |
| 都只配 IPv4 | A | A | 两条连接都连同一个 IPv4 地址 |
| 都配双栈 | A + AAAA | A + AAAA | 由客户端自己选择，通常两条都走同一种协议，结果不可控 |
| **一个 IPv4、一个 IPv6** | 只配 A | 只配 AAAA | 上行固定走 IPv4，下行固定走 IPv6 |
| 两个不同的 IPv4 | A → IP1 | A → IP2 | 需要服务器有多个公网 IPv4 |

示例（反过来配置也可以，按你所在网络哪一侧更稳定来决定由谁承担大流量的下行）：

```text
up.example.com.    A     203.0.113.10
down.example.com.  AAAA  2001:db8::10
```

服务端不用改的原因：Caddy 默认同时监听 IPv4 和 IPv6，Xray 只监听 `127.0.0.1`；脚本的
DNS 检查也接受只解析到本机 IPv6 的域名；UFW 启用 IPv6 时（`IPV6=yes`，多数发行版的
默认值），放行规则同样作用于 IPv6。

使用前请确认：

- 服务器有公网 IPv6，并且云安全组也对 **IPv6** 放行了 TCP 80 和 443。不少厂商的 IPv4 和
  IPv6 安全组规则是分开设置的；
- 只配了 AAAA 的域名在申请证书时，Let's Encrypt 会通过 IPv6 来访问验证，IPv6 入站
  不通就签不出证书；
- **客户端所在网络必须有 IPv6**。只配了 AAAA 的那个域名无法回退到 IPv4，没有 IPv6 时
  这一侧连不上，整个节点也就不可用。部分公司网络、酒店 Wi-Fi 和老旧路由器没有 IPv6；
- IPv6 地址通常没有经过 NAT，可能对应到具体设备，更容易被做设备级分析。这里只把一个
  方向放在 IPv6 上，算是一种折中。

切换配法只需要修改 DNS 记录，并等待生效，不必重新运行脚本。证书按域名签发，与解析到
哪个地址无关；不过新地址必须能从外部访问，否则之后续期证书时会失败。

### 进阶：经过 Cloudflare CDN

XHTTP 方案可以让一部分或全部流量经过 Cloudflare。服务端的 Xray 配置三种方式完全相同，
区别只在于用几个域名，以及输出哪些链接。目前只支持 Cloudflare。

| 方式 | 参数 | 域名 | 输出的链接 | 适合 |
| --- | --- | --- | --- | --- |
| 不走 CDN（默认） | `--cdn none` | 两个，都灰云 | 分离直连 | 线路好、只想要上下行分离 |
| 上行走 CDN、下行直连 | `--cdn up` | 两个，上行橙云、下行灰云 | 分离直连；上行 CDN；全程 CDN 应急 | 让上下行更难关联，大流量仍直连 |
| 全程走 CDN | `--cdn full` | 一个，橙云 | 全程 CDN | 本机 IP 已被封或不想暴露 IP |

`--cdn up` 时，上行连接经过 Cloudflare，下行连接直连服务器，两条连接的目标 IP、ASN 和
网络路径都不相同。上行流量通常很小，不会给 CDN 带来负担。另外输出的**全程 CDN 应急链接**
只用上行域名，上下行都经过 Cloudflare。本机 IP 被封、直连不通时可以切到这条。

`--cdn full` 时只需要一个域名，上下行都经过 Cloudflare，服务器 IP 不会出现在客户端的连接里。

#### 步骤

1. **先把所有域名都设为灰云**，并指向服务器，以便 Caddy 首次签发证书。
2. 运行脚本。在交互菜单中选择 CDN 方式，或者直接加参数：

   ```bash
   # 上行走 CDN、下行直连
   sudo bash install.sh --mode xhttp \
     --up-domain up.example.com --down-domain down.example.com \
     --cdn up [--cdn-address <优选IP或域名>] [--ech]

   # 全程走 CDN
   sudo bash install.sh --mode xhttp --cdn full --domain cdn.example.com \
     [--cdn-address <优选IP或域名>] [--ech]
   ```

3. 经过 CDN 的链接都使用 `packet-up`，不依赖 Cloudflare 的 gRPC 开关；并且总是带上 `host`
   参数，所以把地址换成优选 IP 也能正常工作。
4. 按脚本最后打印的清单设置 Cloudflare（针对经过 CDN 的域名）：
   - SSL/TLS 加密模式选 **Full (strict)**，不要用 Flexible；
   - 关闭 **Always Use HTTPS**，让证书续期的 HTTP-01 验证请求能到达源站；
   - 关闭 **Bot Fight Mode**，或为 XHTTP 路径添加 WAF 跳过规则；
   - 启用 ECH 时，确认 **SSL/TLS → 边缘证书 → Encrypted ClientHello (ECH)** 已开启
     （免费套餐默认开启）；
   - 可选：开启 **gRPC** 后，`--cdn up` 的上行 CDN 链接可以把 `mode=packet-up` 改为
     `mode=stream-up`，全程 CDN 链接可以尝试改为 `mode=stream-one`。
5. 把经过 CDN 的域名切换为**橙云**。`--cdn up` 时下行域名保持灰云。
6. 验证：`curl -sI https://<经过 CDN 的域名>/` 的响应头中应包含 `cf-ray`；然后用 CDN 链接
   实际连接测试。

#### ECH

加 `--ech`（或者在交互菜单中选择启用）后，所有经过 CDN 的链接都会带上 `ech` 参数。客户端
先通过 DoH 查询 `cloudflare-ech.com` 的 HTTPS 记录，取得 Cloudflare 的 ECH 公钥，再把真实的
SNI（你的域名）加密放进 ClientHello。外部只能看到所有 Cloudflare 站点共用的 `cloudflare-ech.com`。

- 默认的配置来源是 `cloudflare-ech.com+https://dns.alidns.com/dns-query`：通过阿里 DoH 查询，
  在国内也能直连，而且查询的是公共域名，不会暴露你自己的域名。可以用 `--ech-config` 换成别的
  DoH 地址，或者直接填 base64 格式的 ECHConfigList（不推荐，Cloudflare 会定期轮换密钥）。
- ECH 只作用于客户端到 Cloudflare 这一段。`--cdn up` 时直连的下行仍然是明文 SNI。
- 客户端必须支持 ECH（例如较新的 Xray 内核，v2rayN / v2rayNG 都能识别链接里的 `ech` 参数）。
  客户端不支持或者取不到 ECH 配置时会直接连不上，不会退回普通 TLS。这时删掉链接里的 `ech`
  参数即可。
- ECH 由 Cloudflare 终止，所以域名还是灰云时，带 ECH 的链接连不通。

#### 需要知道的几点

- Cloudflare 会终止外层 TLS，而 VLESS 本身不加密（`decryption: none`）。因此 Cloudflare 能看到
  经过它的请求中的 VLESS 头部，包括 UUID 和每条连接的目标地址。访问 HTTPS 网站时，网页内容仍由
  内层 TLS 保护。
- `--cdn up` 时下行直连，服务器 IP 并没有被隐藏。这种方式的目的是让上下行难以关联，而不是隐藏 IP。
- 全程 CDN 时所有流量都由 Cloudflare 转发。免费套餐在国内晚高峰可能较慢，长期大流量使用也可能
  违反 Cloudflare 的服务条款。
- 域名开启橙云后，重新运行脚本时 DNS 检查会给出提醒，但不会中断安装；已签发的证书不受影响。
- 如果某次证书续期失败，可以临时把域名切回灰云，等 Caddy 续期成功后再切回橙云。
- 本仓库在本地验证过：经 Caddy 的单域名 `packet-up` 链接，带 ECH 的 Xray 客户端，以及通过阿里 DoH
  取得 Cloudflare ECH 配置并完成握手。但没有用真实的 Cloudflare 域名做过完整测试，以上 Cloudflare
  设置参考的是社区经验。

### 生成的文件

| 用途 | 位置 |
| --- | --- |
| Caddy 配置 | `/etc/caddy/Caddyfile` |
| 上行域名伪装站点 | `/var/www/<上行域名>/` |
| 下行域名伪装站点 | `/var/www/<下行域名>/`（全程 CDN 时没有） |
| Caddy 服务 | `caddy.service` / `/etc/init.d/caddy` |

Caddyfile 首行带有 `# Managed by vless-reality install.sh` 标记，重新运行脚本时
直接覆盖。

### 伪装站点

脚本不生成伪装页面：每个域名的站点目录在创建时为空，此时访问首页返回 404。所有人用
同一份内置页面的话，扫描时反而成了统一的特征，所以伪装站需要每次部署单独制作。建议
两个域名放不同的、多页面的静态站点，而且不要互相链接，这样从内容上看不出它们属于同一台
节点。全程 CDN 时只有一个域名，放一个站点即可。目录已存在时脚本不会改动其中的内容。

文件需要对 Caddy 用户可读，例如：

```bash
chmod -R u=rwX,go=rX /var/www/up.example.com /var/www/down.example.com
```

也可以让 agent 来写，见下文“让 agent 部署”。

### 客户端

导入链接中的下行配置放在 `extra` 参数里（URL 编码的 JSON，包含 `downloadSettings`），
需要较新的 Xray 系客户端或 mihomo 才能识别。全程 CDN 链接没有 `extra` 参数。启用 ECH 时，
链接里的 `ech` 参数需要客户端支持，见上文“ECH”。

链接中的上行（`fp`）和下行（`downloadSettings.tlsSettings.fingerprint`）都会写明指纹，
默认为 `chrome`。这是 Xray 官方推荐的、也是主流的做法。必须写明，是因为不同客户端
对留空的处理相反：Xray 系客户端留空时用 `chrome`，mihomo 留空时却用原生 Go TLS。
在 mihomo 中手动配置时，请设置 `client-fingerprint: chrome`，与链接保持一致。

如果你认同“完全不用 uTLS、只用原生 TLS”的思路，可以加 `--fingerprint unsafe`。
`unsafe` 并不会降低加密强度或跳过证书校验，只是 ClientHello 会呈现 Go 程序的
特征，不再模仿浏览器。Xray 官方不推荐这样做，非 Xray 内核的客户端也可能不认识这个值。
REALITY 方案依赖 uTLS，不能使用 `unsafe`。

### 从一种方案切换到另一种

- REALITY → XHTTP：直接重新运行并选择 2，Xray 会改为只监听 `127.0.0.1:30001`，
  443 交给 Caddy。
- XHTTP → REALITY：先停用 Caddy（`systemctl disable --now caddy`，或
  `rc-service caddy stop && rc-update del caddy default`），再重新运行并选择 1。

## 让 agent 部署

仓库自带一份给 AI agent 用的部署说明：[`skills/vless-deploy/SKILL.md`](skills/vless-deploy/SKILL.md)。
它覆盖整个脚本的使用流程：

- 选择方案；
- 部署前检查；
- 以非交互方式执行脚本（可在本机执行，也可经 SSH 执行）；
- XHTTP 方案中为每个域名分别创作不同的多页面伪装站，并完成验证；
- 切换方案和排障。

文件采用通用的 `SKILL.md` 格式（YAML 头部 `name` / `description` 加 Markdown 正文），
不依赖特定工具：

- 会读取 `AGENTS.md` 的 agent（如 Codex、Cursor、GitHub Copilot 等）在本仓库中工作时，
  会被根目录的 [`AGENTS.md`](AGENTS.md) 引导到这份说明；
- 支持 skill 目录的工具可以直接加载 `skills/vless-deploy/`，仓库里已经为 Claude Code
  准备了软链接 `.claude/skills/vless-deploy`，其他工具可以把这个目录复制或链接到
  各自的 skill 目录；
- 其他 agent 只要能读文件或网页，告诉它“按照 skills/vless-deploy/SKILL.md 执行”，或者
  给它 raw 链接即可：
  `https://raw.githubusercontent.com/MaplumeX/vless-reality/main/skills/vless-deploy/SKILL.md`。

然后对 agent 说“帮我在 <服务器> 上部署 XHTTP 节点，域名是 …”。agent 只有在你确认后，
才会使用 `--force` 覆盖已有配置，或停用 Caddy。

## 如何选择 REALITY 目标域名

建议选择满足以下条件的站点：

- 支持 TLS 1.3；
- 使用标准 TCP 443 端口；
- 从服务器所在网络访问稳定；
- 域名与服务器网络环境相对匹配；
- 不需要额外跳转才能建立 TLS 连接。

不要填写自己的节点域名。REALITY 目标域名是握手时使用的外部 TLS 站点，并不需要
解析到当前服务器。

REALITY 会将认证失败的连接转发到目标站点。避免选择可能让服务器被滥用为大流量
转发器的 CDN 目标。安装完成后，脚本会使用 `xray tls ping` 检查目标站点；检查
失败时会给出警告，但不会删除已经生成的配置。

## 生成的配置

主要文件和服务：

| 用途 | 位置 |
| --- | --- |
| Xray 程序 | `/usr/local/bin/xray` |
| 服务端配置 | `/usr/local/etc/xray/config.json` |
| GeoIP | `/usr/local/share/xray/geoip.dat` |
| GeoSite | `/usr/local/share/xray/geosite.dat` |
| systemd 服务 | `xray.service` |
| OpenRC 服务 | `/etc/init.d/xray` |

重新安装时，systemd 环境会直接覆盖 `config.json`，不保留备份。OpenRC 官方安装器
使用多文件配置目录；为了避免旧配置与新配置合并冲突，脚本会删除目录中的旧 JSON
配置，再写入单个 `config.json`，同样不保留备份。

脚本生成的路由规则与项目目标配置保持一致：

1. REALITY 回落流量仅允许访问所配置的目标域名；
2. 其他 REALITY 回落流量使用 `block`；
3. `geosite:google` 和 `geosite:google-cn` 使用 `direct`；
4. `geosite:cn` 使用 `block`；
5. `geoip:cn` 使用 `block`；
6. 其他流量默认直连。

这意味着节点无法访问大多数中国大陆域名和 IP。如果不需要这一限制，请安装后自行
修改 `routing.rules`，然后重新校验并启动服务。

## 常用运维命令

systemd 常用命令：

```bash
systemctl status xray --no-pager
journalctl -u xray.service -n 100 --no-pager
journalctl -u xray.service -f
systemctl restart xray.service
```

OpenRC/Alpine 常用命令：

```bash
rc-service xray status
rc-service xray restart
rc-update add xray default
```

两种环境都可以直接校验配置：

```bash
/usr/local/bin/xray run -test \
  -config /usr/local/etc/xray/config.json
```

XHTTP 方案中的 Caddy：

```bash
systemctl status caddy --no-pager      # OpenRC：rc-service caddy status
journalctl -u caddy -n 100 --no-pager
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

查看版本：

```bash
/usr/local/bin/xray version
```

## 常见问题

### TCP 443 已被占用

脚本会在安装前停止，并显示监听该端口的程序。可以用以下命令进一步检查：

```bash
ss -lntp 'sport = :443'
```

停止或调整占用 443 的服务后，再重新运行脚本。

### 服务正常运行，但客户端无法连接

依次检查：

1. 云厂商安全组是否允许 TCP 443 入站；
2. UFW、firewalld、nftables 或 iptables 是否允许 TCP 443；
3. 客户端是否支持 VLESS、REALITY 和 XTLS Vision；
4. 客户端中的 UUID、公钥、Short ID、SNI 是否与脚本输出完全一致；
5. 服务器能否访问所填写目标域名的 TCP 443。

### 自动探测到的公网地址不正确

NAT、多出口或代理环境可能影响自动探测。重新运行时通过 `--address` 指定客户端
实际应该连接的公网 IP 或域名：

```bash
sudo ./install.sh \
  --domain www.example.com \
  --address node.example.net \
  --force
```

## 安全提示

- 不要公开分享客户端导入链接、UUID、REALITY 私钥或 Short ID；
- 建议定期更新 Xray；
- 定期检查 Xray 服务状态和日志中的异常连接；
- 不要将来源不明的域名作为 REALITY 目标；
- 本脚本会修改 Xray 配置及 UFW/firewalld 规则，请先了解服务器上已有服务。

请在遵守所在地法律法规以及服务商使用条款的前提下使用本项目。
