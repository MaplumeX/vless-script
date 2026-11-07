# REALITY 方案

VLESS + REALITY + Vision。Xray 直接监听 443，握手时借用一个外部站点（目标域名）的 TLS，
不需要自己的域名和证书。

返回 [README](../README.md)。

## 配置概览

| 项目 | 值 |
| --- | --- |
| 协议 | VLESS |
| 传输 | RAW/TCP |
| 安全 | REALITY |
| Flow | `xtls-rprx-vision` |
| 监听 | `[::]:443` |
| REALITY 回落入口 | `127.0.0.1:4431` |
| 客户端指纹 | 默认 `chrome`，可用 `--fingerprint` 修改（不能用 `unsafe`） |

导入链接使用 `type=tcp`。它与服务端的 `network: raw` 兼容，能被更多客户端识别。

安装完成后，脚本会显示地址、UUID、公钥、Short ID、SNI 和导入链接。

## 选择目标域名

目标域名是握手时借用的外部 TLS 站点，**不需要解析到本机，也不要填自己的节点域名**。

建议选择满足以下条件的站点：

- 支持 TLS 1.3 和 HTTP/2；
- 使用标准的 TCP 443 端口；
- 从服务器所在网络访问稳定；
- 与服务器的网络环境相对匹配；
- 不需要额外跳转就能建立 TLS 连接。

REALITY 会把认证失败的连接转发到目标站点，所以不要选 CDN 类的目标，否则服务器可能被滥用为
大流量转发器。也不要使用来源不明的域名。

安装完成后，脚本会用 `xray tls ping` 检查目标站点。检查失败时只给出警告，不会删除已生成的配置。

## 服务器地址

导入链接里的服务器地址默认通过公网服务自动探测。探测失败且当前是交互式终端时，脚本会要求
手动输入。NAT、多出口或代理环境下探测结果可能不对，可以用 `--address` 指定客户端实际应该
连接的 IP 或域名：

```bash
sudo bash install.sh --mode reality --domain www.example.com --address node.example.net --force
```

## 路由规则

1. REALITY 回落流量只允许访问所配置的目标域名，其余回落流量阻断；
2. `geosite:google` 和 `geosite:google-cn` 直连；
3. `geosite:cn` 和 `geoip:cn` 阻断；
4. 其他流量直连。
