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
readonly FINGERPRINTS="chrome firefox safari ios android edge 360 qq random randomized randomizednoalpn unsafe"

mode=""
reality_domain=""
up_domain=""
down_domain=""
server_address=""
fingerprint="chrome"
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
  sudo bash install.sh --mode xhttp --up-domain up.example.com --down-domain down.example.com [--force]

参数：
  -m, --mode         安装方案：reality（VLESS + REALITY + Vision）或
                     xhttp（VLESS + XHTTP + TLS，Caddy 前置，上下行分离）
  -d, --domain       REALITY 伪装站点域名（不要带协议、端口或路径）
  -a, --address      REALITY 模式下客户端连接的服务器公网 IP 或域名；默认自动探测
      --up-domain    XHTTP 模式的上行域名（需解析到本机）
      --down-domain  XHTTP 模式的下行域名（需解析到本机，且与上行域名不同）
      --fingerprint  写入导入链接的客户端 TLS 指纹，默认 chrome；可选 chrome、firefox、
                     safari、ios、android、edge、360、qq、random、randomized、
                     randomizednoalpn，以及仅 xhttp 方案可用的 unsafe（原生 Go TLS）
  -f, --force        无交互覆盖已有 Xray / Caddy 配置
  -h, --help         显示帮助

未指定 --mode 时：给出 --domain 视为 reality，给出 --up-domain/--down-domain
视为 xhttp，否则在终端中显示菜单供选择。
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
      reality | xhttp) ;;
      *) die "未知安装方案：${mode}（可选 reality 或 xhttp）" ;;
    esac
  elif [[ -n "$reality_domain" ]]; then
    mode="reality"
  elif [[ -n "$up_domain" || -n "$down_domain" ]]; then
    mode="xhttp"
  else
    has_tty || die "无法读取交互输入；请使用 --mode 指定安装方案。"
    cat >/dev/tty <<'EOF'

请选择安装方案：
  1. VLESS + REALITY + Vision（Xray 直接监听 443，借用目标站点的 TLS）
  2. VLESS + XHTTP + TLS（Caddy 前置终止 TLS，上下行分离，需要两个解析到本机的域名）

EOF
    while [[ -z "$mode" ]]; do
      read -r -p "请输入数字 [1-2]: " choice </dev/tty
      case "$choice" in
        1) mode="reality" ;;
        2) mode="xhttp" ;;
        *) warn "请输入 1 或 2。" ;;
      esac
    done
  fi

  if [[ "$mode" == "reality" ]]; then
    [[ -z "$up_domain" && -z "$down_domain" ]] ||
      warn "--up-domain/--down-domain 仅用于 xhttp 方案，已忽略。"
  else
    [[ -z "$reality_domain" ]] || warn "--domain 仅用于 reality 方案，已忽略。"
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

# 用法：prompt_xhttp_domain <变量名> <提示文字>
prompt_xhttp_domain() {
  local var_name="$1" prompt="$2" value="${!1}"

  while [[ -z "$value" ]]; do
    has_tty || die "无法读取交互输入；请使用 --up-domain 和 --down-domain 指定域名。"
    read -r -p "$prompt" value </dev/tty
    value="${value%.}"
    if ! validate_domain "$value"; then
      warn "域名格式不正确，请不要包含 https://、端口或路径。"
      value=""
    fi
  done
  printf -v "$var_name" '%s' "${value,,}"
}

prompt_xhttp_domains() {
  up_domain="${up_domain%.}"
  down_domain="${down_domain%.}"
  prompt_xhttp_domain up_domain "请输入上行域名（例如 up.example.com）: "
  validate_domain "$up_domain" || die "上行域名格式不正确。"
  while :; do
    prompt_xhttp_domain down_domain "请输入下行域名（例如 down.example.com）: "
    validate_domain "$down_domain" || die "下行域名格式不正确。"
    [[ "$down_domain" != "$up_domain" ]] && break
    has_tty || die "上行域名与下行域名不能相同。"
    warn "下行域名不能与上行域名相同。"
    down_domain=""
  done
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
  local domain resolved ip4 ip6

  if ! command -v getent >/dev/null 2>&1; then
    warn "未找到 getent，跳过域名解析检查；请确认两个域名都已解析到本机。"
    return 0
  fi
  ip4="$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  ip6="$(curl -6fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"

  for domain in "$up_domain" "$down_domain"; do
    # musl 的 getent 可能不支持 ahosts，失败时退回 hosts。
    resolved="$({ getent ahosts "$domain" || getent hosts "$domain"; } 2>/dev/null |
      awk '{print $1}' | sort -u || true)"
    if [[ -z "$resolved" ]]; then
      warn "无法解析 ${domain}；Caddy 将无法为其申请证书，请先添加 DNS 记录。"
    elif { [[ -n "$ip4" ]] && grep -qxF "$ip4" <<<"$resolved"; } ||
      { [[ -n "$ip6" ]] && grep -qxF "$ip6" <<<"$resolved"; }; then
      info "${domain} 已解析到本机。"
    else
      warn "${domain} 的解析结果（$(tr '\n' ' ' <<<"$resolved")）不包含本机公网地址（${ip4:-无 IPv4} ${ip6:-无 IPv6}）；若未使用 CDN，证书申请会失败。"
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
  cat <<EOF
    {
      "tag": "xhttp-in",
      "listen": "127.0.0.1",
      "port": ${XHTTP_LOCAL_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
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
    mode_rules="$(reality_routing_rules_json)"
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
    "rules": [
${mode_rules}
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
  for domain in "$up_domain" "$down_domain"; do
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
  local caddy_tmp validate_output

  install -d -m 0755 "$(dirname "$CADDY_FILE")"
  caddy_tmp_dir="$(mktemp -d /tmp/caddy-config.XXXXXX)"
  caddy_tmp="${caddy_tmp_dir}/Caddyfile"
  cat >"$caddy_tmp" <<EOF
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

${up_domain} {
import xhttp_proxy
handle {
root * ${SITE_ROOT}/${up_domain}
file_server
}
}

${down_domain} {
import xhttp_proxy
handle {
root * ${SITE_ROOT}/${down_domain}
file_server
}
}
EOF
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

  for domain in "$up_domain" "$down_domain"; do
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

print_xhttp_result() {
  local extra import_link

  # 显式写出指纹：Xray 系客户端留空时默认 chrome，mihomo 留空时却是原生 Go TLS。
  extra="{\"downloadSettings\":{\"address\":\"${down_domain}\",\"port\":${PORT},\"network\":\"xhttp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"${down_domain}\",\"alpn\":[\"h2\"],\"fingerprint\":\"${fingerprint}\"},\"xhttpSettings\":{\"path\":\"${xhttp_path}\"}}}"
  import_link="vless://${uuid}@${up_domain}:${PORT}?encryption=none&security=tls&sni=${up_domain}&alpn=h2&fp=${fingerprint}&type=xhttp&path=$(urlencode "$xhttp_path")&mode=stream-up&extra=$(urlencode "$extra")#Xray-XHTTP"

  printf '\n\033[1;32m安装完成，Xray 与 Caddy 正在运行。\033[0m\n\n'
  printf '上行域名：%s\n' "$up_domain"
  printf '下行域名：%s\n' "$down_domain"
  printf '端口：%s\n' "$PORT"
  printf 'UUID：%s\n' "$uuid"
  printf 'XHTTP 路径：%s\n' "$xhttp_path"
  printf '传输模式：stream-up（上下行分离）\n'
  printf '客户端指纹：%s\n\n' "$fingerprint"
  printf '客户端导入链接：\n%s\n\n' "$import_link"
  printf 'Xray 配置：%s\n' "$CONFIG_FILE"
  printf 'Caddy 配置：%s\n' "$CADDY_FILE"
  printf '伪装站点目录：%s/%s、%s/%s\n' "$SITE_ROOT" "$up_domain" "$SITE_ROOT" "$down_domain"
  print_status_hint xray caddy
  printf '\n'
  warn "伪装站点目录为空时首页返回 404；请为两个域名分别放入不同的静态站点（可用 skills/vless-deploy 让 agent 生成）。"
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
    prompt_xhttp_domains
  fi
  check_ports
  confirm_overwrite
  [[ "$mode" == "reality" ]] || confirm_caddy_overwrite
  install_dependencies
  if [[ "$mode" == "reality" ]]; then
    [[ -n "$server_address" ]] || detect_public_address
  else
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
