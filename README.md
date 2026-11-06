# VLESS 一键安装脚本（REALITY / XHTTP）

在 Linux 服务器上安装 Xray，并按选择生成以下两种节点之一。支持 systemd 发行版和使用 OpenRC
的 Alpine Linux，运行结束后会直接输出可供客户端导入的 `vless://` 链接。

1. **VLESS + REALITY + Vision**：Xray 直接监听 443，借用目标站点的 TLS 握手，无需自有域名。
2. **VLESS + XHTTP + TLS（上下行分离）**：Caddy 在 443 上用自己域名的真实证书终止 TLS，
   按路径把 XHTTP 请求以 h2c 转给只监听本地端口的 Xray；上行和下行分别走两个域名、
   两条互不相关的连接。

## 功能

- 运行后显示数字菜单选择方案，也可以用 `--mode` 非交互指定；
- 使用 [XTLS/Xray-install](https://github.com/XTLS/Xray-install) 官方脚本安装或升级
  Xray；
- 自动识别 systemd 或 Alpine/OpenRC；Alpine 使用 XTLS 官方 Alpine 安装器；
- 自动生成 UUID；REALITY 方案另生成 X25519 密钥对和 8 字节 Short ID，XHTTP 方案另生成
  随机路径；
- XHTTP 方案通过系统包管理器安装 Caddy（Debian/Ubuntu 官方 apt 源、Fedora/RHEL 官方
  COPR、Alpine 和 openSUSE 系统源），自动申请证书，并为两个域名各准备一个空的伪装站点目录；
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
| 传输 | XHTTP，服务端 `mode: auto`，客户端 `mode: stream-up` |
| 前端 | Caddy 监听 80/443，证书由 Caddy 自动申请 |
| 回源 | `127.0.0.1:30001`，h2c，`flush_interval -1` |
| 上行 | 上行域名，ALPN `h2` |
| 下行 | 下行域名（`extra.downloadSettings`），ALPN `h2` |
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
- XHTTP 方案：两个不同的域名都已解析到本机；TCP 80、443 没有被 Caddy 以外的程序
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
  2. VLESS + XHTTP + TLS（Caddy 前置终止 TLS，上下行分离，需要两个解析到本机的域名）

请输入数字 [1-2]:
```

选择 1 后输入 REALITY 目标域名；选择 2 后依次输入上行域名和下行域名。这里只填写
域名，不要包含 `https://`、端口、路径或通配符。

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
  sudo bash install.sh --mode xhttp --up-domain up.example.com --down-domain down.example.com [--force]

参数：
  -m, --mode         安装方案：reality 或 xhttp
  -d, --domain       REALITY 目标域名，不带协议、端口或路径
  -a, --address      REALITY 方案中客户端连接的服务器公网 IP 或域名
      --up-domain    XHTTP 方案的上行域名
      --down-domain  XHTTP 方案的下行域名，需与上行域名不同
      --fingerprint  客户端 TLS 指纹，默认 chrome；unsafe（原生 Go TLS）仅 XHTTP 可用
  -f, --force        无交互覆盖已有 Xray / Caddy 配置
  -h, --help         显示帮助
```

未指定 `--mode` 时，给出 `--domain` 视为 REALITY 方案，给出 `--up-domain` 或
`--down-domain` 视为 XHTTP 方案，否则显示菜单。旧的 `--domain` 用法保持不变。

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
`down.example.com`），都添加 A/AAAA 记录指向服务器。Caddy 需要通过 80 或 443
完成 ACME 验证，所以请在云安全组中放行 TCP 80、TCP 443（以及可选的 UDP 443）。

脚本会检查两个域名的解析结果是否包含本机公网地址；不包含时只给出提醒，不会中断，
以兼容经过 CDN 的场景。Caddy 启动后，脚本会等待最多约 90 秒确认两个域名的 HTTPS
可用。

### 生成的文件

| 用途 | 位置 |
| --- | --- |
| Caddy 配置 | `/etc/caddy/Caddyfile` |
| 上行域名伪装站点 | `/var/www/<上行域名>/` |
| 下行域名伪装站点 | `/var/www/<下行域名>/` |
| Caddy 服务 | `caddy.service` / `/etc/init.d/caddy` |

Caddyfile 首行带有 `# Managed by vless-reality install.sh` 标记，重新运行脚本时
直接覆盖。

### 伪装站点

脚本不生成伪装页面：两个域名的站点目录在创建时为空，此时访问首页返回 404。所有人用
同一份内置页面的话，扫描时反而成了统一的特征，所以伪装站需要每次部署单独制作。建议
两个域名放不同的、多页面的静态站点，而且不要互相链接，这样从内容上看不出它们属于同一台
节点。目录已存在时脚本不会改动其中的内容。

文件需要对 Caddy 用户可读，例如：

```bash
chmod -R u=rwX,go=rX /var/www/up.example.com /var/www/down.example.com
```

也可以让 agent 来写，见下文“让 agent 部署”。

### 客户端

导入链接中的下行配置放在 `extra` 参数里（URL 编码的 JSON，包含 `downloadSettings`），
需要较新的 Xray 系客户端或 mihomo 才能识别。

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
- XHTTP 方案中为两个域名分别创作不同的多页面伪装站，并完成验证；
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
