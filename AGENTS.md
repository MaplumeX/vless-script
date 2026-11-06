# AGENTS.md

本仓库是一个 Bash 一键安装脚本 `install.sh`，在 Linux 服务器上部署 VLESS 节点，有两种方案：

- `reality`：VLESS + REALITY + Vision，Xray 直接监听 443；
- `xhttp`：VLESS + XHTTP + TLS，由 Caddy 在前面终止 TLS。上行和下行通常分别走两个域名，
  也可以让上行或全程经过 Cloudflare CDN（`--cdn up|full`），并可选 ECH。

用户文档见 `README.md`。

## 部署、重装、切换方案或写伪装站

如果用户要你在服务器上搭建或重装节点、在两种方案之间切换、为 XHTTP 域名制作伪装站，
或者排查节点连不上的问题：**先完整阅读 [`skills/vless-deploy/SKILL.md`](skills/vless-deploy/SKILL.md)，
再按其中的步骤执行**。其中几条硬性要求：

- 只有用户明确同意后，才能使用 `--force` 或停用 Caddy；
- `vless://` 导入链接属于凭据，只交给用户本人；
- 两个域名的伪装站必须各不相同，并且每次部署都要重新创作。

## 修改脚本时

- 保持 `set -Eeuo pipefail` 和 `umask 077`。新建需要被其他用户读取的文件或目录时，
  显式指定权限，例如 `install -m 0644`、`install -d -m 0755`。
- 兼容 Alpine 上的 BusyBox 和 OpenRC：`mktemp` 模板的 `XXXXXX` 必须放在末尾；
  不要依赖 GNU 专有的参数。
- 面向用户的输出使用中文，统一经过 `info` / `warn` / `die` 打印。
- 改完至少运行 `bash -n install.sh`。生成的配置应当可以通过 `xray run -test` 和
  `caddy validate --adapter caddyfile` 的校验。
- 新增或修改参数和行为时，同步更新 `README.md`，以及 `skills/vless-deploy/SKILL.md`
  中对应的步骤。
