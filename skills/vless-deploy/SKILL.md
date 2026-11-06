---
name: vless-deploy
description: 使用本仓库的 install.sh 在 Linux 服务器上部署、重装或切换 VLESS 节点（REALITY + Vision，或 XHTTP + TLS 上下行分离），并为 XHTTP 方案的两个域名各写一个不同的静态伪装站。当用户要求搭建/安装/重装节点、选择或切换 REALITY 与 XHTTP 方案、生成或更换伪装站、排查节点连不上时使用。
---

# 用 install.sh 部署 VLESS 节点

本仓库的 `install.sh` 支持两种方案：

| 方案 | `--mode` | 需要用户提供 | 前端 |
| --- | --- | --- | --- |
| VLESS + REALITY + Vision | `reality` | 一个 REALITY 目标域名（别人的站点，不需要解析到本机） | Xray 直接监听 443 |
| VLESS + XHTTP + TLS，上下行分离 | `xhttp` | 两个不同的、已解析到本机的自有域名 | Caddy 监听 80/443，Xray 只监听 `127.0.0.1:30001` |

脚本的完整行为见仓库根目录的 `README.md`；本文档只规定 agent 怎样安全地执行它，以及
怎样完成脚本刻意留给人做的部分：XHTTP 方案的伪装站。

## 0. 先弄清楚在哪台机器上执行

- agent 就运行在目标服务器上：直接 `sudo bash ./install.sh …`。
- agent 在本地、服务器通过 SSH 访问：把本仓库的脚本通过标准输入传过去，保证执行的
  是当前检出的版本，而不是 GitHub 上的版本：

  ```bash
  ssh <host> 'sudo bash -s -- --mode xhttp --up-domain … --down-domain …' < install.sh
  ```

  后续的检查和写伪装站文件同样通过 `ssh <host> '…'` 执行。
- 手边没有本仓库的检出（例如只拿到了这份说明）：先下载脚本并通读一遍，确认内容后再执行：

  ```bash
  curl -fsSL https://raw.githubusercontent.com/MaplumeX/vless-reality/main/install.sh -o install.sh
  ```

- 不知道目标主机时询问用户；不要猜测，也不要在本地开发机上执行安装。

## 1. 确定方案和参数

用户没说用哪种方案时，用一两句话说明区别后让用户选：

- REALITY：无需域名，部署最快；依赖 uTLS 指纹模拟和借用目标站点。
- XHTTP：需要两个域名，使用自己的真实证书，上行和下行拆到两条连接；
  多一层 Caddy，开销略高。

然后收集参数：REALITY 要一个目标域名；XHTTP 要上行域名和下行域名（两者必须不同）。
REALITY 方案在 NAT 或多出口环境下，可以额外用 `--address` 指定客户端实际连接的地址。

客户端 TLS 指纹默认是 `chrome`，这是 Xray 官方推荐的主流做法，一般不用改。用户明确
希望不用 uTLS 时，XHTTP 方案可以加 `--fingerprint unsafe`（原生 Go TLS）。这时要告诉
用户：Xray 官方不推荐这样做，非 Xray 内核的客户端也可能不认识这个值。REALITY 方案
不能用 `unsafe`。连接出现握手卡顿时，可以试试 `--fingerprint firefox`。

## 2. 部署前检查（只读）

在目标机上执行，把发现的问题告诉用户，再决定是否继续：

```bash
cat /etc/os-release; ps -p 1 -o comm=          # 发行版与 systemd/OpenRC
ss -ltnp 'sport = :443'; ss -ltnp 'sport = :80' # 端口占用
ls /usr/local/etc/xray/*.json 2>/dev/null       # 已有 Xray 配置
head -n 1 /etc/caddy/Caddyfile 2>/dev/null      # 已有 Caddy 配置及是否由本脚本生成
```

- REALITY：
  - 目标域名不能是用户自己的节点域名；
  - 目标域名应支持 TLS 1.3 和 h2：
    `curl -sI --tlsv1.3 --http2 https://<域名> -o /dev/null -w '%{http_version}\n'`；
  - 避免容易让节点被滥用为转发器的 CDN 目标。
- XHTTP：
  - 用 `getent ahosts <域名>` 对比 `curl -4s https://api.ipify.org` 的结果，确认两个
    域名都已解析到本机（经过 CDN 时可以例外，但要提醒用户证书申请可能失败）；
  - TCP 80 不能被 Caddy 以外的程序占用；
  - 提醒用户在云安全组中放行 TCP 80、TCP 443。
- 443 被 Caddy 占用而用户要装 REALITY（即从 XHTTP 切回 REALITY）：脚本会拒绝执行。
  先征得用户同意，再执行 `systemctl disable --now caddy`，或在 OpenRC 上执行
  `rc-service caddy stop && rc-update del caddy default`。Caddy 上可能还托管着别的站点，
  不要擅自停掉。

## 3. 执行脚本

agent 没有交互终端，必须通过参数把选择全部传进去，否则脚本会报"无法读取交互输入"并退出：

```bash
sudo bash ./install.sh --mode reality --domain <目标域名> [--address <地址>]
sudo bash ./install.sh --mode xhttp --up-domain <上行域名> --down-domain <下行域名>
```

- `--force` 会直接覆盖现有的 Xray 配置，以及不是本脚本生成的 Caddyfile，不保留备份；
  旧的导入链接也会随之失效。只有用户明确同意覆盖后才能加。没加 `--force` 时脚本报
  "已存在 … 配置"，就把这一情况告诉用户并询问，不要自行重试加上 `--force`。
- 脚本会安装软件包、改防火墙规则、启动服务，这些都在用户要求部署的范围内。除此之外
  不要改动机器上的其他配置。
- 脚本结束时输出的 `vless://` 链接就是登录凭据：原样交给用户；不要写进仓库、记忆、
  日志文件，也不要发给任何第三方服务。

## 4. XHTTP 方案：写伪装站

脚本只创建两个空目录 `/var/www/<上行域名>` 和 `/var/www/<下行域名>`，Caddy 分别把
它们作为两个域名的站点根目录。目录为空时首页返回 404，伪装站需要 agent 来写。
目录已经存在且有内容时，脚本不会动它；agent 也不要覆盖，先问用户。

### 选题方向

伪装页只对主动探测有用，被动流量分析看不到页面内容。但如果有人既爬了站点，又统计了
流量，站点类型就应该和流量画像大致对得上。这套节点的实际画像是：一个新域名、一台 VPS、
只有一两个客户端，长时间传输大量数据；下行是长时间的 GET 流，上行是长时间的 POST 流。
最吻合这个画像的是**个人或小项目规模的自托管服务**，不是大型公共平台。

- **下行域名：往外发大文件的站**。例如：
  - 摄影作品集或相册，声称提供原图下载；
  - 自己开源小项目的发布与下载页；
  - 播客或音频节目归档；
  - 个人维护的软件镜像说明页。
- **上行域名：接收上传的站**。例如：
  - 某个小应用的 API 或上传后端的文档页；很多 API 域名的根路径本来就只有一页文档；
  - 个人备份与同步端点的说明页；
  - 投稿或文件收集服务的说明页，只做文字说明，不放表单。
- **不要装成大型高流量平台**，例如视频站、网盘、CDN、知名软件的官方下载站。新域名、
  普通 VPS 加上几张静态页撑不起这种身份，主动探测一看就穿。
- **不要真的托管大文件**来"做实"，否则会招来真实的下载流量和版权风险。页面上的下载项
  可以指向站内真实存在的小文件（校验和、README、用 SVG 画的缩略图、更新日志等），
  也可以说明"原图或完整文件按需提供"。所有链接都不能指向不存在的文件。
- 在上述方向内为每次部署随机挑选不同的具体题材，并让题材与域名的字面意思相呼应。
  用户指定了题材时，以用户的为准。

### 要求

- **两个站点完全不同**：主题、页面结构、文案、配色、排版、文件名都不一样，不共用
  CSS 或模板，也不互相链接。外人不应该能从内容上看出两个域名属于同一个人。
- **每次部署都重新创作**：不要复用以前写过的站点，也不要套用固定模板。否则所有用这个
  仓库部署的节点首页都一样，扫描时就成了一眼可识别的特征。
- **每个站点是多页面的**：至少一个首页和 2～4 个子页面（例如 about、几篇文章或项目
  介绍），页面之间用相对链接互相导航，每个页面都要有实在的内容。
- **内容看起来像真实的个人小站**：题材按上面的“选题方向”选。页面要有具体的细节，比如
  项目说明、更新记录、作品描述、接口说明，不要写成空泛的介绍。语言按用户的偏好；
  用户没有偏好时，跟域名或用户的交流语言保持一致。
- **纯静态、完全自包含**：只用 HTML 和 CSS；favicon 用内联的 SVG 文件。不加载外部字体、
  CDN 或统计脚本，不需要 JavaScript。
- **以下内容禁止出现**：
  - 冒充真实的公司、品牌、机构或个人（名称、Logo、商标、版权声明都不行）；
  - 照搬第三方网站的内容；
  - 登录框、注册或支付表单，虚构的商品、价格或评价；
  - 与代理、翻墙、VPN、Xray 相关的任何字眼；
  - XHTTP 路径或指向它的链接（路径在 `/usr/local/etc/xray/config.json` 的
    `xhttpSettings.path`）；
  - lorem ipsum、"建设中"之类的占位文本。
- **权限**：脚本设置了 `umask 077`，agent 在 root shell 里写文件时也要注意权限。
  写完后执行 `chmod -R u=rwX,go=rX /var/www/<域名>`，保证 Caddy 用户能读到。

### 验证

两个域名都要检查。证书未就绪时，可以先带 `-k` 测试内容：

```bash
d=<域名>
for p in / /about.html /<其他页面>; do
  curl -s -o /dev/null -w "$p %{http_code} %{content_type}\n" --resolve "$d:443:127.0.0.1" "https://$d$p"
done
curl -s -o /dev/null -w '%{http_code}\n' --resolve "$d:443:127.0.0.1" "https://$d/no-such-page"   # 期望 404
path=$(grep -o '"path": *"[^"]*"' /usr/local/etc/xray/config.json | cut -d'"' -f4)
grep -rlF "$path" /var/www/<上行域名> /var/www/<下行域名> && echo "泄露了 XHTTP 路径！"
sha256sum /var/www/<上行域名>/index.html /var/www/<下行域名>/index.html                    # 两者必须不同
```

站内的相对链接也要逐个检查，确认都能打开：

```bash
cd /var/www/<域名> && find . -name '*.html' | while read -r f; do
  grep -oE '(href|src)="[^"]*"' "$f" | cut -d'"' -f2 |
    grep -vE '^([A-Za-z][A-Za-z0-9+.-]*:|#|$)' | sed 's/[?#].*//' |
    while read -r p; do
      case "$p" in /*) t=".$p" ;; *) t="$(dirname "$f")/$p" ;; esac
      [[ "$t" == */ ]] && t="${t}index.html"
      [[ -e "$t" ]] || echo "$f → 缺失：$p"
    done
done   # 没有输出即全部正常
```

所有页面都要返回 200，内容类型为 `text/html`；不存在的页面返回 404；XHTTP 路径
没有出现在任何文件里。

## 5. 部署后检查与排障

- 服务状态：`systemctl status xray caddy --no-pager`（OpenRC：`rc-service xray status`、
  `rc-service caddy status`）。
- 配置校验：`/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json`；
  XHTTP 方案再执行 `caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`。
- 日志：`journalctl -u xray -n 100 --no-pager`、`journalctl -u caddy -n 100 --no-pager`。
- REALITY 连不上时：
  - 确认云安全组放行了 443；
  - 确认客户端支持 REALITY 和 Vision；
  - 用 `xray tls ping <目标域名>:443` 检查目标站点。
- XHTTP 连不上时：
  - 证书没签下来，通常是 DNS 没生效，或 80/443 入站没放行；
  - 用 `curl --resolve <域名>:443:127.0.0.1 https://<域名><路径>/x` 测试，返回 502 说明
    Xray 没在运行；
  - 客户端需要支持 xhttp 和 `extra.downloadSettings`；在 mihomo 中手动配置时要设置
    `client-fingerprint`，值与链接里的 `fp` 一致（默认 `chrome`）。mihomo 留空时会用原生 Go TLS。

## 6. 向用户汇报

用几行说明：

- 采用的方案和域名；
- 导入链接（原样给出）；
- XHTTP 方案中两个伪装站各自的主题和页面清单；
- 检查中发现的提醒，例如 DNS 不匹配、证书尚未签发、需要用户自己放行的云安全组端口；
- 没能验证的部分要明说，例如没有用真实客户端测试连接。
