# hybrid 方案

VLESS Encryption + Vision + XHTTP。服务端结构和 [XHTTP 方案](xhttp.md) 相同：Caddy 终止 TLS，Xray 只监听
`127.0.0.1:30001`。不同的是上下行走完全不同的路径：上行经 IPv6 直连本机，下行经 IPv4 走
Cloudflare 并启用 ECH；VLESS 层固定启用 VLESS Encryption 和 Vision。

返回 [README](../README.md)。

## 结构

| | 上行 | 下行 |
| --- | --- | --- |
| 域名 | 上行域名，灰云，**只配 AAAA** | 下行域名，橙云，**只配 A** |
| 路径 | 客户端 →（IPv6）→ 本机 Caddy | 客户端 →（IPv4）→ Cloudflare →（IPv4 回源）→ 本机 Caddy |
| 安全层 | TLS（Caddy 签发的证书） | TLS（Cloudflare 终止）+ ECH |
| XHTTP | `stream-up` | 下行 GET 流（`extra.downloadSettings`） |
| VLESS 层 | VLESS Encryption（`mlkem768x25519plus`，X25519 认证，`xorpub`）+ Vision，作用于整个会话 | 同左 |

前端、回源和伪装站点与 XHTTP 方案相同。

## 效果与代价

效果：

- 两条连接的目标（本机对 Cloudflare）、IP 协议（IPv6 对 IPv4）和外部可见的 SNI（上行域名对
  `cloudflare-ech.com`）都不同，很难被关联起来；
- 请求中的 VLESS 头部（UUID、目标地址）只出现在直连的上行里，Cloudflare 看不到；经过 Cloudflare 的
  下行数据也由 VLESS Encryption 加密；
- Vision 填充内层 TLS 握手的长度，减轻 TLS in TLS 特征。在 XHTTP 上，Vision 必须和 VLESS Encryption
  搭配使用。

代价：

- 大流量的下行全部经过 Cloudflare 免费套餐，国内晚高峰可能较慢，长期大流量使用也可能违反其服务条款；
- 上行直连本机 IPv6，IP 被封时节点不可用；
- 对客户端的要求最高，见下文 [客户端要求](#客户端要求)。

## 准备

1. **两个不同的域名**。建议使用不同的主域名，例如 `a.example.com` 和 `b.example.net`，让外人从证书和
   DNS 上看不出两者有关系。下行域名需要托管在 Cloudflare。
2. **公网 IPv6**。服务器要有公网 IPv6，并且云安全组对 **IPv4 和 IPv6** 都放行 TCP 80、443。脚本检测
   不到本机公网 IPv6 时会直接退出。
3. **DNS**，先全部设为灰云：
   - 上行域名**只配 AAAA**，指向本机 IPv6；
   - 下行域名**只配 A**，指向本机 IPv4。

   ```text
   up.example.com.    AAAA  2001:db8::10
   down.example.net.  A     203.0.113.10
   ```

## 安装

```bash
sudo bash install.sh --mode hybrid \
  --up-domain up.example.com --down-domain down.example.net \
  [--cdn-address <IPv4 优选 IP 或优选域名>]
```

交互模式下在方案菜单中选 3。

- `--cdn`、`--ech` 和 `--vless-enc` 在这个方案里是固定的，传入会被忽略；
- `--ech-config` 和 `--fingerprint` 仍然可用；
- `--cdn-address` 不能是 IPv6 地址。

脚本会检查：上行域名应解析到本机 IPv6，且没有 A 记录；下行域名在灰云阶段应解析到本机 IPv4，且没有
指向本机的 AAAA 记录。不符合时只提醒，不中断。

## 输出的链接

| 链接 | 下行 | 何时可用 |
| --- | --- | --- |
| **主链接** | 经 Cloudflare 连接下行域名（地址可以是优选 IP），带 `host` 和 ECH；`downloadSettings.sockopt` 中设置 `domainStrategy: UseIPv4`，让客户端固定通过 IPv4 连接 Cloudflare | 下行域名切换为橙云之后 |
| **测试链接** | 直连下行域名，不带 ECH | 切换橙云之前，用来确认服务端正常 |

两条链接的上行都直连上行域名，并且都带有 `encryption=`（VLESS Encryption 的客户端参数）和
`flow=xtls-rprx-vision`。

## Cloudflare 设置

安装完成后，按脚本打印的清单为**下行域名**完成：

1. SSL/TLS 加密模式选 **Full (strict)**；
2. 关闭 **Always Use HTTPS**；
3. 关闭 **Bot Fight Mode**，或为 XHTTP 路径添加 WAF 跳过规则；
4. 确认 **Encrypted ClientHello (ECH)** 已打开；
5. 只保留 A 记录，最后切换为**橙云**。

上行域名始终保持灰云。下行是 GET 流，不需要打开 gRPC。每一项的说明见
[XHTTP 方案 · 经过 Cloudflare CDN](xhttp.md#进阶经过-cloudflare-cdn)。

## 客户端要求

- 需要较新的 Xray 内核，支持 VLESS Encryption、XHTTP 上的 Vision、ECH 和 `extra.downloadSettings`，
  例如使用最新 Xray 内核的 v2rayN / v2rayNG。mihomo 等其他内核没有验证过；
- 客户端所在网络必须**同时有 IPv4 和 IPv6**，否则上行或下行有一侧连不上。

本仓库在本地验证过：由脚本生成的服务端配置和链接（上行经 IPv6、下行经 IPv4），以及 `UseIPv4` 确实对
下行生效。ECH 的验证见 [XHTTP 方案 · ECH](xhttp.md#ech)。没有用真实的 Cloudflare 和真实的 IPv6 网络
做过完整测试。
