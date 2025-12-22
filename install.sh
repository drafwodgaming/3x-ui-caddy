#!/usr/bin/env bash
set -e

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && exit 1

# Check OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo -e "${red}✗ Failed to detect OS${plain}"
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}✗ Unsupported architecture${plain}" && exit 1 ;;
    esac
}

print_banner() {
    clear
    echo -e "${cyan}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │        3X-UI + CADDY INSTALLER          │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
}

# --- Credentials input ---
read_credentials() {
    echo -e "${blue}┌ Panel Credentials${plain}"
    read -rp "$(echo -e ${blue}│${plain}) Username (leave empty to generate): " XUI_USERNAME
    read -rp "$(echo -e ${blue}│${plain}) Password (leave empty to generate): " XUI_PASSWORD

    if [[ -z "$XUI_USERNAME" ]]; then
        XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n 1)
    fi
    if [[ -z "$XUI_PASSWORD" ]]; then
        length=$((20 + RANDOM % 11))
        XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w $length | head -n 1)
    fi
    echo -e "${cyan}│ Username:${green} $XUI_USERNAME ${cyan}Password:${green} $XUI_PASSWORD${plain}"
    echo -e "${blue}└${plain}"
}

# --- Panel ports/domains ---
read_parameters() {
    echo -e "${blue}┌ Configuration${plain}"
    echo -e "${blue}│${plain}"
    read -rp "$(echo -e ${blue}│${plain}) Panel port [8080]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
    
    read -rp "$(echo -e ${blue}│${plain}) Subscription port [2096]: " SUB_PORT
    SUB_PORT=${SUB_PORT:-2096}
    
    read -rp "$(echo -e ${blue}│${plain}) Panel domain: " PANEL_DOMAIN
    read -rp "$(echo -e ${blue}│${plain}) Subscription domain: " SUB_DOMAIN
    
    read -rp "$(echo -e ${blue}│${plain}) Reality SNI (e.g., www.google.com) [www.microsoft.com]: " REALITY_SNI
    REALITY_SNI=${REALITY_SNI:-www.microsoft.com}
    
    read -rp "$(echo -e ${blue}│${plain}) VLESS port [443]: " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    
    echo -e "${blue}└${plain}"
}

# --- Install base dependencies ---
install_base() {
    echo -e "\n${yellow}→${plain} Installing dependencies..."
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq uuid-runtime >/dev/null 2>&1
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq util-linux >/dev/null 2>&1
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1 && yum install -y wget curl tar tzdata sqlite jq util-linux >/dev/null 2>&1
            else
                dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq util-linux >/dev/null 2>&1
            fi
        ;;
        *)
            apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq uuid-runtime >/dev/null 2>&1
        ;;
    esac
    echo -e "${green}✓${plain} Dependencies installed"
}

# --- Install 3X-UI ---
install_3xui() {
    echo -e "${yellow}→${plain} Installing 3x-ui..."
    
    cd /usr/local/
    
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ ! -n "$tag_version" ]] && echo -e "${red}✗ Failed to fetch version${plain}" && exit 1
    
    wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz \
        https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    
    [[ $? -ne 0 ]] && echo -e "${red}✗ Download failed${plain}" && exit 1
    
    wget --inet4-only -q -O /usr/bin/x-ui-temp \
        https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null || true
        rm /usr/local/x-ui/ -rf
    fi
    
    tar zxf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
    rm x-ui-linux-$(arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui x-ui.sh
    
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)
    
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    
    config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)
    
    /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1
    
    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl start x-ui
    
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
    
    echo -e "${green}✓${plain} 3x-ui ${tag_version} installed"
}

# --- Install Caddy ---
install_caddy() {
    echo -e "${yellow}→${plain} Installing Caddy..."
    
    apt update >/dev/null 2>&1 && apt install -y ca-certificates curl gnupg >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null \
        | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
        | tee /etc/apt/sources.list.d/caddy.list >/dev/null
    apt update >/dev/null 2>&1
    apt install -y caddy >/dev/null 2>&1
    
    echo -e "${green}✓${plain} Caddy installed"
}

# --- Configure Caddy ---
configure_caddy() {
    echo -e "${yellow}→${plain} Configuring reverse proxy..."
    
    cat > /etc/caddy/Caddyfile <<EOF
$PANEL_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$PANEL_PORT
    tls internal
}

$SUB_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$SUB_PORT
}
EOF
    
    systemctl restart caddy
    echo -e "${green}✓${plain} Caddy configured"
}

# --- Setup VLESS + Reality ---
setup_vless_reality() {
    echo -e "${yellow}→${plain} Adding default VLESS Reality configuration..."
    
    # Ждём, пока панель полностью запустится
    sleep 3
    
    # Генерируем необходимые данные
    CLIENT_UUID=$(uuidgen)
    SHORT_ID=$(openssl rand -hex 8)
    
    # Генерируем Reality ключи используя xray
    KEYS=$(/usr/local/x-ui/bin/xray-linux-$(arch) x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    
    # Создаём инбаунд напрямую в базе данных SQLite
    DB_PATH="/etc/x-ui/x-ui.db"
    
    # JSON конфигурация для инбаунда
    SETTINGS_JSON=$(cat <<EOF
{
  "clients": [
    {
      "id": "${CLIENT_UUID}",
      "flow": "xtls-rprx-vision",
      "email": "default_client",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": ""
    }
  ],
  "decryption": "none",
  "fallbacks": []
}
EOF
)

    STREAM_SETTINGS=$(cat <<EOF
{
  "network": "tcp",
  "security": "reality",
  "realitySettings": {
    "show": false,
    "dest": "${REALITY_SNI}:443",
    "xver": 0,
    "serverNames": [
      "${REALITY_SNI}"
    ],
    "privateKey": "${PRIVATE_KEY}",
    "minClientVer": "",
    "maxClientVer": "",
    "maxTimeDiff": 0,
    "shortIds": [
      "${SHORT_ID}"
    ]
  },
  "tcpSettings": {
    "acceptProxyProtocol": false,
    "header": {
      "type": "none"
    }
  }
}
EOF
)

    SNIFFING_JSON='{"enabled":true,"destOverride":["http","tls","quic"]}'
    
    # Вставляем инбаунд в базу данных
    sqlite3 "$DB_PATH" <<EOF
INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing)
VALUES (
    1,
    0,
    0,
    0,
    'VLESS-Reality-Vision',
    1,
    0,
    '',
    ${VLESS_PORT},
    'vless',
    '${SETTINGS_JSON}',
    '${STREAM_SETTINGS}',
    'inbound-${VLESS_PORT}',
    '${SNIFFING_JSON}'
);
EOF

    # Перезапускаем панель для применения изменений
    systemctl restart x-ui
    sleep 2
    
    # Сохраняем данные для вывода
    echo "$CLIENT_UUID" > /tmp/vless_uuid
    echo "$PUBLIC_KEY" > /tmp/vless_public_key
    echo "$SHORT_ID" > /tmp/vless_short_id
    
    echo -e "${green}✓${plain} VLESS Reality configuration added"
}

# --- Show summary ---
show_summary() {
    sleep 2
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    # Читаем сохранённые данные VLESS
    CLIENT_UUID=$(cat /tmp/vless_uuid 2>/dev/null || echo "N/A")
    PUBLIC_KEY=$(cat /tmp/vless_public_key 2>/dev/null || echo "N/A")
    SHORT_ID=$(cat /tmp/vless_short_id 2>/dev/null || echo "N/A")
    
    # Создаём VLESS URL
    VLESS_LINK="vless://${CLIENT_UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality-Vision"
    
    clear
    echo -e "${green}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │         Installation Complete           │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
    
    echo -e "${cyan}┌ Panel Credentials${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Username    ${green}${XUI_USERNAME}${plain}"
    echo -e "${cyan}│${plain}  Password    ${green}${XUI_PASSWORD}${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    echo -e "\n${cyan}┌ Access URLs${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Panel (HTTPS)    ${blue}https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}  Panel (Direct)   ${blue}http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Subscription     ${blue}https://${SUB_DOMAIN}:8443/${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    echo -e "\n${cyan}┌ VLESS Reality Configuration${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Port         ${green}${VLESS_PORT}${plain}"
    echo -e "${cyan}│${plain}  UUID         ${green}${CLIENT_UUID}${plain}"
    echo -e "${cyan}│${plain}  Public Key   ${green}${PUBLIC_KEY}${plain}"
    echo -e "${cyan}│${plain}  Short ID     ${green}${SHORT_ID}${plain}"
    echo -e "${cyan}│${plain}  SNI          ${green}${REALITY_SNI}${plain}"
    echo -e "${cyan}│${plain}  Flow         ${green}xtls-rprx-vision${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    echo -e "\n${cyan}┌ VLESS Connection Link${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  ${magenta}${VLESS_LINK}${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    echo -e "\n${yellow}⚠  Panel is not secure with SSL certificate${plain}"
    echo -e "${yellow}   Configure SSL in panel settings for production${plain}"
    
    echo -e "\n${green}✓ Ready to use!${plain}\n"
    
    # Очищаем временные файлы
    rm -f /tmp/vless_uuid /tmp/vless_public_key /tmp/vless_short_id
}

# --- Main execution ---
main() {
    print_banner
    read_credentials
    read_parameters
    install_base
    install_3xui
    install_caddy
    configure_caddy
    setup_vless_reality
    show_summary
}

main
