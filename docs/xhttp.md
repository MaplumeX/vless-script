# XHTTP 方案

VLESS + XHTTP + TLS。Caddy 在 443 上用你自己域名的真实证书终止 TLS，再按路径把 XHTTP 请求
以 h2c 转给只监听本地端口的 Xray。上行和下行分别走两个域名、两条互不相关的连接；也可以让
上行或全程经过 Cloudflare CDN，并可选启用 ECH。

返回 [README](../README.md)。

- [配置概览](#配置概览)
- [准备域名](#准备域名)
- [进阶：上行和下行分走 IPv4 / IPv6](#进阶上行和下行分走-ipv4--ipv6)
- [进阶：经过 Cloudflare CDN](#进阶经过-cloudflare-cdn)
- [ECH](#ech)
- [VLESS Encryption + Vision](#vless-encryption--vision)
- [伪装站点](#伪装站点)
- [客户端与指纹](#客户端与指纹)

## 配置概览

| 项目 | 值 |
| --- | --- |
| 协议 | VLESS |
| 传输 | XHTTP。服务端 `mode: auto`；直连链接用 `stream-up`，CDN 链接用 `packet-up` |
| 前端 | Caddy 监听 80、443，自动申请证书 |
| 回源 | `127.0.0.1:30001`，h2c，`flush_interval -1` |
| 来源地址 | 信任 Caddy 转发的 `X-Forwarded-For`（`sockopt.trustedXForwardedFor`），Xray 日志记录客户端的真实地址；经过 Cloudflare 时记录的是 Cloudflare 节点的地址 |
| 上行 | 上行域名，ALPN `h2` |
| 下行 | 下行域名（`extra.downloadSettings`），ALPN `h2`；全程 CDN 时与上行同一个域名 |
| CDN | 可选，`--cdn up` 或 `--cdn full`（仅 Cloudflare），可选 ECH |
| VLESS 层 | 经过 CDN 时默认启用 VLESS Encryption + Vision，否则默认 `none`；可用 `--vless-enc on/off` 修改 |
| 客户端指纹 | 默认 `chrome`，可用 `--fingerprint` 修改，包括 `unsafe`（原生 Go TLS） |
| 其他路径 | 每个域名各自的伪装站点 `/var/www/<域名>/`，默认为空 |

Caddy 的安装来源：Debian / Ubuntu 用官方 apt 源，Fedora / RHEL 用官方 COPR，Alpine 和 openSUSE
用系统源。

安装完成后，脚本会显示上下行域名、UUID、路径和导入链接。

## 准备域名

准备两个不同的域名，可以是同一主域名下的两个子域名，例如 `up.example.com` 和
`down.example.com`；全程走 CDN 时只需要一个。为它们添加 A / AAAA 记录，指向服务器。

Caddy 需要通过 80 或 443 完成 ACME 验证，所以要在云安全组中放行 TCP 80、TCP 443（UDP 443 可选）。
TCP 80、443 不能被 Caddy 以外的程序占用；Xray 正占用 443（例如原来装的是 REALITY）时，脚本会
自动把它改为只监听本地端口。

默认情况下，**两个域名在 Cloudflare 等 DNS 服务商处都应保持“仅 DNS”（灰云）**，直接连到服务器。
不要直接打开 CDN 代理（橙云）：默认链接的上行使用 `stream-up`，未经设置的 CDN 通常无法流式转发
上行请求；SSL 模式设置不当还会造成无限重定向。需要经过 CDN 时，请看下文
[经过 Cloudflare CDN](#进阶经过-cloudflare-cdn)。

脚本会检查每个域名的解析结果是否包含本机公网地址。不包含时只给出提醒，不会中断，以兼容经过
CDN 的场景。Caddy 启动后，脚本最多等待约 90 秒，确认每个域名的 HTTPS 都可用。

## 进阶：上行和下行分走 IPv4 / IPv6

两个域名都解析到同一个地址时，上行和下行虽然已经拆成两条连接，外部观察者仍然可以按
“同一客户端、同一服务器 IP、同时建立”把它们配成一对。如果服务器有公网 IPv6，可以只靠 DNS 让
两条连接落在不同的地址上：**每个域名只配一种记录**。脚本和服务端配置都不需要改。

| 配法 | 上行域名 | 下行域名 | 效果 |
| --- | --- | --- | --- |
| 都只配 IPv4 | A | A | 两条连接都连同一个 IPv4 地址 |
| 都配双栈 | A + AAAA | A + AAAA | 由客户端自行选择，通常两条都走同一种协议，结果不可控 |
| **一个 IPv4、一个 IPv6** | 只配 A | 只配 AAAA | 上行固定走 IPv4，下行固定走 IPv6 |
| 两个不同的 IPv4 | A → IP1 | A → IP2 | 需要服务器有多个公网 IPv4 |

示例（反过来也可以，按你所在网络哪一侧更稳定，决定由谁承担大流量的下行）：

```text
up.example.com.    A     203.0.113.10
down.example.com.  AAAA  2001:db8::10
```

服务端不用改，是因为：Caddy 默认同时监听 IPv4 和 IPv6，Xray 只监听 `127.0.0.1`；脚本的 DNS 检查
也接受只解析到本机 IPv6 的域名；UFW 启用 IPv6 时（`IPV6=yes`，多数发行版的默认值），放行规则同样
作用于 IPv6。

使用前请确认：

- 服务器有公网 IPv6，并且云安全组也对 **IPv6** 放行了 TCP 80、443。不少厂商的 IPv4 和 IPv6
  安全组规则是分开设置的；
- 只配了 AAAA 的域名申请证书时，Let's Encrypt 会通过 IPv6 访问验证，IPv6 入站不通就签不出证书；
- **客户端所在网络必须有 IPv6**。只配了 AAAA 的那个域名无法回退到 IPv4，没有 IPv6 时这一侧连不上，
  整个节点也就不可用。部分公司网络、酒店 Wi-Fi 和老旧路由器没有 IPv6；
- IPv6 地址通常没有经过 NAT，可能对应到具体设备，更容易被做设备级分析。这里只把一个方向放在
  IPv6 上，算是一种折中。

切换配法只需要修改 DNS 记录并等待生效，不必重新运行脚本。证书按域名签发，与解析到哪个地址无关；
但新地址必须能从外部访问，否则之后证书续期会失败。

想更进一步，让下行经过 Cloudflare，可以看 [hybrid 方案](hybrid.md)。

## 进阶：经过 Cloudflare CDN

可以让一部分或全部流量经过 Cloudflare（目前只支持 Cloudflare）。三种方式的服务端 Xray 配置完全
相同，区别只在于用几个域名，以及输出哪些链接。

| 方式 | 参数 | 域名 | 输出的链接 | 适合 |
| --- | --- | --- | --- | --- |
| 不走 CDN（默认） | `--cdn none` | 两个，都灰云 | 分离直连 | 线路好，只想要上下行分离 |
| 上行走 CDN、下行直连 | `--cdn up` | 两个，上行橙云、下行灰云 | 分离直连；上行 CDN；全程 CDN 应急 | 让上下行更难关联，大流量仍直连 |
| 全程走 CDN | `--cdn full` | 一个，橙云 | 全程 CDN | 本机 IP 已被封，或不想暴露 IP |

- `--cdn up`：上行经过 Cloudflare，下行直连服务器，两条连接的目标 IP、ASN 和网络路径都不同。
  上行流量通常很小，不会给 CDN 带来负担。另外输出的**全程 CDN 应急链接**只用上行域名，上下行都
  经过 Cloudflare，本机 IP 被封、直连不通时可以切到这条。
- `--cdn full`：只需要一个域名，上下行都经过 Cloudflare，服务器 IP 不会出现在客户端的连接里。

### 步骤

1. **先把所有域名都设为灰云**并指向服务器，以便 Caddy 首次签发证书。
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

   经过 CDN 的链接都使用 `packet-up`，不依赖 Cloudflare 的 gRPC 开关；并且总是带上 `host` 参数，
   所以把地址换成优选 IP 也能正常工作。
3. 按脚本最后打印的清单，为经过 CDN 的域名设置 Cloudflare：
   - SSL/TLS 加密模式选 **Full (strict)**，不要用 Flexible；
   - 关闭 **Always Use HTTPS**，让证书续期的 HTTP-01 验证请求能到达源站；
   - 关闭 **Bot Fight Mode**，或为 XHTTP 路径添加 WAF 跳过规则；
   - 启用 ECH 时，确认 **SSL/TLS → 边缘证书 → Encrypted ClientHello (ECH)** 已打开（免费套餐默认打开）；
   - 可选：打开 **gRPC** 后，`--cdn up` 的上行 CDN 链接可以把 `mode=packet-up` 改为 `mode=stream-up`，
     全程 CDN 链接可以尝试改为 `mode=stream-one`。
4. 把经过 CDN 的域名切换为**橙云**。`--cdn up` 时下行域名保持灰云。
5. 验证：`curl -sI https://<经过 CDN 的域名>/` 的响应头中应包含 `cf-ray`；然后用 CDN 链接实际连接测试。

### 需要知道的几点

- `--cdn up` 时下行直连，服务器 IP 并没有被隐藏。这种方式的目的是让上下行难以关联，而不是隐藏 IP。
- 全程 CDN 时所有流量都由 Cloudflare 转发。免费套餐在国内晚高峰可能较慢，长期大流量使用也可能
  违反 Cloudflare 的服务条款。
- 用 `--vless-enc off` 关闭 VLESS Encryption 时，Cloudflare 能看到 VLESS 头部（UUID 和目标地址）。
  访问 HTTPS 网站时，网页内容仍由内层 TLS 保护。
- 域名切换为橙云后，重新运行脚本时 DNS 检查会给出提醒，但不会中断安装；已签发的证书不受影响。
- 某次证书续期失败时，可以临时把域名切回灰云，等 Caddy 续期成功后再切回橙云。

本仓库在本地验证过：经 Caddy 的单域名 `packet-up` 链接、带 ECH 的 Xray 客户端，以及通过阿里 DoH 取得
Cloudflare 的 ECH 配置并完成握手。但没有用真实的 Cloudflare 域名做过完整测试，以上 Cloudflare
设置参考的是社区经验。

## ECH

加 `--ech`（或在交互菜单中选择启用）后，所有经过 CDN 的链接都会带上 `ech` 参数。客户端先通过 DoH
查询 `cloudflare-ech.com` 的 HTTPS 记录，取得 Cloudflare 的 ECH 公钥，再把真实的 SNI（你的域名）
加密后放进 ClientHello。外部只能看到所有 Cloudflare 站点共用的 `cloudflare-ech.com`。

- 默认的配置来源是 `cloudflare-ech.com+https://dns.alidns.com/dns-query`：通过阿里 DoH 查询，在国内
  也能直连；查询的是公共域名，不会暴露你自己的域名。可以用 `--ech-config` 换成别的 DoH 地址，或直接
  填 base64 格式的 ECHConfigList（不推荐，Cloudflare 会定期轮换密钥）。
- ECH 只作用于客户端到 Cloudflare 这一段。`--cdn up` 时直连的下行仍然是明文 SNI。
- 客户端必须支持 ECH（例如较新的 Xray 内核；v2rayN / v2rayNG 都能识别链接里的 `ech` 参数）。客户端
  不支持或取不到 ECH 配置时会直接连不上，不会退回普通 TLS，这时删掉链接里的 `ech` 参数即可。
- ECH 由 Cloudflare 终止，所以域名还是灰云时，带 ECH 的链接连不通。

## VLESS Encryption + Vision

Cloudflare 会终止外层 TLS。如果 VLESS 本身不加密（`decryption: none`），Cloudflare 就能看到经过它的
请求中的 VLESS 头部，包括 UUID 和每条连接的目标地址。因此经过 CDN 时，脚本默认启用：

- **VLESS Encryption**（`mlkem768x25519plus`，X25519 认证，`xorpub` 外观）：VLESS 头部和数据在客户端
  与 Xray 之间端到端加密，Cloudflare 剥掉 TLS 后只能看到密文；
- **Vision**（`xtls-rprx-vision`）：填充内层 TLS 握手的长度，减轻 TLS in TLS 特征。在 XHTTP 上，
  Vision 只能和 VLESS Encryption 一起使用。

交互模式下会询问一次（默认启用），也可以用 `--vless-enc on|off` 指定。需要知道：

- 直连链接和 CDN 链接共用同一个入站，所以**一次安装的所有链接会一起启用**，链接里都带有
  `encryption=` 和 `flow=xtls-rprx-vision`；
- 客户端需要较新的 Xray 内核。要兼容不支持的客户端，可以加 `--vless-enc off`；
- 不经过 CDN 时默认不启用，因为 TLS 本来就在你自己的 Caddy 上终止。想要 Vision 的填充，也可以用
  `--vless-enc on` 打开。

本仓库在本地验证过：启用后直连链接（`stream-up`）、上行 CDN 链接（`packet-up` + `downloadSettings`）和
全程 CDN 链接（`packet-up`）都能正常上传和下载。

## 伪装站点

脚本不生成伪装页面：每个域名的站点目录在创建时为空，访问首页返回 404。目录已存在时，脚本不会改动
其中的内容。

伪装站需要每次部署单独制作。如果所有人都用同一份内置页面，扫描时它反而会成为统一的特征。建议：

- 两个域名放不同的、多页面的静态站点，并且不要互相链接，让人从内容上看不出它们属于同一台节点；
- 全程 CDN 时只有一个域名，放一个站点即可。

文件需要对 Caddy 用户可读，例如：

```bash
chmod -R u=rwX,go=rX /var/www/up.example.com /var/www/down.example.com
```

也可以让 AI agent 来写，它会按 [`skills/vless-deploy/SKILL.md`](../skills/vless-deploy/SKILL.md)
中的要求为每个域名创作不同的站点，见 README 的“让 AI agent 部署”。

## 客户端与指纹

导入链接中的下行配置放在 `extra` 参数里（URL 编码的 JSON，包含 `downloadSettings`），需要较新的
Xray 系客户端或 mihomo 才能识别。全程 CDN 链接没有 `extra` 参数。启用 ECH 时，客户端还需要支持
`ech` 参数，见上文 [ECH](#ech)。

链接中的上行（`fp`）和下行（`downloadSettings.tlsSettings.fingerprint`）都会写明指纹，默认为 `chrome`。
这是 Xray 官方推荐的、也是主流的做法。之所以必须写明，是因为不同客户端对留空的处理相反：Xray 系
客户端留空时用 `chrome`，mihomo 留空时却用原生 Go TLS。在 mihomo 中手动配置时，请设置
`client-fingerprint: chrome`，与链接保持一致。

如果你认同“完全不用 uTLS、只用原生 TLS”的思路，可以加 `--fingerprint unsafe`。`unsafe` 不会降低加密
强度，也不会跳过证书校验，只是 ClientHello 会呈现 Go 程序的特征，不再模仿浏览器。Xray 官方不推荐
这样做，非 Xray 内核的客户端也可能不认识这个值。
