# VLESS 一键安装脚本

一条命令在 Linux 服务器上装好 Xray，部署一个 VLESS 节点，最后直接输出可导入客户端的
`vless://` 链接。支持 systemd 发行版和 Alpine Linux（OpenRC）。

## 选择方案

| | REALITY | XHTTP | hybrid |
| --- | --- | --- | --- |
| 组合 | VLESS + REALITY + Vision | VLESS + XHTTP + TLS | VLESS Encryption + Vision + XHTTP |
| 需要域名 | 不需要（借用别人的站点） | 两个自有域名（全程 CDN 时一个） | 两个自有域名 |
| 443 端口 | Xray 直接监听 | Caddy 终止 TLS，转给本地 Xray | 同 XHTTP |
| 上下行 | 同一条连接 | 拆成两条连接、走两个域名 | 上行 IPv6 直连，下行 IPv4 经 Cloudflare + ECH |
| Cloudflare CDN | 不支持 | 可选：上行或全程经过，可选 ECH | 下行固定经过 |
| 额外要求 | 无 | 无 | 本机公网 IPv6；客户端网络同时有 IPv4 和 IPv6 |
| 适合 | 想最快部署、没有域名 | 想用自己的真实证书、拆分上下行 | 想让上下行最难被关联 |

简单来说：没有域名就选 REALITY；有两个域名就选 XHTTP；服务器有 IPv6，并且能接受下行经过
Cloudflare 免费套餐时，可以选 hybrid。

每种方案的详细说明：

- [REALITY 方案](docs/reality.md)：配置概览和目标域名的选择；
- [XHTTP 方案](docs/xhttp.md)：域名准备、IPv4 / IPv6 分流、Cloudflare CDN、ECH、
  VLESS Encryption、伪装站和客户端指纹；
- [hybrid 方案](docs/hybrid.md)：DNS 配法、输出的链接和 Cloudflare 设置。

## 环境要求

- 使用 systemd 的 Linux 发行版，或使用 OpenRC 的 Alpine Linux；
- root 或 sudo 权限，已安装 Bash 和 curl；
- 服务器能访问 GitHub；
- 云厂商安全组放行所需端口：REALITY 需要 TCP 443，XHTTP 和 hybrid 需要 TCP 80、443；
- 所需端口没有被其他程序占用（XHTTP 和 hybrid 的 80、443 可以是 Caddy）。

依赖通过 `apk`、`apt-get`、`dnf`、`yum` 或 `zypper` 自动安装。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-script/main/install.sh | sudo bash
```

Alpine 默认没有 Bash 和 curl，先补齐：

```bash
sudo apk add --no-cache bash curl &&
  curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-script/main/install.sh | sudo bash
```

脚本会显示菜单，按提示操作即可：

```text
请选择安装方案：
  1. VLESS + REALITY + Vision（Xray 直接监听 443，借用目标站点的 TLS）
  2. VLESS + XHTTP + TLS（Caddy 前置终止 TLS；可上下行分离，也可经过 Cloudflare CDN）
  3. VLESS Encryption + Vision + XHTTP：上行 IPv6 直连，下行 IPv4 经 Cloudflare + ECH
     （需要两个域名和本机公网 IPv6）

请输入数字 [1-3]:
```

- 选 1：输入 REALITY 目标域名；
- 选 2：先选 CDN 方式（默认不走 CDN），再输入上行和下行域名；全程走 CDN 时只输入一个域名；
- 选 3：依次输入上行域名、下行域名和可选的优选地址。

域名只填域名本身，不要带 `https://`、端口、路径或通配符。

> [!IMPORTANT]
> 安装 XHTTP 或 hybrid 之前，请先把域名解析到服务器，并在 Cloudflare 上保持**灰云（仅 DNS）**，
> 否则证书签不下来。需要经过 CDN 的域名，等安装完成后再按脚本打印的清单切换为橙云。

也可以克隆仓库后运行：

```bash
git clone https://github.com/MaplumeX/vless-script.git
cd vless-script
sudo ./install.sh
```

## 非交互安装

通过参数传入全部选择，适合脚本化部署：

```bash
URL=https://raw.githubusercontent.com/MaplumeX/vless-script/main/install.sh

# REALITY
curl -fsSL "$URL" | sudo bash -s -- --mode reality --domain www.example.com

# XHTTP，上下行分离直连
curl -fsSL "$URL" | sudo bash -s -- --mode xhttp \
  --up-domain up.example.com --down-domain down.example.com

# XHTTP，全程经过 Cloudflare 并启用 ECH
curl -fsSL "$URL" | sudo bash -s -- --mode xhttp --cdn full --domain cdn.example.com --ech

# hybrid
curl -fsSL "$URL" | sudo bash -s -- --mode hybrid \
  --up-domain up.example.com --down-domain down.example.net
```

已有 Xray 配置时，非交互模式需要加 `--force` 才会覆盖，见下文“重新安装”。

## 参数

| 参数 | 适用方案 | 说明 |
| --- | --- | --- |
| `-m, --mode` | 全部 | `reality`、`xhttp` 或 `hybrid` |
| `-d, --domain` | REALITY、XHTTP | REALITY 的目标域名；`--cdn full` 时为经过 Cloudflare 的域名 |
| `-a, --address` | REALITY | 客户端连接的服务器 IP 或域名，默认自动探测 |
| `--up-domain` | XHTTP、hybrid | 上行域名 |
| `--down-domain` | XHTTP、hybrid | 下行域名，必须与上行域名不同 |
| `--cdn` | XHTTP | `none`（默认）、`up`（上行经 Cloudflare）、`full`（一个域名，全程经 Cloudflare） |
| `--cdn-address` | XHTTP、hybrid | CDN 链接使用的优选 IP 或域名，默认用经过 CDN 的域名；hybrid 中不能是 IPv6 |
| `--ech` | XHTTP | 为 CDN 链接启用 ECH，需要客户端支持 |
| `--ech-config` | XHTTP、hybrid | ECH 配置来源，默认 `cloudflare-ech.com+https://dns.alidns.com/dns-query`；指定时自动启用 `--ech` |
| `--vless-enc` | XHTTP | `on` / `off`，是否启用 VLESS Encryption + Vision；经过 CDN 时默认 `on`，否则默认 `off` |
| `--fingerprint` | 全部 | 客户端 TLS 指纹，默认 `chrome`；`unsafe`（原生 Go TLS）只能用于 XHTTP |
| `-f, --force` | 全部 | 不询问，直接覆盖已有的 Xray / Caddy 配置 |
| `-h, --help` | — | 显示帮助 |

补充说明：

- 未指定 `--mode` 时：给出 `--cdn`、`--up-domain` 或 `--down-domain` 视为 XHTTP，只给出
  `--domain` 视为 REALITY，否则显示菜单；
- hybrid 必须显式指定 `--mode hybrid` 或在菜单中选择。它固定启用 VLESS Encryption、Vision 和 ECH，
  传入 `--cdn`、`--ech` 或 `--vless-enc off` 会被忽略；
- `--fingerprint` 的全部可选值见 `bash install.sh --help`。

## 安装完成后

脚本结束时会显示节点参数和 `vless://` 导入链接。经过 CDN 时还会输出多条链接，以及一份
Cloudflare 设置清单。

> [!WARNING]
> 导入链接包含节点的连接凭据，请妥善保存，不要公开分享。

按方案还需要：

- **REALITY**：导入链接即可使用。
- **XHTTP / hybrid**：
  - 为每个域名放一个伪装站。脚本只创建空目录 `/var/www/<域名>/`，访问首页会返回 404。
    两个域名的站点应当各不相同，详见 [XHTTP 方案 · 伪装站点](docs/xhttp.md#伪装站点)；
  - 经过 CDN 时，按脚本打印的清单完成 Cloudflare 设置，再把对应域名切换为橙云。

客户端需要较新的 Xray 内核（如 v2rayN、v2rayNG）。XHTTP 链接的下行配置放在 `extra` 参数里，
mihomo 等其他内核需要确认能识别；启用 VLESS Encryption 或 ECH 时，对客户端的要求更高。

## 重新安装与切换方案

- 每次运行都会生成新的凭据，旧的导入链接随之失效；
- 已有 Xray 配置（XHTTP 和 hybrid 还包括非本脚本生成的 `/etc/caddy/Caddyfile`）时，交互模式会先询问，
  非交互模式需要加 `--force`。覆盖时不保留备份；
- REALITY → XHTTP / hybrid、XHTTP ↔ hybrid：直接重新运行，选择新方案即可，然后按新方案调整 DNS；
- XHTTP / hybrid → REALITY：先停用 Caddy，再重新运行并选择 REALITY：

  ```bash
  systemctl disable --now caddy                          # systemd
  rc-service caddy stop && rc-update del caddy default   # OpenRC
  ```

## 脚本做了什么

- 用 [XTLS/Xray-install](https://github.com/XTLS/Xray-install) 官方脚本安装或升级 Xray，
  Alpine 使用官方的 Alpine 安装器；
- 生成 UUID；REALITY 另生成 X25519 密钥对和 Short ID，XHTTP 另生成随机路径；
- XHTTP 和 hybrid：通过系统包管理器安装 Caddy，自动申请证书；
- 下载 Loyalsoldier 的 `geoip.dat` 和 `geosite.dat`，每周一 04:30 自动更新；
- 写入前用 Xray 和 Caddy 校验配置，检查端口占用；
- UFW 或 firewalld 已启用时，自动放行所需端口；
- 启动服务并输出导入链接。

生成的路由规则：**阻断中国大陆的域名和 IP**，Google 相关域名直连，其余流量直连。不需要这一限制时，
请自行修改配置中的 `routing.rules`。

文件位置、服务管理、日志和常见问题见 [运维与排障](docs/operations.md)。

## 让 AI agent 部署

仓库自带一份给 AI agent 的部署说明 [`skills/vless-deploy/SKILL.md`](skills/vless-deploy/SKILL.md)，
覆盖选择方案、部署前检查、执行脚本、为每个域名创作伪装站，以及切换方案和排障。

- 读取 `AGENTS.md` 的 agent（Codex、Cursor、GitHub Copilot 等）会被根目录的
  [`AGENTS.md`](AGENTS.md) 引导到这份说明；
- Claude Code 可以通过 `.claude/skills/vless-deploy` 软链接直接加载，其他支持 skill 目录的工具
  可以复制或链接 `skills/vless-deploy/`；
- 其他 agent 可以直接给它 raw 链接：
  `https://raw.githubusercontent.com/MaplumeX/vless-script/main/skills/vless-deploy/SKILL.md`。

然后告诉 agent：“帮我在 <服务器> 上部署 XHTTP 节点，域名是 …”。只有在你确认之后，agent 才会用
`--force` 覆盖已有配置或停用 Caddy。

## 安全提示

- 不要公开导入链接、UUID、REALITY 私钥或 Short ID；
- 定期更新 Xray，留意服务日志中的异常连接；
- 脚本会修改 Xray 配置和 UFW / firewalld 规则，请先了解服务器上已有的服务。

请在遵守所在地法律法规以及服务商使用条款的前提下使用本项目。
