#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly XRAY_INSTALL_URL_SYSTEMD="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
readonly XRAY_INSTALL_URL_OPENRC="https://github.com/XTLS/Xray-install/raw/main/alpinelinux/install-release.sh"
readonly GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
readonly GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
readonly CADDY_APT_KEY_URL="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
readonly CADDY_APT_LIST_URL="https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt"
readonly CADDY_APT_KEYRING="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
readonly XRAY_BIN="/usr/local/bin/xray"
readonly CONFIG_DIR="/usr/local/etc/xray"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly ASSET_DIR="/usr/local/share/xray"
readonly CADDY_FILE="/etc/caddy/Caddyfile"
readonly CADDY_MARK="# Managed by vless-reality install.sh"
readonly SITE_ROOT="/var/www"
readonly PORT="443"
readonly XHTTP_LOCAL_PORT="30001"
readonly VISION_FLOW="xtls-rprx-vision"
readonly DEFAULT_ECH_CONFIG="cloudflare-ech.com+https://dns.alidns.com/dns-query"
readonly FINGERPRINTS="chrome firefox safari ios android edge 360 qq random randomized randomizednoalpn unsafe"

mode=""
reality_domain=""
up_domain=""
down_domain=""
server_address=""
fingerprint="chrome"
cdn_mode=""
cdn_address=""
ech=""
ech_config="$DEFAULT_ECH_CONFIG"
site_domains=()
vless_enc=""
vless_decryption="none"
vless_encryption="none"
vless_flow=""
public_ipv6=""
force="false"
init_system=""
installer_tmp=""
config_tmp=""
config_tmp_dir=""
asset_tmp_dir=""
caddy_tmp_dir=""

cleanup() {
  [[ -z "${installer_tmp}" ]] || rm -f -- "${installer_tmp}"
  [[ -z "${config_tmp}" ]] || rm -f -- "${config_tmp}"
  [[ -z "${config_tmp_dir}" ]] || rm -rf -- "${config_tmp_dir}"
  [[ -z "${asset_tmp_dir}" ]] || rm -rf -- "${asset_tmp_dir}"
  [[ -z "${caddy_tmp_dir}" ]] || rm -rf -- "${caddy_tmp_dir}"
}
trap cleanup EXIT

info() {
  printf '\033[1;34m[信息]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[提醒]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：
  sudo bash install.sh
  sudo bash install.sh --mode reality --domain example.com [--address 203.0.113.10] [--force]
  sudo bash install.sh --mode xhttp --up-domain up.example.com --down-domain down.example.com
                       [--cdn up [--cdn-address 104.16.0.1] [--ech]] [--vless-enc on|off] [--force]
  sudo bash install.sh --mode xhttp --cdn full --domain cdn.example.com
                       [--cdn-address 104.16.0.1] [--ech] [--vless-enc on|off] [--force]
  sudo bash install.sh --mode hybrid --up-domain up.example.com --down-domain down.example.com
                       [--cdn-address 104.16.0.1] [--force]

参数：
  -m, --mode         安装方案：reality（VLESS + REALITY + Vision）、
                     xhttp（VLESS + XHTTP + TLS，Caddy 前置）或
                     hybrid（VLESS Encryption + Vision + XHTTP：上行 IPv6 直连，
                     下行 IPv4 经 Cloudflare + ECH）
  -d, --domain       REALITY 伪装站点域名；--cdn full 时为经过 Cloudflare 的那个域名
                     （不要带协议、端口或路径）
  -a, --address      REALITY 模式下客户端连接的服务器公网 IP 或域名；默认自动探测
      --up-domain    xhttp / hybrid 的上行域名（需解析到本机；hybrid 只配 AAAA）
      --down-domain  xhttp / hybrid 的下行域名（需解析到本机，且与上行域名不同；
                     hybrid 只配 A，安装后切换为橙云）
      --cdn          XHTTP 模式的 CDN（Cloudflare）方式：
                       none  两个域名都直连（默认）
                       up    上行域名经过 CDN、下行域名直连，另输出全程 CDN 应急链接
                       full  只用一个域名，上下行都经过 CDN
      --cdn-address  CDN 链接使用的优选 IP 或优选域名；默认使用经过 CDN 的域名
                     （hybrid 只接受 IPv4 优选 IP 或域名）
      --ech          为 CDN 链接启用 ECH（隐藏真实域名，需要客户端支持）
      --ech-config   ECH 配置来源，默认 cloudflare-ech.com+https://dns.alidns.com/dns-query；
                     也可填 base64 的 ECHConfigList。指定时自动启用 --ech
      --vless-enc    xhttp 方案是否启用 VLESS Encryption + Vision（on / off）；
                     经过 CDN 时默认 on，不经过时默认 off。所有链接一起生效，
                     需要较新的 Xray 内核。hybrid 固定启用
      --fingerprint  写入导入链接的客户端 TLS 指纹，默认 chrome；可选 chrome、firefox、
                     safari、ios、android、edge、360、qq、random、randomized、
                     randomizednoalpn，以及仅 xhttp 方案可用的 unsafe（原生 Go TLS）
  -f, --force        无交互覆盖已有 Xray / Caddy 配置
  -h, --help         显示帮助

未指定 --mode 时：给出 --cdn、--up-domain 或 --down-domain 视为 xhttp，
只给出 --domain 视为 reality，否则在终端中显示菜单供选择。hybrid 需要显式指定
--mode hybrid 或在菜单中选择；它固定启用 VLESS Encryption、Vision 和 ECH，
不接受 --cdn 和 --ech。
EOF
}

while (($# > 0)); do
  case "$1" in
    -m | --mode)
      (($# >= 2)) || die "$1 缺少参数"
      mode="$2"
      shift 2
      ;;
    -d | --domain)
      (($# >= 2)) || die "$1 缺少参数"
      reality_domain="$2"
      shift 2
      ;;
    -a | --address)
      (($# >= 2)) || die "$1 缺少参数"
      server_address="$2"
      shift 2
      ;;
    --up-domain)
      (($# >= 2)) || die "$1 缺少参数"
      up_domain="$2"
      shift 2
      ;;
    --down-domain)
      (($# >= 2)) || die "$1 缺少参数"
      down_domain="$2"
      shift 2
      ;;
    --cdn)
      (($# >= 2)) || die "$1 缺少参数"
      cdn_mode="${2,,}"
      shift 2
      ;;
    --cdn-address)
      (($# >= 2)) || die "$1 缺少参数"
      cdn_address="$2"
      shift 2
      ;;
    --ech)
      ech="true"
      shift
      ;;
    --ech-config)
      (($# >= 2)) || die "$1 缺少参数"
      ech="true"
      ech_config="$2"
      shift 2
      ;;
    --vless-enc)
      (($# >= 2)) || die "$1 缺少参数"
      vless_enc="${2,,}"
      shift 2
      ;;
    --fingerprint)
      (($# >= 2)) || die "$1 缺少参数"
      fingerprint="${2,,}"
      shift 2
      ;;
    -f | --force)
      force="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1（使用 --help 查看帮助）"
      ;;
  esac
done

validate_domain() {
  local domain="$1"
  local label
  local -a labels

  [[ ${#domain} -le 253 ]] || return 1
  [[ "$domain" == *.* ]] || return 1
  [[ "$domain" != *..* ]] || return 1
  [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

  IFS='.' read -r -a labels <<<"$domain"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

validate_address() {
  local address="$1"
  [[ -n "$address" && ${#address} -le 253 ]] || return 1
  case "$address" in
    *'/'* | *'?'* | *'#'* | *'@'* | *'['* | *']'*) return 1 ;;
  esac
  [[ "$address" =~ ^[A-Za-z0-9:.-]+$ ]]
}

# 固定的 base64 ECHConfigList，或“域名+DoH 地址”/DNS 服务器地址形式。
validate_ech_config() {
  local pattern='^[A-Za-z0-9+/=:._~%?&-]+$'
  [[ -n "$ech_config" && ${#ech_config} -le 2048 && "$ech_config" =~ $pattern ]]
}

validate_fingerprint() {
  [[ " ${FINGERPRINTS} " == *" ${fingerprint} "* ]] ||
    die "不支持的指纹：${fingerprint}（可选：${FINGERPRINTS}）"
  if [[ "$mode" == "reality" && "$fingerprint" == "unsafe" ]]; then
    die "REALITY 依赖 uTLS，不能使用 unsafe 指纹。"
  fi
}

has_tty() {
  { : </dev/tty && : >/dev/tty; } 2>/dev/null
}

urlencode() {
  local LC_ALL=C
  local str="$1" out="" c i

  for ((i = 0; i < ${#str}; i++)); do
    c="${str:i:1}"
    case "$c" in
      [A-Za-z0-9.~_-]) out+="$c" ;;
      *)
        printf -v c '%%%02X' "'$c"
        out+="$c"
        ;;
    esac
  done
  printf '%s' "$out"
}

detect_init_system() {
  local pid_one=""

  pid_one="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]' || true)"
  if command -v systemctl >/dev/null 2>&1 &&
    { [[ "$pid_one" == "systemd" ]] || [[ -d /run/systemd/system ]]; }; then
    init_system="systemd"
  elif command -v rc-service >/dev/null 2>&1 &&
    command -v rc-update >/dev/null 2>&1; then
    [[ -f /etc/alpine-release ]] ||
      die "检测到 OpenRC，但当前自动安装仅支持 Alpine Linux。"
    init_system="openrc"
  else
    die "未检测到受支持的服务管理器；目前支持 systemd 和 OpenRC。"
  fi
  info "检测到服务管理器：${init_system}"
}

select_mode() {
  local choice=""

  if [[ -n "$mode" ]]; then
    case "$mode" in
      reality | xhttp | hybrid) ;;
      *) die "未知安装方案：${mode}（可选 reality、xhttp 或 hybrid）" ;;
    esac
  elif [[ -n "$cdn_mode" || -n "$up_domain" || -n "$down_domain" ]]; then
    mode="xhttp"
  elif [[ -n "$reality_domain" ]]; then
    mode="reality"
  else
    has_tty || die "无法读取交互输入；请使用 --mode 指定安装方案。"
    cat >/dev/tty <<'EOF'

请选择安装方案：
  1. VLESS + REALITY + Vision（Xray 直接监听 443，借用目标站点的 TLS）
  2. VLESS + XHTTP + TLS（Caddy 前置终止 TLS；可上下行分离，也可经过 Cloudflare CDN）
  3. VLESS Encryption + Vision + XHTTP：上行 IPv6 直连，下行 IPv4 经 Cloudflare + ECH
     （需要两个域名和本机公网 IPv6）

EOF
    while [[ -z "$mode" ]]; do
      read -r -p "请输入数字 [1-3]: " choice </dev/tty
      case "$choice" in
        1) mode="reality" ;;
        2) mode="xhttp" ;;
        3) mode="hybrid" ;;
        *) warn "请输入 1、2 或 3。" ;;
      esac
    done
  fi

  if [[ "$mode" == "reality" ]]; then
    [[ -z "$up_domain" && -z "$down_domain" ]] ||
      warn "--up-domain/--down-domain 仅用于 xhttp 方案，已忽略。"
    [[ -z "$cdn_mode" && -z "$cdn_address" && -z "$ech" && -z "$vless_enc" ]] ||
      warn "--cdn/--cdn-address/--ech/--vless-enc 仅用于 xhttp 方案，已忽略。"
    cdn_mode=""
    cdn_address=""
    ech=""
    vless_enc=""
  elif [[ "$mode" == "hybrid" ]]; then
    [[ -z "$reality_domain" ]] || warn "--domain 不用于 hybrid 方案，已忽略。"
    [[ -z "$server_address" ]] || warn "--address 仅用于 reality 方案，已忽略。"
    [[ -z "$cdn_mode" ]] || warn "hybrid 方案固定为下行经过 Cloudflare，--cdn 已忽略。"
    [[ "$ech" != "true" ]] || info "hybrid 方案固定启用 ECH。"
    [[ "$vless_enc" != "off" ]] || warn "hybrid 方案固定启用 VLESS Encryption + Vision，--vless-enc off 已忽略。"
    reality_domain=""
    # hybrid 是固定组合：下行走 CDN + ECH，VLESS 层启用 Encryption + Vision。
    cdn_mode="down"
    ech="true"
    vless_enc="on"
  else
    [[ -z "$server_address" ]] || warn "--address 仅用于 reality 方案，已忽略。"
  fi
  info "安装方案：${mode}"
}

prompt_domain() {
  while [[ -z "$reality_domain" ]]; do
    has_tty || die "无法读取交互输入；请使用 --domain 指定 REALITY 域名。"
    read -r -p "请输入 REALITY 伪装域名（例如 www.example.com）: " reality_domain </dev/tty
    reality_domain="${reality_domain%.}"
    if ! validate_domain "$reality_domain"; then
      warn "域名格式不正确，请不要包含 https://、端口或路径。"
      reality_domain=""
    fi
  done
}

# 用法：prompt_xhttp_domain <变量名> <提示文字> <对应的命令行参数>
prompt_xhttp_domain() {
  local var_name="$1" prompt="$2" flag="$3" value="${!1}"

  while [[ -z "$value" ]]; do
    has_tty || die "无法读取交互输入；请使用 ${flag} 指定域名。"
    read -r -p "$prompt" value </dev/tty
    value="${value%.}"
    if ! validate_domain "$value"; then
      warn "域名格式不正确，请不要包含 https://、端口或路径。"
      value=""
    fi
  done
  printf -v "$var_name" '%s' "${value,,}"
}

# 选择 CDN 方式需要在输入域名之前完成：全程 CDN 只需要一个域名。
prompt_cdn_mode() {
  local choice=""

  if [[ -n "$cdn_mode" ]]; then
    case "$cdn_mode" in
      none | up | full) ;;
      *) die "未知 CDN 方式：${cdn_mode}（可选 none、up 或 full）" ;;
    esac
  elif has_tty; then
    cat >/dev/tty <<'MENU'

请选择 CDN（Cloudflare）方式：
  1. 不走 CDN，上下行两个域名都直连（默认）
  2. 上行走 CDN、下行直连（两个域名）
  3. 全程走 CDN（一个域名，上下行都经过 Cloudflare）

MENU
    while [[ -z "$cdn_mode" ]]; do
      read -r -p "请输入数字 [1-3，默认 1]: " choice </dev/tty
      case "$choice" in
        "" | 1) cdn_mode="none" ;;
        2) cdn_mode="up" ;;
        3) cdn_mode="full" ;;
        *) warn "请输入 1、2 或 3。" ;;
      esac
    done
  else
    cdn_mode="none"
  fi

  if [[ "$cdn_mode" == "none" ]]; then
    [[ -z "$cdn_address" ]] || die "--cdn-address 需要与 --cdn up 或 --cdn full 一起使用。"
    [[ -z "$ech" ]] || die "--ech 需要与 --cdn up 或 --cdn full 一起使用。"
  fi
}

prompt_xhttp_domains() {
  up_domain="${up_domain%.}"
  down_domain="${down_domain%.}"
  reality_domain="${reality_domain%.}"

  if [[ "$cdn_mode" == "full" ]]; then
    if [[ -n "$reality_domain" && -n "$up_domain" && "${reality_domain,,}" != "${up_domain,,}" ]]; then
      die "全程 CDN 只使用一个域名，--domain 与 --up-domain 不能不同。"
    fi
    up_domain="${up_domain:-$reality_domain}"
    [[ -z "$down_domain" ]] || warn "全程 CDN 只使用一个域名，--down-domain 已忽略。"
    down_domain=""
    reality_domain=""
    prompt_xhttp_domain up_domain "请输入经过 Cloudflare 的域名（例如 cdn.example.com）: " --domain
    validate_domain "$up_domain" || die "域名格式不正确。"
    site_domains=("$up_domain")
    return 0
  fi

  [[ -z "$reality_domain" ]] || warn "--domain 仅用于 reality 方案或 --cdn full，已忽略。"
  reality_domain=""
  prompt_xhttp_domain up_domain "请输入上行域名（例如 up.example.com）: " "--up-domain 和 --down-domain"
  validate_domain "$up_domain" || die "上行域名格式不正确。"
  while :; do
    prompt_xhttp_domain down_domain "请输入下行域名（例如 down.example.com）: " "--up-domain 和 --down-domain"
    validate_domain "$down_domain" || die "下行域名格式不正确。"
    [[ "$down_domain" != "$up_domain" ]] && break
    has_tty || die "上行域名与下行域名不能相同。"
    warn "下行域名不能与上行域名相同。"
    down_domain=""
  done
  site_domains=("$up_domain" "$down_domain")
}

# 经过 CDN 的域名：hybrid（down）是下行域名，其余是上行域名。
cdn_domain() {
  if [[ "$cdn_mode" == "down" ]]; then
    printf '%s' "$down_domain"
  else
    printf '%s' "$up_domain"
  fi
}

prompt_cdn_options() {
  local choice="" cdn_dom

  [[ "$cdn_mode" != "none" ]] || return 0
  cdn_dom="$(cdn_domain)"

  if [[ -z "$cdn_address" ]] && has_tty; then
    read -r -p "CDN 链接使用的优选 IP 或域名（直接回车则使用 ${cdn_dom}）: " cdn_address </dev/tty
  fi
  cdn_address="${cdn_address%.}"
  if [[ -n "$cdn_address" ]]; then
    validate_address "$cdn_address" || die "优选地址格式不正确：${cdn_address}"
    if [[ "$cdn_mode" == "down" && "$cdn_address" == *:* ]]; then
      die "hybrid 方案的下行固定经 IPv4 连接 Cloudflare，--cdn-address 不能是 IPv6 地址。"
    fi
  fi

  if [[ -z "$ech" ]]; then
    if has_tty; then
      cat >/dev/tty <<'MENU'

CDN 链接是否启用 ECH？启用后握手中只能看到 cloudflare-ech.com，看不到你的域名；
但客户端必须支持 ECH，否则无法连接。
  1. 否（默认）
  2. 是

MENU
      while [[ -z "$ech" ]]; do
        read -r -p "请输入数字 [1-2，默认 1]: " choice </dev/tty
        case "$choice" in
          "" | 1) ech="false" ;;
          2) ech="true" ;;
          *) warn "请输入 1 或 2。" ;;
        esac
      done
    else
      ech="false"
    fi
  fi
  if [[ "$ech" == "true" ]]; then
    validate_ech_config || die "ECH 配置格式不正确：${ech_config}"
  fi

  case "$cdn_mode" in
    up) info "上行走 CDN、下行直连；CDN 链接地址：${cdn_address:-$cdn_dom}" ;;
    full) info "全程走 CDN；CDN 链接地址：${cdn_address:-$cdn_dom}" ;;
    down) info "上行 IPv6 直连、下行 IPv4 经 CDN；下行连接地址：${cdn_address:-$cdn_dom}" ;;
  esac
  [[ "$ech" != "true" ]] || info "CDN 链接启用 ECH：${ech_config}"
}

# hybrid 的上行固定走 IPv6，没有公网 IPv6 就无法使用。
require_public_ipv6() {
  public_ipv6="$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  [[ "$public_ipv6" == *:* ]] ||
    die "未检测到本机公网 IPv6；hybrid 方案的上行需要 IPv6。请确认服务器已分配公网 IPv6，且 IPv6 出站可用。"
  info "本机公网 IPv6：${public_ipv6}"
}

# 入站同时服务直连和 CDN 链接，启用后所有链接都必须带 encryption 和 flow。
prompt_vless_enc() {
  local choice=""

  case "$vless_enc" in
    on | off) ;;
    "")
      if [[ "$cdn_mode" == "none" ]]; then
        vless_enc="off"
      elif has_tty; then
        cat >/dev/tty <<'MENU'

是否启用 VLESS Encryption + Vision？启用后 Cloudflare 看不到 UUID 和访问目标，
Vision 还能减轻 TLS in TLS 特征；但所有链接都需要较新的 Xray 内核。
  1. 是（推荐，默认）
  2. 否（兼容不支持的客户端）

MENU
        while [[ -z "$vless_enc" ]]; do
          read -r -p "请输入数字 [1-2，默认 1]: " choice </dev/tty
          case "$choice" in
            "" | 1) vless_enc="on" ;;
            2) vless_enc="off" ;;
            *) warn "请输入 1 或 2。" ;;
          esac
        done
      else
        vless_enc="on"
      fi
      ;;
    *) die "--vless-enc 只接受 on 或 off：${vless_enc}" ;;
  esac

  if [[ "$vless_enc" == "on" ]]; then
    vless_flow="$VISION_FLOW"
    info "启用 VLESS Encryption + Vision。"
  else
    vless_flow=""
  fi
}

install_dependencies() {
  if command -v curl >/dev/null 2>&1 &&
    command -v openssl >/dev/null 2>&1 &&
    command -v unzip >/dev/null 2>&1; then
    return 0
  fi

  info "安装基础依赖……"
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache bash curl openssl ca-certificates unzip
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssl ca-certificates unzip
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl openssl ca-certificates unzip
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl openssl ca-certificates unzip
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl openssl ca-certificates unzip
  else
    die "未找到受支持的包管理器，请先安装 bash、curl、openssl、unzip 和 ca-certificates。"
  fi
}

detect_public_address() {
  local detected=""

  detected="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$detected" ]]; then
    detected="$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  fi
  if validate_address "$detected"; then
    server_address="$detected"
    info "探测到服务器公网地址：${server_address}"
    return 0
  fi

  if has_tty; then
    while [[ -z "$server_address" ]]; do
      read -r -p "无法自动探测公网地址，请输入服务器公网 IP 或域名: " server_address </dev/tty
      if ! validate_address "$server_address"; then
        warn "服务器地址格式不正确。"
        server_address=""
      fi
    done
  else
    die "无法自动探测公网地址；非交互运行时请使用 --address 指定。"
  fi
}

# 仅提醒，不中断：域名可能经 CDN 或尚在 DNS 生效中。
check_domain_dns() {
  local domain resolved ip4 ip6 is_local cdn_dom

  if ! command -v getent >/dev/null 2>&1; then
    warn "未找到 getent，跳过域名解析检查；请确认域名都已解析到本机。"
    return 0
  fi
  ip4="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  ip6="$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  cdn_dom="$(cdn_domain)"

  for domain in "${site_domains[@]}"; do
    # musl 的 getent 可能不支持 ahosts，失败时退回 hosts。
    resolved="$({ getent ahosts "$domain" || getent hosts "$domain"; } 2>/dev/null |
      awk '{print $1}' | sort -u || true)"
    if [[ -z "$resolved" ]]; then
      warn "无法解析 ${domain}；Caddy 将无法为其申请证书，请先添加 DNS 记录。"
      continue
    fi
    is_local="false"
    if { [[ -n "$ip4" ]] && grep -qxF "$ip4" <<<"$resolved"; } ||
      { [[ -n "$ip6" ]] && grep -qxF "$ip6" <<<"$resolved"; }; then
      is_local="true"
    fi

    if [[ "$cdn_mode" != "none" && "$domain" == "$cdn_dom" ]]; then
      if [[ "$is_local" == "true" ]]; then
        info "${domain} 当前直连本机（灰云），适合首次签发证书；安装完成后再切换为橙云。"
      else
        warn "${domain} 当前未解析到本机（可能已开橙云）；若 Caddy 尚未为它签发过证书，首次签发可能失败，建议先切回灰云再运行。"
      fi
    elif [[ "$is_local" == "true" ]]; then
      info "${domain} 已解析到本机。"
    elif [[ "$cdn_mode" == "up" || "$cdn_mode" == "down" ]]; then
      warn "${domain} 是直连的域名，但解析结果（$(tr '\n' ' ' <<<"$resolved")）不包含本机公网地址（${ip4:-无 IPv4} ${ip6:-无 IPv6}）；请确认它保持灰云并指向本机。"
    else
      warn "${domain} 的解析结果（$(tr '\n' ' ' <<<"$resolved")）不包含本机公网地址（${ip4:-无 IPv4} ${ip6:-无 IPv6}）；若未使用 CDN，证书申请会失败。"
    fi

    [[ "$mode" == "hybrid" ]] || continue
    if [[ "$domain" == "$up_domain" ]]; then
      if grep -qv ':' <<<"$resolved"; then
        warn "${domain} 存在 A 记录；hybrid 方案的上行域名应当只配 AAAA，否则上行可能改走 IPv4。"
      fi
      if [[ -z "$ip6" ]] || ! grep -qxF "$ip6" <<<"$resolved"; then
        warn "${domain} 没有解析到本机公网 IPv6（${ip6:-未检测到}）；上行将无法直连。"
      fi
    elif [[ -n "$ip6" ]] && grep -qxF "$ip6" <<<"$resolved"; then
      warn "${domain} 存在指向本机的 AAAA 记录；hybrid 方案的下行域名应当只配 A，让 Cloudflare 经 IPv4 回源。"
    fi
  done
}

confirm_overwrite() {
  local existing_configs=()

  if [[ -d "$CONFIG_DIR" ]]; then
    shopt -s nullglob
    existing_configs=("${CONFIG_DIR}"/*.json)
    shopt -u nullglob
  fi
  ((${#existing_configs[@]} > 0)) || return 0
  [[ "$force" == "true" ]] && return 0

  if ! has_tty; then
    die "已存在 Xray 配置；如需覆盖，请添加 --force。"
  fi

  local answer=""
  warn "检测到已有 Xray 配置。继续会直接覆盖且不保留备份，并生成新凭据；旧导入链接将失效。"
  read -r -p "确认直接覆盖吗？[y/N] " answer </dev/tty
  [[ "$answer" =~ ^[Yy]$ ]] || die "已取消。"
}

confirm_caddy_overwrite() {
  [[ -s "$CADDY_FILE" ]] || return 0
  grep -qF "$CADDY_MARK" "$CADDY_FILE" && return 0
  [[ "$force" == "true" ]] && return 0

  if ! has_tty; then
    die "已存在 ${CADDY_FILE}；如需覆盖，请添加 --force。"
  fi

  local answer=""
  warn "检测到已有 Caddy 配置 ${CADDY_FILE}。继续会直接覆盖且不保留备份，其中原有站点将失效。"
  read -r -p "确认直接覆盖吗？[y/N] " answer </dev/tty
  [[ "$answer" =~ ^[Yy]$ ]] || die "已取消。"
}

# 用法：check_port <端口> <允许占用的进程名>...
check_port() {
  local port="$1"
  shift
  local listeners line proc allowed

  command -v ss >/dev/null 2>&1 || return 0
  listeners="$(ss -H -ltnp "sport = :${port}" 2>/dev/null || true)"
  [[ -z "$listeners" ]] && return 0

  while IFS= read -r line; do
    allowed="false"
    for proc in "$@"; do
      if [[ "$line" == *"\"${proc}\""* ]]; then
        allowed="true"
        break
      fi
    done
    [[ "$allowed" == "true" ]] ||
      die "TCP ${port} 已被其他程序占用，请先释放该端口：${line}"
  done <<<"$listeners"
  info "TCP ${port} 当前由本脚本管理的服务占用，将更新配置。"
}

check_ports() {
  local listeners=""

  if [[ "$mode" == "reality" ]]; then
    if command -v ss >/dev/null 2>&1; then
      listeners="$(ss -H -ltnp "sport = :${PORT}" 2>/dev/null || true)"
      if [[ "$listeners" == *'"caddy"'* ]]; then
        if [[ "$init_system" == "systemd" ]]; then
          die "TCP ${PORT} 被 Caddy 占用（可能来自之前安装的 XHTTP 方案）。如不再需要，请先执行：systemctl disable --now caddy"
        else
          die "TCP ${PORT} 被 Caddy 占用（可能来自之前安装的 XHTTP 方案）。如不再需要，请先执行：rc-service caddy stop && rc-update del caddy default"
        fi
      fi
    fi
    check_port "$PORT" xray
  else
    check_port "$PORT" xray caddy
    check_port 80 caddy
    check_port "$XHTTP_LOCAL_PORT" xray
  fi
}

install_xray() {
  local installer_url="$XRAY_INSTALL_URL_SYSTEMD"

  [[ "$init_system" == "systemd" ]] || installer_url="$XRAY_INSTALL_URL_OPENRC"
  # BusyBox mktemp（Alpine）要求 XXXXXX 位于模板末尾。
  installer_tmp="$(mktemp /tmp/xray-install.XXXXXX)"
  info "下载并运行适用于 ${init_system} 的 XTLS 官方 Xray 安装脚本……"
  curl -fL --retry 3 --connect-timeout 10 -o "$installer_tmp" "$installer_url"
  if [[ "$init_system" == "systemd" ]]; then
    bash "$installer_tmp" install
  else
    ash "$installer_tmp"
  fi
  [[ -x "$XRAY_BIN" ]] || die "Xray 安装失败：未找到 ${XRAY_BIN}。"
}

install_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    info "检测到已安装 Caddy：$(caddy version 2>/dev/null | head -n 1)"
    return 0
  fi

  info "安装 Caddy……"
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache caddy caddy-openrc
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg ca-certificates curl
    curl -fsSL --retry 3 "$CADDY_APT_KEY_URL" | gpg --dearmor --yes -o "$CADDY_APT_KEYRING"
    curl -fsSL --retry 3 -o /etc/apt/sources.list.d/caddy-stable.list "$CADDY_APT_LIST_URL"
    chmod 0644 "$CADDY_APT_KEYRING" /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
  elif command -v dnf >/dev/null 2>&1; then
    if ! dnf copr --help >/dev/null 2>&1; then
      dnf install -y 'dnf-command(copr)' || dnf install -y dnf5-plugins
    fi
    dnf copr enable -y @caddy/caddy
    dnf install -y caddy
  elif command -v yum >/dev/null 2>&1; then
    yum install -y yum-plugin-copr
    yum copr enable -y @caddy/caddy
    yum install -y caddy
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install caddy
  else
    die "未找到受支持的包管理器，请先手动安装 Caddy。"
  fi
  command -v caddy >/dev/null 2>&1 || die "Caddy 安装失败：未找到 caddy 命令。"
}

download_geodata() {
  asset_tmp_dir="$(mktemp -d /tmp/xray-geodata.XXXXXX)"
  info "下载 Loyalsoldier 路由数据……"
  curl -fL --retry 3 --connect-timeout 10 -o "${asset_tmp_dir}/geoip.dat" "$GEOIP_URL"
  curl -fL --retry 3 --connect-timeout 10 -o "${asset_tmp_dir}/geosite.dat" "$GEOSITE_URL"
  [[ -s "${asset_tmp_dir}/geoip.dat" && -s "${asset_tmp_dir}/geosite.dat" ]] ||
    die "路由数据下载不完整。"

  install -d -m 0755 "$ASSET_DIR"
  install -m 0644 "${asset_tmp_dir}/geoip.dat" "${ASSET_DIR}/geoip.dat"
  install -m 0644 "${asset_tmp_dir}/geosite.dat" "${ASSET_DIR}/geosite.dat"
}

generate_credentials() {
  local key_output

  uuid="$("$XRAY_BIN" uuid | tr -d '\r\n')"
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || die "UUID 生成失败。"

  if [[ "$mode" == "reality" ]]; then
    key_output="$("$XRAY_BIN" x25519)"
    private_key="$(awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' <<<"$key_output")"
    public_key="$(awk -F': *' 'tolower($1) ~ /(password|public)/ {print $2; exit}' <<<"$key_output")"
    short_id="$(openssl rand -hex 8)"

    [[ -n "$private_key" && -n "$public_key" ]] || die "REALITY X25519 密钥生成失败。"
    [[ "$short_id" =~ ^[0-9a-f]{16}$ ]] || die "Short ID 生成失败。"
  else
    xhttp_path="/$(openssl rand -hex 8)"
    [[ "$xhttp_path" =~ ^/[0-9a-f]{16}$ ]] || die "XHTTP 路径生成失败。"
  fi

  if [[ "$vless_enc" == "on" ]]; then
    key_output="$("$XRAY_BIN" vlessenc)"
    # 取 X25519 认证的一对，导入链接更短；临时密钥交换本身已是后量子安全的。
    # xorpub 让经过 CDN 的数据没有固定结构。
    vless_decryption="$(awk '/X25519/ {f = 1} f && /"decryption"/ {print; exit}' <<<"$key_output" | cut -d'"' -f4)"
    vless_encryption="$(awk '/X25519/ {f = 1} f && /"encryption"/ {print; exit}' <<<"$key_output" | cut -d'"' -f4)"
    vless_decryption="${vless_decryption/.native./.xorpub.}"
    vless_encryption="${vless_encryption/.native./.xorpub.}"
    [[ "$vless_decryption" == mlkem768x25519plus.xorpub.* &&
      "$vless_encryption" == mlkem768x25519plus.xorpub.* ]] || die "VLESS Encryption 密钥生成失败。"
  fi
}

reality_inbounds_json() {
  cat <<EOF
    {
      "tag": "reality-fallback",
      "listen": "127.0.0.1",
      "port": 4431,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "${reality_domain}",
        "port": 443,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "vless-in",
      "listen": "::",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "127.0.0.1:4431",
          "xver": 0,
          "serverNames": [
            "${reality_domain}"
          ],
          "privateKey": "${private_key}",
          "shortIds": [
            "${short_id}"
          ]
        }
      }
    }
EOF
}

reality_routing_rules_json() {
  cat <<EOF
      {
        "type": "field",
        "inboundTag": [
          "reality-fallback"
        ],
        "domain": [
          "full:${reality_domain}"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": [
          "reality-fallback"
        ],
        "outboundTag": "block"
      },
EOF
}

xhttp_inbounds_json() {
  local flow_line=""

  [[ -z "$vless_flow" ]] || flow_line=",
            \"flow\": \"${vless_flow}\""
  cat <<EOF
    {
      "tag": "xhttp-in",
      "listen": "127.0.0.1",
      "port": ${XHTTP_LOCAL_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"${flow_line}
          }
        ],
        "decryption": "${vless_decryption}"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${xhttp_path}",
          "mode": "auto"
        }
      }
    }
EOF
}

write_config() {
  local old_json inbounds mode_rules=""
  local -a old_configs=()

  if [[ "$mode" == "reality" ]]; then
    inbounds="$(reality_inbounds_json)"
    # 自带开头的换行，没有额外规则时 "rules": [ 后面不会多出空行。
    mode_rules=$'\n'"$(reality_routing_rules_json)"
  else
    inbounds="$(xhttp_inbounds_json)"
  fi

  install -d -m 0755 "$CONFIG_DIR"
  # BusyBox mktemp 要求 XXXXXX 位于末尾，而 Xray 又依赖 .json 扩展名识别格式。
  config_tmp_dir="$(mktemp -d /tmp/xray-config.XXXXXX)"
  config_tmp="${config_tmp_dir}/config.json"
  cat >"$config_tmp" <<EOF
{
  "log": {
    "loglevel": "info"
  },
  "geodata": {
    "cron": "30 4 * * 1",
    "outbound": "direct",
    "assets": [
      {
        "url": "${GEOIP_URL}",
        "file": "geoip.dat"
      },
      {
        "url": "${GEOSITE_URL}",
        "file": "geosite.dat"
      }
    ]
  },
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [${mode_rules}
      {
        "type": "field",
        "domain": [
          "geosite:google",
          "geosite:google-cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

  info "校验 Xray 配置……"
  "$XRAY_BIN" run -test -config "$config_tmp"

  if [[ "$init_system" == "openrc" ]]; then
    shopt -s nullglob
    old_configs=("${CONFIG_DIR}"/*.json)
    shopt -u nullglob
    for old_json in "${old_configs[@]}"; do
      rm -f -- "$old_json"
    done
  fi
  install -m 0644 "$config_tmp" "$CONFIG_FILE"
}

# 伪装站点留空，由用户（或 agent，见 skills/vless-deploy）自行填充；
# 已存在的目录及其内容保持不动。
prepare_site_dirs() {
  local domain dir

  [[ -d "$SITE_ROOT" ]] || install -d -m 0755 "$SITE_ROOT"
  for domain in "${site_domains[@]}"; do
    dir="${SITE_ROOT}/${domain}"
    if [[ -d "$dir" ]]; then
      info "伪装站点目录已存在，保持原样：${dir}"
    else
      install -d -m 0755 "$dir"
      info "已创建空的伪装站点目录：${dir}"
    fi
  done
}

write_caddy_config() {
  local caddy_tmp validate_output domain

  install -d -m 0755 "$(dirname "$CADDY_FILE")"
  caddy_tmp_dir="$(mktemp -d /tmp/caddy-config.XXXXXX)"
  caddy_tmp="${caddy_tmp_dir}/Caddyfile"
  {
    cat <<EOF
${CADDY_MARK}; rerunning the installer overwrites this file.
(xhttp_proxy) {
handle ${xhttp_path}* {
reverse_proxy 127.0.0.1:${XHTTP_LOCAL_PORT} {
flush_interval -1
transport http {
versions h2c
}
}
}
}
EOF
    for domain in "${site_domains[@]}"; do
      cat <<EOF

${domain} {
import xhttp_proxy
handle {
root * ${SITE_ROOT}/${domain}
file_server
}
}
EOF
    done
  } >"$caddy_tmp"
  caddy fmt --overwrite "$caddy_tmp" >/dev/null 2>&1 || true

  info "校验 Caddy 配置……"
  if ! validate_output="$(caddy validate --config "$caddy_tmp" --adapter caddyfile 2>&1)"; then
    printf '%s\n' "$validate_output" >&2
    die "Caddy 配置校验失败。"
  fi
  install -m 0644 "$caddy_tmp" "$CADDY_FILE"
}

allow_geodata_updates() {
  local service_user service_group

  if [[ "$init_system" == "systemd" ]]; then
    service_user="$(systemctl show xray.service -p User --value 2>/dev/null || true)"
    [[ -n "$service_user" ]] || service_user="root"
  else
    service_user="nobody"
  fi
  if id "$service_user" >/dev/null 2>&1; then
    service_group="$(id -gn "$service_user")"
    chown "root:${service_group}" "$CONFIG_FILE"
    chmod 0640 "$CONFIG_FILE"
    chown -R "${service_user}:${service_group}" "$ASSET_DIR"
    chmod 0755 "$ASSET_DIR"
    chmod 0644 "${ASSET_DIR}/geoip.dat" "${ASSET_DIR}/geosite.dat"
  else
    warn "无法识别 Xray 服务用户，定时更新 geodata 时可能没有写权限。"
  fi
}

# 用法：open_firewall_ports <端口/协议>...
open_firewall_ports() {
  local rule

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    for rule in "$@"; do
      ufw allow "$rule" >/dev/null
    done
    info "已在 UFW 放行：$*"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for rule in "$@"; do
      firewall-cmd --permanent --add-port="$rule" >/dev/null
      firewall-cmd --add-port="$rule" >/dev/null
    done
    info "已在 firewalld 放行：$*"
  else
    warn "未检测到启用中的 UFW/firewalld；请确认云安全组和系统防火墙已放行：$*"
  fi
}

# 用法：start_service <服务名>
start_service() {
  local name="$1"

  if [[ "$init_system" == "systemd" ]]; then
    systemctl daemon-reload
    systemctl enable "${name}.service" >/dev/null
    if ! systemctl restart "${name}.service"; then
      journalctl -u "${name}.service" -n 30 --no-pager >&2 || true
      die "${name} 启动失败，请根据上方日志排查。"
    fi
    systemctl is-active --quiet "${name}.service" || die "${name} 服务未处于运行状态。"
  else
    rc-update add "$name" default >/dev/null
    if rc-service "$name" status >/dev/null 2>&1; then
      rc-service "$name" restart || die "${name} 重启失败，请运行 rc-service ${name} status 排查。"
    else
      rc-service "$name" start || die "${name} 启动失败，请运行 rc-service ${name} status 排查。"
    fi
    rc-service "$name" status >/dev/null 2>&1 || die "${name} 服务未处于运行状态。"
  fi
}

# 首次申请证书可能需要数十秒，这里只提醒、不中断。
# 伪装站点可能还是空目录（返回 404），所以只要求 TLS 握手成功并拿到 HTTP 响应。
verify_https() {
  local domain i ok code

  for domain in "${site_domains[@]}"; do
    ok="false"
    info "等待 ${domain} 的证书就绪……"
    for ((i = 0; i < 18; i++)); do
      code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
        --resolve "${domain}:${PORT}:127.0.0.1" "https://${domain}/" 2>/dev/null || true)"
      if [[ -n "$code" && "$code" != "000" ]]; then
        ok="true"
        break
      fi
      sleep 5
    done
    if [[ "$ok" == "true" ]]; then
      info "${domain} 的 HTTPS 已可用。"
    elif [[ "$init_system" == "systemd" ]]; then
      warn "${domain} 的 HTTPS 暂不可用；请检查 DNS 解析、80/443 入站，并查看 journalctl -u caddy -n 50。"
    else
      warn "${domain} 的 HTTPS 暂不可用；请检查 DNS 解析、80/443 入站，并运行 rc-service caddy status 排查。"
    fi
  done
}

print_status_hint() {
  if [[ "$init_system" == "systemd" ]]; then
    printf '查看状态：systemctl status %s --no-pager\n' "$*"
  else
    printf '查看状态：rc-service %s status\n' "$1"
  fi
}

print_reality_result() {
  local uri_host="$server_address"
  local import_link

  [[ "$uri_host" == *:* ]] && uri_host="[${uri_host}]"
  import_link="vless://${uuid}@${uri_host}:${PORT}?encryption=none&security=reality&sni=${reality_domain}&fp=${fingerprint}&pbk=${public_key}&sid=${short_id}&type=tcp&flow=xtls-rprx-vision#Xray-REALITY"

  printf '\n\033[1;32m安装完成，Xray 正在运行。\033[0m\n\n'
  printf '服务器地址：%s\n' "$server_address"
  printf '端口：%s\n' "$PORT"
  printf 'UUID：%s\n' "$uuid"
  printf 'REALITY 公钥：%s\n' "$public_key"
  printf 'Short ID：%s\n' "$short_id"
  printf 'SNI：%s\n' "$reality_domain"
  printf '客户端指纹：%s\n\n' "$fingerprint"
  printf '客户端导入链接：\n%s\n\n' "$import_link"
  printf '服务端配置：%s\n' "$CONFIG_FILE"
  print_status_hint xray
}

# 用法：download_extra_json <split|split-cdn>
# split：下行直连下行域名；split-cdn：下行经 CDN 连接下行域名（hybrid），带 Host、可选 ECH，
# 并固定用 IPv4 连接 Cloudflare。
download_extra_json() {
  local address="$down_domain" tls_extra="" xhttp_extra="" sockopt=""

  if [[ "$1" == "split-cdn" ]]; then
    address="${cdn_address:-$down_domain}"
    [[ "$ech" != "true" ]] || tls_extra=",\"echConfigList\":\"${ech_config}\""
    xhttp_extra=",\"host\":\"${down_domain}\""
    sockopt=",\"sockopt\":{\"domainStrategy\":\"UseIPv4\"}"
  fi
  # 显式写出指纹：Xray 系客户端留空时默认 chrome，mihomo 留空时却是原生 Go TLS。
  printf '{"downloadSettings":{"address":"%s","port":%s,"network":"xhttp","security":"tls","tlsSettings":{"serverName":"%s","alpn":["h2"],"fingerprint":"%s"%s},"xhttpSettings":{"path":"%s"%s}%s}}' \
    "$address" "$PORT" "$down_domain" "$fingerprint" "$tls_extra" "$xhttp_path" "$xhttp_extra" "$sockopt"
}

# 用法：xhttp_link <连接地址> <XHTTP 模式> <备注> <split|split-cdn|single> [额外查询参数]
# split / split-cdn 通过 extra.downloadSettings 让下行改走下行域名；single 上下行都走上行域名。
xhttp_link() {
  local address="$1" link_mode="$2" name="$3" layout="$4" extra_query="${5:-}"
  local extra_param="" flow_param=""

  [[ "$address" == *:* ]] && address="[${address}]"
  case "$layout" in
    split | split-cdn) extra_param="&extra=$(urlencode "$(download_extra_json "$layout")")" ;;
  esac
  [[ -z "$vless_flow" ]] || flow_param="&flow=${vless_flow}"
  printf 'vless://%s@%s:%s?encryption=%s%s&security=tls&sni=%s%s&alpn=h2&fp=%s&type=xhttp&path=%s&mode=%s%s#%s' \
    "$uuid" "$address" "$PORT" "$(urlencode "$vless_encryption")" "$flow_param" "$up_domain" \
    "$extra_query" "$fingerprint" "$(urlencode "$xhttp_path")" "$link_mode" "$extra_param" "$name"
}

# 上行经过 CDN 的链接的额外查询参数：Host 头，以及可选的 ECH。
cdn_query() {
  local query="&host=${up_domain}"

  if [[ "$ech" == "true" ]]; then
    query+="&ech=$(urlencode "$ech_config")"
  fi
  printf '%s' "$query"
}

print_cdn_checklist() {
  local cdn_dom i
  cdn_dom="$(cdn_domain)"
  local -a steps=(
    "SSL/TLS 加密模式：Full (strict)（不要用 Flexible，否则会无限重定向）"
    "关闭 Always Use HTTPS（让证书续期的验证请求能到达源站 80 端口）"
    "关闭 Bot Fight Mode，或为路径 ${xhttp_path}* 添加 WAF 跳过规则"
  )

  if [[ "$ech" == "true" ]]; then
    steps+=("确认 SSL/TLS → 边缘证书 中的 Encrypted ClientHello (ECH) 为开启状态（免费套餐默认开启）")
  fi
  case "$cdn_mode" in
    up) steps+=("可选：开启 gRPC 后，可把上行 CDN 链接中的 mode=packet-up 改为 mode=stream-up") ;;
    full) steps+=("可选：开启 gRPC 后，可尝试把链接中的 mode=packet-up 改为 mode=stream-one，减少请求数") ;;
    down) steps+=("${cdn_dom} 只保留 A 记录，不要添加 AAAA（让 Cloudflare 经 IPv4 回源）") ;;
  esac
  steps+=("最后把 ${cdn_dom} 切换为橙云（代理）")

  printf '接下来请在 Cloudflare 后台为 %s 完成：\n' "$cdn_dom"
  for i in "${!steps[@]}"; do
    printf '  %d. %s\n' "$((i + 1))" "${steps[i]}"
  done
  printf '  验证：curl -sI https://%s/ 的响应头中应包含 cf-ray\n' "$cdn_dom"
  if [[ "$ech" == "true" ]]; then
    printf '  注意：ECH 由 Cloudflare 终止，切换为橙云之前带 ECH 的链接无法连通。\n'
  fi
  case "$cdn_mode" in
    up) printf '  注意：%s 必须保持灰云（仅 DNS）并直连本机。\n' "$down_domain" ;;
    down) printf '  注意：%s 必须保持灰云（仅 DNS），并且只配指向本机的 AAAA 记录。\n' "$up_domain" ;;
  esac
  printf '  注意：经过 CDN 的流量都由 Cloudflare 转发，免费套餐晚高峰可能较慢，大流量使用也可能违反其服务条款。\n'
}

print_xhttp_result() {
  local direct_link cdn_link full_link main_link cdn_host="${cdn_address:-$up_domain}" site_dirs="" domain

  for domain in "${site_domains[@]}"; do
    site_dirs+="${site_dirs:+、}${SITE_ROOT}/${domain}"
  done

  printf '\n\033[1;32m安装完成，Xray 与 Caddy 正在运行。\033[0m\n\n'
  if [[ "$cdn_mode" == "full" ]]; then
    printf '域名：%s（上下行都经过 Cloudflare）\n' "$up_domain"
  elif [[ "$cdn_mode" == "down" ]]; then
    printf '上行域名：%s（IPv6 直连）\n' "$up_domain"
    printf '下行域名：%s（IPv4 经 Cloudflare）\n' "$down_domain"
  else
    printf '上行域名：%s\n' "$up_domain"
    printf '下行域名：%s\n' "$down_domain"
  fi
  printf '端口：%s\n' "$PORT"
  printf 'UUID：%s\n' "$uuid"
  printf 'XHTTP 路径：%s\n' "$xhttp_path"
  printf '客户端指纹：%s\n' "$fingerprint"
  if [[ "$vless_encryption" != "none" ]]; then
    printf 'VLESS Encryption（客户端）：%s\n' "$vless_encryption"
    printf 'Flow：%s\n' "$vless_flow"
  fi
  [[ "$ech" != "true" ]] || printf 'ECH（仅 CDN 连接）：%s\n' "$ech_config"

  case "$cdn_mode" in
    none)
      direct_link="$(xhttp_link "$up_domain" stream-up Xray-XHTTP split)"
      printf '传输模式：stream-up（上下行分离）\n\n'
      printf '客户端导入链接：\n%s\n\n' "$direct_link"
      ;;
    up)
      direct_link="$(xhttp_link "$up_domain" stream-up Xray-XHTTP split)"
      cdn_link="$(xhttp_link "$cdn_host" packet-up Xray-XHTTP-CDN split "$(cdn_query)")"
      full_link="$(xhttp_link "$cdn_host" packet-up Xray-XHTTP-CDN-Full single "$(cdn_query)")"
      printf '传输模式：直连链接 stream-up；CDN 链接 packet-up\n\n'
      printf '直连链接（现在即可使用；CDN 出问题时也可作为备用）：\n%s\n\n' "$direct_link"
      printf '上行 CDN 链接（将 %s 切换为橙云后日常使用；下行仍直连）：\n%s\n\n' "$up_domain" "$cdn_link"
      printf '全程 CDN 应急链接（本机 IP 被封、直连不通时使用；所有流量经过 Cloudflare）：\n%s\n\n' "$full_link"
      print_cdn_checklist
      printf '\n'
      ;;
    full)
      full_link="$(xhttp_link "$cdn_host" packet-up Xray-XHTTP-CDN single "$(cdn_query)")"
      printf '传输模式：packet-up（上下行都经过 Cloudflare）\n\n'
      if [[ "$ech" == "true" || -n "$cdn_address" ]]; then
        printf '客户端导入链接（将 %s 切换为橙云后使用）：\n%s\n\n' "$up_domain" "$full_link"
      else
        printf '客户端导入链接（灰云时直连本机，可先测试；切换为橙云后改为经过 Cloudflare）：\n%s\n\n' "$full_link"
      fi
      print_cdn_checklist
      printf '\n'
      ;;
    down)
      main_link="$(xhttp_link "$up_domain" stream-up Xray-Hybrid split-cdn)"
      direct_link="$(xhttp_link "$up_domain" stream-up Xray-Hybrid-Test split)"
      printf '传输模式：上行 stream-up；下行 GET 流\n\n'
      printf '主链接（将 %s 切换为橙云后使用）：\n%s\n\n' "$down_domain" "$main_link"
      printf '测试链接（下行不带 ECH；切换橙云前上下行都直连本机，用于确认服务端正常）：\n%s\n\n' "$direct_link"
      print_cdn_checklist
      printf '  客户端要求：较新的 Xray 内核（需支持 VLESS Encryption、XHTTP 上的 Vision、ECH 和 downloadSettings）；\n'
      printf '  客户端所在网络需同时有 IPv4 和 IPv6。\n\n'
      ;;
  esac
  if [[ "$mode" == "xhttp" && "$vless_enc" == "on" ]]; then
    printf '客户端要求：所有链接都启用了 VLESS Encryption + Vision，需要较新的 Xray 内核。\n\n'
  fi
  printf 'Xray 配置：%s\n' "$CONFIG_FILE"
  printf 'Caddy 配置：%s\n' "$CADDY_FILE"
  printf '伪装站点目录：%s\n' "$site_dirs"
  print_status_hint xray caddy
  printf '\n'
  if ((${#site_domains[@]} > 1)); then
    warn "伪装站点目录为空时首页返回 404；请为两个域名分别放入不同的静态站点（可用 skills/vless-deploy 让 agent 生成）。"
  else
    warn "伪装站点目录为空时首页返回 404；请放入一个静态站点（可用 skills/vless-deploy 让 agent 生成）。"
  fi
}

main() {
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 权限运行，例如：sudo bash install.sh"
  [[ "$(uname -s)" == "Linux" ]] || die "本脚本仅支持 Linux。"

  detect_init_system
  select_mode
  validate_fingerprint
  if [[ "$mode" == "reality" ]]; then
    prompt_domain
    validate_domain "$reality_domain" || die "REALITY 域名格式不正确。"
    [[ -z "$server_address" ]] || validate_address "$server_address" ||
      die "服务器地址格式不正确。"
  else
    [[ "$mode" == "hybrid" ]] || prompt_cdn_mode
    prompt_xhttp_domains
    prompt_cdn_options
    prompt_vless_enc
  fi
  check_ports
  confirm_overwrite
  [[ "$mode" == "reality" ]] || confirm_caddy_overwrite
  install_dependencies
  if [[ "$mode" == "reality" ]]; then
    [[ -n "$server_address" ]] || detect_public_address
  else
    [[ "$mode" != "hybrid" ]] || require_public_ipv6
    check_domain_dns
  fi
  install_xray
  [[ "$mode" == "reality" ]] || install_caddy
  download_geodata
  generate_credentials
  write_config
  allow_geodata_updates
  if [[ "$mode" == "reality" ]]; then
    open_firewall_ports "${PORT}/tcp"
  else
    prepare_site_dirs
    write_caddy_config
    open_firewall_ports 80/tcp "${PORT}/tcp" "${PORT}/udp"
  fi
  # XHTTP 方案中 Xray 先改为只监听本地端口，释放 443 后再启动 Caddy。
  start_service xray

  if [[ "$mode" == "reality" ]]; then
    if ! "$XRAY_BIN" tls ping "${reality_domain}:443" >/dev/null 2>&1; then
      warn "Xray 未能确认伪装站点的 TLS 可用性；节点可能仍能启动，但建议更换支持 TLS 1.3 的目标域名。"
    fi
    print_reality_result
  else
    start_service caddy
    verify_https
    print_xhttp_result
  fi
}

main
