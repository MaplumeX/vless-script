# 运维与排障

返回 [README](../README.md)。

## 生成的文件

| 用途 | 位置 | 方案 |
| --- | --- | --- |
| Xray 程序 | `/usr/local/bin/xray` | 全部 |
| Xray 配置 | `/usr/local/etc/xray/config.json` | 全部 |
| GeoIP / GeoSite | `/usr/local/share/xray/geoip.dat`、`geosite.dat` | 全部 |
| Xray 服务 | `xray.service`（systemd）/ `/etc/init.d/xray`（OpenRC） | 全部 |
| Caddy 配置 | `/etc/caddy/Caddyfile` | XHTTP、hybrid |
| Caddy 服务 | `caddy.service`（systemd）/ `/etc/init.d/caddy`（OpenRC） | XHTTP、hybrid |
| 伪装站点 | `/var/www/<上行域名>/`、`/var/www/<下行域名>/`（全程 CDN 时只有一个） | XHTTP、hybrid |

重新安装时的处理：

- **Xray 配置**：systemd 环境直接覆盖 `config.json`。OpenRC 的官方安装器使用多文件配置目录，为避免
  旧配置与新配置合并冲突，脚本会先删除目录中的旧 JSON 配置，再写入单个 `config.json`。两种情况都不
  保留备份；
- **Caddyfile**：首行带有 `# Managed by vless-reality install.sh` 标记时直接覆盖；没有标记时，交互模式
  会先询问，非交互模式需要加 `--force`；
- **伪装站点目录**：已存在时不改动其中的内容。

## 路由规则

1. REALITY 回落流量只允许访问所配置的目标域名，其余回落流量阻断（仅 REALITY 方案）；
2. `geosite:google` 和 `geosite:google-cn` 直连；
3. `geosite:cn` 和 `geoip:cn` 阻断；
4. 其他流量直连。

这意味着节点无法访问大多数中国大陆的域名和 IP。不需要这一限制时，请修改 `config.json` 中的
`routing.rules`，校验后重启 Xray。

GeoIP 和 GeoSite 数据来自 Loyalsoldier/v2ray-rules-dat，每周一 04:30 由 Xray 自动更新。

## 常用命令

systemd：

```bash
systemctl status xray --no-pager
systemctl restart xray
journalctl -u xray -n 100 --no-pager
journalctl -u xray -f
```

OpenRC / Alpine：

```bash
rc-service xray status
rc-service xray restart
rc-update add xray default
```

XHTTP 和 hybrid 方案中的 Caddy：

```bash
systemctl status caddy --no-pager      # OpenRC：rc-service caddy status
journalctl -u caddy -n 100 --no-pager
```

校验配置、查看版本：

```bash
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
/usr/local/bin/xray version
```

## 常见问题

### 端口已被占用

脚本会在安装前停止，并显示监听该端口的程序。可以进一步检查：

```bash
ss -lntp 'sport = :443'
ss -lntp 'sport = :80'
```

停止或调整占用端口的服务后，再重新运行脚本。从 XHTTP / hybrid 切回 REALITY 时，443 被 Caddy 占用，
需要先停用 Caddy，见 README 的“重新安装与切换方案”。

### 服务正常运行，但客户端连不上

通用检查：

1. 云厂商安全组是否放行了所需端口（hybrid 还要检查 IPv6 规则）；
2. UFW、firewalld、nftables 或 iptables 是否放行了所需端口；
3. 客户端中的参数是否与脚本输出完全一致，最好直接导入链接。

REALITY：

- 客户端是否支持 REALITY 和 XTLS Vision；
- 服务器能否访问目标域名的 TCP 443，可以用 `xray tls ping <目标域名>:443` 检查。

XHTTP：

- 证书没签下来，通常是 DNS 没生效，或 80 / 443 入站没放行；
- 客户端是否支持 XHTTP 和 `extra.downloadSettings`；在 mihomo 中手动配置时，是否设置了
  `client-fingerprint`，并与链接里的 `fp` 一致；
- 链接里有 `encryption=mlkem768…` 时，客户端内核是否足够新。旧客户端可以用 `--vless-enc off` 重装。

经过 Cloudflare 时：

- SSL 模式是 Flexible 会导致重定向循环，应改为 Full (strict)；
- Bot Fight Mode 或 WAF 拦截 POST 请求时，会返回 403 或质询页；
- 启用 ECH 时，确认客户端支持 ECH、能访问 DoH 地址（默认 `dns.alidns.com`），并且 Cloudflare 的 ECH
  开关已打开。可以删掉链接里的 `ech` 参数对比测试；
- 把模式改成 `stream-up` 或 `stream-one` 后，需要打开 Cloudflare 的 gRPC 开关。

hybrid：

- 客户端网络是否同时有 IPv4 和 IPv6；
- 上行域名是否只有 AAAA、仍是灰云；
- 测试链接能用、主链接不能用时，问题在 Cloudflare 这一段（橙云、SSL 模式、WAF、ECH 开关）。

### Xray 日志里刷屏 `X-Forwarded-For` 警告

```text
[Warning] common/protocol/http: received "X-Forwarded-For" from 127.0.0.1:... but "sockopt.trustedXForwardedFor" is not configured
```

XHTTP 和 hybrid 方案中，Caddy 转发每个请求时都会带上 `X-Forwarded-For`。较新的 Xray 在入站没有配置
`sockopt.trustedXForwardedFor` 时，每个请求都会打一条这样的警告。功能不受影响，只是日志里所有来源
都显示为 `127.0.0.1`。

现在的脚本已经在 XHTTP 入站上配置了它，重新运行脚本即可。不想重装时，可以手动在 `config.json` 中
`xhttp-in` 入站的 `streamSettings` 里加上下面这段，校验后重启 Xray：

```json
"sockopt": {
  "trustedXForwardedFor": ["X-Forwarded-Proto"]
}
```

Caddy 转发时总会加上 `X-Forwarded-Proto`，并用自己看到的来源覆盖客户端发来的 `X-Forwarded-*`；Xray 又
只监听本机，请求必经 Caddy，所以这样信任 XFF 是安全的。

### 自动探测到的公网地址不正确

NAT、多出口或代理环境可能影响自动探测。REALITY 方案重新运行时用 `--address` 指定客户端实际应该
连接的 IP 或域名：

```bash
sudo bash install.sh --mode reality --domain www.example.com --address node.example.net --force
```
