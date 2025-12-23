#!/usr/bin/env bash
set -e
# #
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && exit 1

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

read_parameters() {
    echo -e "${blue}┌ Configuration${plain}"
    echo -e "${blue}│${plain}"
    read -rp "$(echo -e ${blue}│${plain}) Panel port [8080]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
    
    read -rp "$(echo -e ${blue}│${plain}) Subscription port [2096]: " SUB_PORT
    SUB_PORT=${SUB_PORT:-2096}
    
    # Only ask for domains if using Caddy
    if [[ "$USE_CADDY" == "true" ]]; then
        read -rp "$(echo -e ${blue}│${plain}) Panel domain: " PANEL_DOMAIN
        read -rp "$(echo -e ${blue}│${plain}) Subscription domain: " SUB_DOMAIN
    fi
    echo -e "${blue}│${plain}"
    echo -e "${blue}└${plain}"
}

ask_caddy() {
    echo -e "${blue}┌ Caddy Configuration${plain}"
    echo -e "${blue}│${plain}"
    echo -e "${blue}│${plain} Do you want to use Caddy as a reverse proxy?"
    echo -e "${blue}│${plain} This will allow you to use domains and SSL certificates."
    echo -e "${blue}│${plain}"
    while true; do
        read -rp "$(echo -e ${blue}│${plain}) Use Caddy? [y/n]: " yn
        case $yn in
            [Yy]* ) USE_CADDY="true"; break;;
            [Nn]* ) USE_CADDY="false"; break;;
            * ) echo -e "${blue}│${plain} Please answer y or n.";;
        esac
    done
    echo -e "${blue}└${plain}"
}

ask_default_inbound() {
    echo -e "${blue}┌ Default Inbound${plain}"
    echo -e "${blue}│${plain}"
    echo -e "${blue}│${plain} Do you want to create a default VLESS Reality inbound?"
    echo -e "${blue}│${plain} This will create an inbound with predefined settings."
    echo -e "${blue}│${plain}"
    while true; do
        read -rp "$(echo -e ${blue}│${plain}) Create default inbound? [y/n]: " yn
        case $yn in
            [Yy]* ) CREATE_DEFAULT_INBOUND="true"; break;;
            [Nn]* ) CREATE_DEFAULT_INBOUND="false"; break;;
            * ) echo -e "${blue}│${plain} Please answer y or n.";;
        esac
    done
    echo -e "${blue}└${plain}"
}

# --- Install base dependencies ---
install_base() {
    echo -e "\n${yellow}→${plain} Installing dependencies..."
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >/dev/null 2>&1
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >/dev/null 2>&1
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1 && yum install -y wget curl tar tzdata sqlite jq >/dev/null 2>&1
            else
                dnf -y update >/dev/null 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >/dev/null 2>&1
            fi
        ;;
        *)
            apt-get update >/dev/null 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >/dev/null 2>&1
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
    sleep 5
    
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
    sleep 5
    echo -e "${green}✓${plain} Caddy configured"
}

# --- Get panel info via API ---
get_panel_info() {
    if [[ "$USE_CADDY" == "true" ]]; then
        PANEL_URL="https://${PANEL_DOMAIN}:8443"
    else
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
        PANEL_URL="http://${SERVER_IP}:${ACTUAL_PORT}"
    fi
}

# --- API Login ---
api_login() {
    echo -e "${yellow}→${plain} Authenticating via API..."
    
    # Get actual panel info first
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    
    if [[ "$USE_CADDY" == "true" ]]; then
        PANEL_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}"
    else
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
        PANEL_URL="http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}"
    fi
    
    local response=$(curl -k -s -c /tmp/xui_cookies.txt -X POST \
        "${PANEL_URL}login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}" 2>/dev/null)
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${green}✓${plain} Authentication successful"
        return 0
    else
        echo -e "${red}✗${plain} Authentication failed"
        echo "Response: $response"
        return 1
    fi
}

# --- Generate UUID via API ---
generate_uuid() {
    local response=$(curl -k -s -b /tmp/xui_cookies.txt -X GET \
        "${PANEL_URL}panel/api/server/getNewUUID" 2>/dev/null)
    
    local uuid=$(echo "$response" | jq -r '.obj.uuid // empty' 2>/dev/null)
    
    if [[ -n "$uuid" && "$uuid" != "null" ]]; then
        echo "$uuid"
    else
        echo ""
    fi
}

# --- Generate Reality Keys via API ---
generate_reality_keys() {
    local response=$(curl -k -s -b /tmp/xui_cookies.txt -X GET \
        "${PANEL_URL}panel/api/server/getNewX25519Cert" 2>/dev/null)
    
    REALITY_PRIVATE_KEY=$(echo "$response" | jq -r '.obj.privateKey // empty' 2>/dev/null)
    REALITY_PUBLIC_KEY=$(echo "$response" | jq -r '.obj.publicKey // empty' 2>/dev/null)
    
    if [[ -z "$REALITY_PRIVATE_KEY" || "$REALITY_PRIVATE_KEY" == "null" ]]; then
        REALITY_PRIVATE_KEY=""
    fi
    
    if [[ -z "$REALITY_PUBLIC_KEY" || "$REALITY_PUBLIC_KEY" == "null" ]]; then
        REALITY_PUBLIC_KEY=""
    fi
}

# --- Create VLESS Reality Inbound via API ---
create_vless_reality_inbound() {
    echo -e "${yellow}→${plain} Creating VLESS Reality inbound via API..."
    
    REALITY_PORT=443
    REALITY_SNI="www.google.com"
    REALITY_DEST="www.google.com:443"
    CLIENT_EMAIL="user"
    
    CLIENT_UUID=$(generate_uuid)
    if [[ -z "$CLIENT_UUID" ]]; then
        echo -e "${red}✗${plain} Failed to generate UUID via API"
        return 1
    fi
    
    if [[ ! "$CLIENT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo -e "${red}✗${plain} Generated UUID has invalid format: $CLIENT_UUID"
        return 1
    fi
    
    echo -e "${cyan}│${plain} UUID generated: $CLIENT_UUID"
    
    generate_reality_keys
    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        echo -e "${red}✗${plain} Failed to generate Reality keys via API"
        return 1
    fi
    echo -e "${cyan}│${plain} Reality keys generated"
    
    SHORT_ID=$(openssl rand -hex 8)
    
    # Create inbound via API
    local inbound_json
    inbound_json=$(jq -n \
        --argjson port "$REALITY_PORT" \
        --arg uuid "$CLIENT_UUID" \
        --arg email "$CLIENT_EMAIL" \
        --arg dest "$REALITY_DEST" \
        --arg sni "$REALITY_SNI" \
        --arg privkey "$REALITY_PRIVATE_KEY" \
        --arg shortid "$SHORT_ID" \
        --arg remark "VLESS-Reality-Vision" \
        '{
            enable: true,
            port: $port,
            protocol: "vless",
            settings: (
                {
                    clients: [{ 
                        id: $uuid, 
                        flow: "xtls-rprx-vision", 
                        email: $email, 
                        limitIp: 0, 
                        totalGB: 0, 
                        expiryTime: 0, 
                        enable: true, 
                        tgId: "", 
                        subId: "" 
                    }],
                    decryption: "none",
                    fallbacks: []
                } | @json
            ),
            streamSettings: (
                {
                    network: "tcp",
                    security: "reality",
                    realitySettings: {
                        show: false,
                        dest: $dest,
                        xver: 0,
                        serverNames: [$sni],
                        privateKey: $privkey,
                        minClientVer: "",
                        maxClientVer: "",
                        maxTimeDiff: 0,
                        shortIds: [$shortid]
                    },
                    tcpSettings: { 
                        acceptProxyProtocol: false, 
                        header: { type: "none" } 
                    }
                } | @json
            ),
            sniffing: (
                {
                    enabled: true,
                    destOverride: ["http", "tls", "quic", "fakedns"],
                    metadataOnly: false,
                    routeOnly: false
                } | @json
            ),
            remark: $remark,
            listen: "",
            allocate: { 
                strategy: "always", 
                refresh: 5, 
                concurrency: 3 
            }
        }'
    )
    
    local response=$(curl -k -s -b /tmp/xui_cookies.txt -X POST \
        "${PANEL_URL}panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$inbound_json" 2>/dev/null)
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${green}✓${plain} VLESS Reality inbound created via API"
        
        # Save config to file
        cat > /root/vless_reality_config.txt <<EOF
═══════════════════════════════════════════════════
VLESS Reality Configuration
═══════════════════════════════════════════════════

Server IP: $(curl -s ifconfig.me 2>/dev/null)
Port: ${REALITY_PORT}
UUID: ${CLIENT_UUID}
Flow: xtls-rprx-vision
Encryption: none
Network: tcp
Security: reality

Reality Settings:
  SNI: ${REALITY_SNI}
  Public Key: ${REALITY_PUBLIC_KEY}
  Short ID: ${SHORT_ID}
  Spider X: /

Client Email: ${CLIENT_EMAIL}

═══════════════════════════════════════════════════
Configuration saved to: /root/vless_reality_config.txt
═══════════════════════════════════════════════════
EOF
        
        echo ""
        echo -e "${cyan}┌ VLESS Reality Configuration${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}│${plain}  Port             ${green}${REALITY_PORT}${plain}"
        echo -e "${cyan}│${plain}  UUID             ${green}${CLIENT_UUID}${plain}"
        echo -e "${cyan}│${plain}  Flow             ${green}xtls-rprx-vision${plain}"
        echo -e "${cyan}│${plain}  Public Key       ${green}${REALITY_PUBLIC_KEY}${plain}"
        echo -e "${cyan}│${plain}  Short ID         ${green}${SHORT_ID}${plain}"
        echo -e "${cyan}│${plain}  SNI              ${green}${REALITY_SNI}${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}│${plain}  ${yellow}Config: /root/vless_reality_config.txt${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}└${plain}"
        
        return 0
    else
        echo -e "${red}✗${plain} Failed to create inbound via API"
        echo "Response: $response"
        return 1
    fi
}

# --- Configure Reality Inbound ---
configure_reality_inbound() {
    echo -e "\n${magenta}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${magenta}  Creating VLESS Reality Inbound via API...${plain}"
    echo -e "${magenta}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}\n"

    if api_login; then
        if create_vless_reality_inbound; then
            echo -e "\n${green}✓ VLESS Reality inbound configured successfully via API!${plain}\n"
        else
            echo -e "\n${yellow}⚠ Failed to create inbound via API${plain}"
            echo -e "${yellow}  Please create it manually in the panel${plain}\n"
        fi
    else
        echo -e "\n${yellow}⚠ API authentication failed${plain}"
        echo -e "${yellow}  Please create inbound manually in the panel${plain}\n"
    fi
}

# --- Show summary ---
show_summary() {
    sleep 2
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    clear
    echo -e "${green}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │         Installation Complete           │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
    
    echo -e "${cyan}┌ Credentials${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Username    ${green}${XUI_USERNAME}${plain}"
    echo -e "${cyan}│${plain}  Password    ${green}${XUI_PASSWORD}${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    echo -e "\n${cyan}┌ Access URLs${plain}"
    echo -e "${cyan}│${plain}"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        echo -e "${cyan}│${plain}  Panel (HTTPS)    ${blue}https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}${plain}"
        echo -e "${cyan}│${plain}  Subscription     ${blue}https://${SUB_DOMAIN}:8443/${plain}"
    else
        echo -e "${cyan}│${plain}  Panel (Direct)   ${blue}http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}${plain}"
    fi
    
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
}

# --- Main execution ---
main() {
    print_banner
    read_credentials
    ask_caddy
    ask_default_inbound
    read_parameters
    install_base
    install_3xui
    
    # Only install and configure Caddy if user chose to use it
    if [[ "$USE_CADDY" == "true" ]]; then
        install_caddy
        configure_caddy
    fi
    
    show_summary
    
    # Only create default inbound if user chose to
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" ]]; then
        configure_reality_inbound
    fi
}

main
