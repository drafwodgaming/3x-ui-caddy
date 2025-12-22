#!/usr/bin/env bash
set -e

# UPDATE 2.12 - Enhanced Version
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/3x-ui-install.log"
COOKIE_FILE="/tmp/xui_cookies.txt"
CONFIG_DIR="/etc/3x-ui"
CONFIG_FILE="/root/vless_reality_config.txt"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check root
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && log "ERROR" "Root privileges required" && exit 1
}

# Check OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
        source /usr/lib/os-release
        release=$ID
    else
        echo -e "${red}✗ Failed to detect OS${plain}"
        log "ERROR" "Failed to detect OS"
        exit 1
    fi
    log "INFO" "Detected OS: $release"
}

# Get system architecture
get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${red}✗ Unsupported architecture${plain}" && log "ERROR" "Unsupported architecture: $(uname -m)" && exit 1 ;;
    esac
}

# Print banner
print_banner() {
    clear
    echo -e "${cyan}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │        3X-UI + CADDY INSTALLER          │"
    echo "  │              Enhanced Version           │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
}

# Validate input
validate_input() {
    local input=$1
    local type=$2
    
    case $type in
        port)
            if ! [[ "$input" =~ ^[0-9]+$ ]] || [ "$input" -lt 1 ] || [ "$input" -gt 65535 ]; then
                echo -e "${red}✗ Invalid port number${plain}"
                return 1
            fi
            ;;
        domain)
            if ! [[ "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                echo -e "${red}✗ Invalid domain format${plain}"
                return 1
            fi
            ;;
    esac
    return 0
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
    log "INFO" "Credentials configured"
}

# --- Panel ports/domains ---
read_parameters() {
    echo -e "${blue}┌ Configuration${plain}"
    echo -e "${blue}│${plain}"
    
    # Panel port with validation
    while true; do
        read -rp "$(echo -e ${blue}│${plain}) Panel port [8080]: " PANEL_PORT
        PANEL_PORT=${PANEL_PORT:-8080}
        if validate_input "$PANEL_PORT" "port"; then
            break
        fi
    done
    
    # Subscription port with validation
    while true; do
        read -rp "$(echo -e ${blue}│${plain}) Subscription port [2096]: " SUB_PORT
        SUB_PORT=${SUB_PORT:-2096}
        if validate_input "$SUB_PORT" "port"; then
            break
        fi
    done
    
    # Only ask for domains if using Caddy
    if [[ "$USE_CADDY" == "true" ]]; then
        while true; do
            read -rp "$(echo -e ${blue}│${plain}) Panel domain: " PANEL_DOMAIN
            if validate_input "$PANEL_DOMAIN" "domain"; then
                break
            fi
        done
        
        while true; do
            read -rp "$(echo -e ${blue}│${plain}) Subscription domain: " SUB_DOMAIN
            if validate_input "$SUB_DOMAIN" "domain"; then
                break
            fi
        done
    fi
    echo -e "${blue}│${plain}"
    echo -e "${blue}└${plain}"
    log "INFO" "Parameters configured"
}

# --- Ask if user wants to use Caddy ---
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
    log "INFO" "Caddy option: $USE_CADDY"
}

# --- Ask if user wants to create default inbound ---
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
    log "INFO" "Default inbound option: $CREATE_DEFAULT_INBOUND"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Install base dependencies ---
install_base() {
    echo -e "\n${yellow}→${plain} Installing dependencies..."
    log "INFO" "Installing dependencies"
    
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >/dev/null 2>&1
            if ! command_exists wget; then apt-get install -y -q wget >/dev/null 2>&1; fi
            if ! command_exists curl; then apt-get install -y -q curl >/dev/null 2>&1; fi
            if ! command_exists tar; then apt-get install -y -q tar >/dev/null 2>&1; fi
            if ! command_exists sqlite3; then apt-get install -y -q sqlite3 >/dev/null 2>&1; fi
            if ! command_exists jq; then apt-get install -y -q jq >/dev/null 2>&1; fi
            if ! command_exists openssl; then apt-get install -y -q openssl >/dev/null 2>&1; fi
        ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update >/dev/null 2>&1
            if ! command_exists wget; then dnf install -y -q wget >/dev/null 2>&1; fi
            if ! command_exists curl; then dnf install -y -q curl >/dev/null 2>&1; fi
            if ! command_exists tar; then dnf install -y -q tar >/dev/null 2>&1; fi
            if ! command_exists sqlite; then dnf install -y -q sqlite >/dev/null 2>&1; fi
            if ! command_exists jq; then dnf install -y -q jq >/dev/null 2>&1; fi
            if ! command_exists openssl; then dnf install -y -q openssl >/dev/null 2>&1; fi
        ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1
                if ! command_exists wget; then yum install -y wget >/dev/null 2>&1; fi
                if ! command_exists curl; then yum install -y curl >/dev/null 2>&1; fi
                if ! command_exists tar; then yum install -y tar >/dev/null 2>&1; fi
                if ! command_exists sqlite; then yum install -y sqlite >/dev/null 2>&1; fi
                if ! command_exists jq; then yum install -y jq >/dev/null 2>&1; fi
                if ! command_exists openssl; then yum install -y openssl >/dev/null 2>&1; fi
            else
                dnf -y update >/dev/null 2>&1
                if ! command_exists wget; then dnf install -y -q wget >/dev/null 2>&1; fi
                if ! command_exists curl; then dnf install -y -q curl >/dev/null 2>&1; fi
                if ! command_exists tar; then dnf install -y -q tar >/dev/null 2>&1; fi
                if ! command_exists sqlite; then dnf install -y -q sqlite >/dev/null 2>&1; fi
                if ! command_exists jq; then dnf install -y -q jq >/dev/null 2>&1; fi
                if ! command_exists openssl; then dnf install -y -q openssl >/dev/null 2>&1; fi
            fi
        ;;
        *)
            apt-get update >/dev/null 2>&1
            if ! command_exists wget; then apt-get install -y -q wget >/dev/null 2>&1; fi
            if ! command_exists curl; then apt-get install -y -q curl >/dev/null 2>&1; fi
            if ! command_exists tar; then apt-get install -y -q tar >/dev/null 2>&1; fi
            if ! command_exists sqlite3; then apt-get install -y -q sqlite3 >/dev/null 2>&1; fi
            if ! command_exists jq; then apt-get install -y -q jq >/dev/null 2>&1; fi
            if ! command_exists openssl; then apt-get install -y -q openssl >/dev/null 2>&1; fi
        ;;
    esac
    echo -e "${green}✓${plain} Dependencies installed"
    log "INFO" "Dependencies installed successfully"
}

# --- Install 3X-UI ---
install_3xui() {
    echo -e "${yellow}→${plain} Installing 3x-ui..."
    log "INFO" "Installing 3x-ui"
    
    cd /usr/local/
    
    # Create backup if exists
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null || true
        mv /usr/local/x-ui/ /usr/local/x-ui-backup-$(date +%Y%m%d%H%M%S)/
        log "INFO" "Existing installation backed up"
    fi
    
    tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ ! -n "$tag_version" ]] && echo -e "${red}✗ Failed to fetch version${plain}" && log "ERROR" "Failed to fetch 3x-ui version" && exit 1
    
    wget --inet4-only -q -O /usr/local/x-ui-linux-$(get_arch).tar.gz \
        https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(get_arch).tar.gz
    
    [[ $? -ne 0 ]] && echo -e "${red}✗ Download failed${plain}" && log "ERROR" "Failed to download 3x-ui" && exit 1
    
    wget --inet4-only -q -O /usr/bin/x-ui-temp \
        https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
    
    tar zxf x-ui-linux-$(get_arch).tar.gz >/dev/null 2>&1
    rm x-ui-linux-$(get_arch).tar.gz -f
    
    cd x-ui
    chmod +x x-ui x-ui.sh
    
    if [[ $(get_arch) == "armv5" || $(get_arch) == "armv6" || $(get_arch) == "armv7" ]]; then
        mv bin/xray-linux-$(get_arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(get_arch)
    
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    
    config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)
    
    /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1
    
    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl start x-ui
    
    # Wait for service to be ready
    sleep 5
    
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
    
    echo -e "${green}✓${plain} 3x-ui ${tag_version} installed"
    log "INFO" "3x-ui ${tag_version} installed successfully"
}

# --- Install Caddy ---
install_caddy() {
    echo -e "${yellow}→${plain} Installing Caddy..."
    log "INFO" "Installing Caddy"
    
    # Create backup if exists
    if [[ -e /etc/caddy/Caddyfile ]]; then
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile-backup-$(date +%Y%m%d%H%M%S)
        log "INFO" "Existing Caddyfile backed up"
    fi
    
    case "${release}" in
        ubuntu | debian | armbian)
            apt update >/dev/null 2>&1
            if ! command_exists ca-certificates; then apt install -y ca-certificates >/dev/null 2>&1; fi
            if ! command_exists gnupg; then apt install -y gnupg >/dev/null 2>&1; fi
            if ! command_exists curl; then apt install -y curl >/dev/null 2>&1; fi
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update >/dev/null 2>&1
            if ! command_exists curl; then dnf install -y curl >/dev/null 2>&1; fi
            if ! command_exists gnupg2; then dnf install -y gnupg2 >/dev/null 2>&1; fi
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1
                if ! command_exists curl; then yum install -y curl >/dev/null 2>&1; fi
                if ! command_exists gnupg2; then yum install -y gnupg2 >/dev/null 2>&1; fi
            else
                dnf -y update >/dev/null 2>&1
                if ! command_exists curl; then dnf install -y curl >/dev/null 2>&1; fi
                if ! command_exists gnupg2; then dnf install -y gnupg2 >/dev/null 2>&1; fi
            fi
            ;;
        *)
            apt update >/dev/null 2>&1
            if ! command_exists ca-certificates; then apt install -y ca-certificates >/dev/null 2>&1; fi
            if ! command_exists gnupg; then apt install -y gnupg >/dev/null 2>&1; fi
            if ! command_exists curl; then apt install -y curl >/dev/null 2>&1; fi
            ;;
    esac
    
    # Install Caddy using official method
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update >/dev/null 2>&1
    apt install -y caddy >/dev/null 2>&1
    
    echo -e "${green}✓${plain} Caddy installed"
    log "INFO" "Caddy installed successfully"
}

# --- Configure Caddy ---
configure_caddy() {
    echo -e "${yellow}→${plain} Configuring reverse proxy..."
    log "INFO" "Configuring Caddy reverse proxy"
    
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
    # Wait for service to be ready
    sleep 5
    echo -e "${green}✓${plain} Caddy configured"
    log "INFO" "Caddy configured successfully"
}

# Get panel URL
get_panel_url() {
    if [[ "$USE_CADDY" == "true" ]]; then
        PANEL_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}"
    else
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
        PANEL_URL="http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}"
    fi
    echo "$PANEL_URL"
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
    
    if [[ "$USE_CADDY" == "true" ]]; then
        echo -e "\n${yellow}⚠  Panel is not secure with SSL certificate${plain}"
        echo -e "${yellow}   Configure SSL in panel settings for production${plain}"
    fi
    
    log "INFO" "Installation summary displayed"
}

api_login() {
    echo -e "${yellow}→${plain} Authenticating..."
    log "INFO" "Attempting API login"
    
    PANEL_URL=$(get_panel_url)
    
    local response=$(curl -k -s -c "$COOKIE_FILE" -X POST \
        "${PANEL_URL}login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}" 2>/dev/null)
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${green}✓${plain} Authentication successful"
        log "INFO" "API authentication successful"
        return 0
    else
        echo -e "${red}✗${plain} Authentication failed"
        log "ERROR" "API authentication failed: $response"
        return 1
    fi
}

generate_uuid() {
    PANEL_URL=$(get_panel_url)
    
    local response=$(curl -k -s -b "$COOKIE_FILE" \
        "${PANEL_URL}panel/api/server/getNewUUID" 2>/dev/null)
    
    local uuid=$(echo "$response" | jq -r '.obj.uuid // empty' 2>/dev/null)
    
    if [[ -n "$uuid" && "$uuid" != "null" ]]; then
        echo "$uuid"
        log "INFO" "UUID generated: $uuid"
    else
        log "ERROR" "Failed to generate UUID"
        echo ""
    fi
}

generate_reality_keys() {
    PANEL_URL=$(get_panel_url)
    
    local response=$(curl -k -s -b "$COOKIE_FILE" \
        "${PANEL_URL}panel/api/server/getNewX25519Cert" 2>/dev/null)
    
    REALITY_PRIVATE_KEY=$(echo "$response" | jq -r '.obj.privateKey // empty' 2>/dev/null)
    REALITY_PUBLIC_KEY=$(echo "$response" | jq -r '.obj.publicKey // empty' 2>/dev/null)
    
    if [[ -z "$REALITY_PRIVATE_KEY" || "$REALITY_PRIVATE_KEY" == "null" ]]; then
        REALITY_PRIVATE_KEY=""
        log "ERROR" "Failed to generate Reality private key"
    fi
    
    if [[ -z "$REALITY_PUBLIC_KEY" || "$REALITY_PUBLIC_KEY" == "null" ]]; then
        REALITY_PUBLIC_KEY=""
        log "ERROR" "Failed to generate Reality public key"
    fi
    
    if [[ -n "$REALITY_PRIVATE_KEY" && -n "$REALITY_PUBLIC_KEY" ]]; then
        log "INFO" "Reality keys generated successfully"
    fi
}

create_vless_reality_inbound() {
    echo -e "${yellow}→${plain} Creating VLESS Reality inbound..."
    log "INFO" "Creating VLESS Reality inbound"
    
    # Predefined settings for inbound
    REALITY_PORT=443
    REALITY_SNI="web.max.ru"
    REALITY_DEST="web.max.ru:443"
    CLIENT_EMAIL="user"
    
    CLIENT_UUID=$(generate_uuid)
    if [[ -z "$CLIENT_UUID" ]]; then
        echo -e "${red}✗${plain} Failed to generate UUID"
        log "ERROR" "Failed to generate UUID for inbound"
        return 1
    fi

    # Basic UUID format validation
    if [[ ! "$CLIENT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo -e "${red}✗${plain} Generated UUID has invalid format: $CLIENT_UUID"
        log "ERROR" "Invalid UUID format: $CLIENT_UUID"
        return 1
    fi
    
    echo -e "${cyan}│${plain} UUID generated: $CLIENT_UUID"
    
    generate_reality_keys
    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        echo -e "${red}✗${plain} Failed to generate Reality keys"
        log "ERROR" "Failed to generate Reality keys"
        return 1
    fi
    echo -e "${cyan}│${plain} Reality keys generated"
    echo -e "${cyan}│${plain} Private Key: ${REALITY_PRIVATE_KEY:0:20}..."
    echo -e "${cyan}│${plain} Public Key:  ${REALITY_PUBLIC_KEY:0:20}..."
    
    SHORT_ID=$(openssl rand -hex 8)

    # Create JSON payload with PUBLIC KEY
    local inbound_json
    inbound_json=$(jq -n \
        --argjson port "$REALITY_PORT" \
        --arg uuid "$CLIENT_UUID" \
        --arg email "$CLIENT_EMAIL" \
        --arg dest "$REALITY_DEST" \
        --arg sni "$REALITY_SNI" \
        --arg privkey "$REALITY_PRIVATE_KEY" \
        --arg pubkey "$REALITY_PUBLIC_KEY" \
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
                        publicKey: $pubkey,
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

    # Debug information
    echo -e "${yellow}→${plain} Payload to be sent to API:"
    echo "$inbound_json" | jq .
    echo -e "${blue}└${plain}"
    
    PANEL_URL=$(get_panel_url)
    
    local response=$(curl -k -s -b "$COOKIE_FILE" -X POST \
        "${PANEL_URL}panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$inbound_json" 2>/dev/null)

    echo -e "${yellow}→${plain} API Response:"
    echo "$response" | jq .
    echo -e "${blue}└${plain}"
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${green}✓${plain} VLESS Reality inbound created"
        log "INFO" "VLESS Reality inbound created successfully"
        
        # Create config directory if it doesn't exist
        mkdir -p "$CONFIG_DIR"
        
        cat > "$CONFIG_FILE" <<EOF
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
Configuration saved to: ${CONFIG_FILE}
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
        echo -e "${cyan}│${plain}  ${yellow}Config: ${CONFIG_FILE}${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}└${plain}"
        
        return 0
    else
        echo -e "${red}✗${plain} Failed to create inbound"
        log "ERROR" "Failed to create inbound: $response"
        return 1
    fi
}

configure_reality_inbound() {
    echo -e "\n${magenta}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${magenta}  Creating VLESS Reality Inbound...${plain}"
    echo -e "${magenta}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}\n"

    if api_login; then
        if create_vless_reality_inbound; then
            echo -e "\n${green}✓ VLESS Reality inbound configured successfully!${plain}\n"
            log "INFO" "VLESS Reality inbound configured successfully"
        else
            echo -e "\n${yellow}⚠ Failed to create inbound automatically${plain}"
            echo -e "${yellow}  Please create it manually in the panel${plain}\n"
            log "WARNING" "Failed to create inbound automatically"
        fi
    else
        echo -e "\n${yellow}⚠ API authentication failed${plain}"
        echo -e "${yellow}  Please create inbound manually in the panel${plain}\n"
        log "WARNING" "API authentication failed"
    fi
}

# Cleanup function
cleanup() {
    if [[ -f "$COOKIE_FILE" ]]; then
        rm -f "$COOKIE_FILE"
    fi
    log "INFO" "Cleanup completed"
}

# Set up trap for cleanup
trap cleanup EXIT

# --- Main execution ---
main() {
    log "INFO" "Starting 3X-UI + Caddy installation"
    
    print_banner
    check_root
    check_os
    
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
    
    log "INFO" "Installation completed successfully"
    echo -e "\n${green}Installation completed successfully!${plain}"
    echo -e "${yellow}Log file: $LOG_FILE${plain}"
}

main
