#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#UPDATE 2.12

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly PLAIN='\033[0m'

# Global variables
XUI_USERNAME=""
XUI_PASSWORD=""
PANEL_PORT=""
SUB_PORT=""
PANEL_DOMAIN=""
SUB_DOMAIN=""
USE_CADDY="false"
CREATE_DEFAULT_INBOUND="false"
ACTUAL_PORT=""
ACTUAL_WEBBASE=""
PANEL_URL=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""

# Check root privileges
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}✗ Error:${PLAIN} Root privileges required" && exit 1
}

# Detect OS
detect_os() {
    local release
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
        source /usr/lib/os-release
        release=$ID
    else
        echo -e "${RED}✗ Failed to detect OS${PLAIN}"
        exit 1
    fi
    echo "$release"
}

# Detect architecture
get_arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo 'amd64' ;;
        i*86|x86) echo '386' ;;
        armv8*|armv8|arm64|aarch64) echo 'arm64' ;;
        armv7*|armv7|arm) echo 'armv7' ;;
        armv6*|armv6) echo 'armv6' ;;
        armv5*|armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${RED}✗ Unsupported architecture${PLAIN}" && exit 1 ;;
    esac
}

# Print banner
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │        3X-UI + CADDY INSTALLER          │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${PLAIN}"
}

# Generate random string
generate_random_string() {
    local length=$1
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
}

# Generate random password
generate_random_password() {
    local length=$((20 + RANDOM % 11))
    LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | head -c "$length"
}

# Read credentials
read_credentials() {
    echo -e "${BLUE}┌ Panel Credentials${PLAIN}"
    read -rp "$(echo -e "${BLUE}│${PLAIN}") Username (leave empty to generate): " XUI_USERNAME
    read -rp "$(echo -e "${BLUE}│${PLAIN}") Password (leave empty to generate): " XUI_PASSWORD

    [[ -z "$XUI_USERNAME" ]] && XUI_USERNAME=$(generate_random_string 10)
    [[ -z "$XUI_PASSWORD" ]] && XUI_PASSWORD=$(generate_random_password)
    
    echo -e "${CYAN}│ Username:${GREEN} $XUI_USERNAME ${CYAN}Password:${GREEN} $XUI_PASSWORD${PLAIN}"
    echo -e "${BLUE}└${PLAIN}"
}

# Read parameters
read_parameters() {
    echo -e "${BLUE}┌ Configuration${PLAIN}"
    echo -e "${BLUE}│${PLAIN}"
    
    read -rp "$(echo -e "${BLUE}│${PLAIN}") Panel port [8080]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
    
    read -rp "$(echo -e "${BLUE}│${PLAIN}") Subscription port [2096]: " SUB_PORT
    SUB_PORT=${SUB_PORT:-2096}
    
    if [[ "$USE_CADDY" == "true" ]]; then
        read -rp "$(echo -e "${BLUE}│${PLAIN}") Panel domain: " PANEL_DOMAIN
        read -rp "$(echo -e "${BLUE}│${PLAIN}") Subscription domain: " SUB_DOMAIN
    fi
    
    echo -e "${BLUE}│${PLAIN}"
    echo -e "${BLUE}└${PLAIN}"
}

# Ask yes/no question
ask_yes_no() {
    local prompt=$1
    local var_name=$2
    
    echo -e "${BLUE}┌ $prompt${PLAIN}"
    echo -e "${BLUE}│${PLAIN}"
    
    while true; do
        read -rp "$(echo -e "${BLUE}│${PLAIN}") [y/n]: " yn
        case $yn in
            [Yy]*) eval "$var_name=true"; break ;;
            [Nn]*) eval "$var_name=false"; break ;;
            *) echo -e "${BLUE}│${PLAIN} Please answer y or n." ;;
        esac
    done
    
    echo -e "${BLUE}└${PLAIN}"
}

# Ask if user wants to use Caddy
ask_caddy() {
    echo -e "${BLUE}┌ Caddy Configuration${PLAIN}"
    echo -e "${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} Do you want to use Caddy as a reverse proxy?"
    echo -e "${BLUE}│${PLAIN} This will allow you to use domains and SSL certificates."
    echo -e "${BLUE}│${PLAIN}"
    
    while true; do
        read -rp "$(echo -e "${BLUE}│${PLAIN}") Use Caddy? [y/n]: " yn
        case $yn in
            [Yy]*) USE_CADDY="true"; break ;;
            [Nn]*) USE_CADDY="false"; break ;;
            *) echo -e "${BLUE}│${PLAIN} Please answer y or n." ;;
        esac
    done
    
    echo -e "${BLUE}└${PLAIN}"
}

# Ask if user wants to create default inbound
ask_default_inbound() {
    echo -e "${BLUE}┌ Default Inbound${PLAIN}"
    echo -e "${BLUE}│${PLAIN}"
    echo -e "${BLUE}│${PLAIN} Do you want to create a default VLESS Reality inbound?"
    echo -e "${BLUE}│${PLAIN} This will create an inbound with predefined settings."
    echo -e "${BLUE}│${PLAIN}"
    
    while true; do
        read -rp "$(echo -e "${BLUE}│${PLAIN}") Create default inbound? [y/n]: " yn
        case $yn in
            [Yy]*) CREATE_DEFAULT_INBOUND="true"; break ;;
            [Nn]*) CREATE_DEFAULT_INBOUND="false"; break ;;
            *) echo -e "${BLUE}│${PLAIN} Please answer y or n." ;;
        esac
    done
    
    echo -e "${BLUE}└${PLAIN}"
}

# Install base dependencies
install_base() {
    local release=$(detect_os)
    echo -e "\n${YELLOW}→${PLAIN} Installing dependencies..."
    
    case "${release}" in
        ubuntu|debian|armbian)
            apt-get update >/dev/null 2>&1
            apt-get install -y -q wget curl tar tzdata sqlite3 jq >/dev/null 2>&1
            ;;
        fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol)
            dnf -y update >/dev/null 2>&1
            dnf install -y -q wget curl tar tzdata sqlite jq >/dev/null 2>&1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update >/dev/null 2>&1
                yum install -y wget curl tar tzdata sqlite jq >/dev/null 2>&1
            else
                dnf -y update >/dev/null 2>&1
                dnf install -y -q wget curl tar tzdata sqlite jq >/dev/null 2>&1
            fi
            ;;
        *)
            apt-get update >/dev/null 2>&1
            apt-get install -y -q wget curl tar tzdata sqlite3 jq >/dev/null 2>&1
            ;;
    esac
    
    echo -e "${GREEN}✓${PLAIN} Dependencies installed"
}

# Get latest release version
get_latest_version() {
    curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Download file
download_file() {
    local url=$1
    local output=$2
    wget --inet4-only -q -O "$output" "$url"
}

# Install 3X-UI
install_3xui() {
    echo -e "${YELLOW}→${PLAIN} Installing 3x-ui..."
    
    local arch=$(get_arch)
    local tag_version=$(get_latest_version)
    
    [[ -z "$tag_version" ]] && echo -e "${RED}✗ Failed to fetch version${PLAIN}" && exit 1
    
    cd /usr/local/
    
    download_file \
        "https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-${arch}.tar.gz" \
        "/usr/local/x-ui-linux-${arch}.tar.gz" || {
        echo -e "${RED}✗ Download failed${PLAIN}"
        exit 1
    }
    
    download_file \
        "https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh" \
        "/usr/bin/x-ui-temp"
    
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null || true
        rm -rf /usr/local/x-ui/
    fi
    
    tar zxf "x-ui-linux-${arch}.tar.gz" >/dev/null 2>&1
    rm -f "x-ui-linux-${arch}.tar.gz"
    
    cd x-ui
    chmod +x x-ui x-ui.sh
    
    if [[ $arch == "armv5" || $arch == "armv6" || $arch == "armv7" ]]; then
        mv "bin/xray-linux-${arch}" bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    
    chmod +x x-ui "bin/xray-linux-${arch}"
    
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    
    local config_webBasePath=$(generate_random_string 18)
    
    /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
        -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1
    
    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl start x-ui
    
    sleep 5
    
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
    
    echo -e "${GREEN}✓${PLAIN} 3x-ui ${tag_version} installed"
}

# Install Caddy
install_caddy() {
    echo -e "${YELLOW}→${PLAIN} Installing Caddy..."
    
    apt update >/dev/null 2>&1
    apt install -y ca-certificates curl gnupg >/dev/null 2>&1
    
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null \
        | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
    
    echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
        | tee /etc/apt/sources.list.d/caddy.list >/dev/null
    
    apt update >/dev/null 2>&1
    apt install -y caddy >/dev/null 2>&1
    
    echo -e "${GREEN}✓${PLAIN} Caddy installed"
}

# Configure Caddy
configure_caddy() {
    echo -e "${YELLOW}→${PLAIN} Configuring reverse proxy..."
    
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
    echo -e "${GREEN}✓${PLAIN} Caddy configured"
}

# Get server IP
get_server_ip() {
    curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org
}

# Get panel info
get_panel_info() {
    local panel_info=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$panel_info" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$panel_info" | grep -oP 'webBasePath: \K\S+')
}

# Set panel URL
set_panel_url() {
    if [[ "$USE_CADDY" == "true" ]]; then
        PANEL_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}"
    else
        local server_ip=$(get_server_ip)
        PANEL_URL="http://${server_ip}:${ACTUAL_PORT}${ACTUAL_WEBBASE}"
    fi
}

# Show summary
show_summary() {
    sleep 2
    get_panel_info
    local server_ip=$(get_server_ip)
    
    clear
    echo -e "${GREEN}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │         Installation Complete           │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${PLAIN}"
    
    echo -e "${CYAN}┌ Credentials${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Username    ${GREEN}${XUI_USERNAME}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Password    ${GREEN}${XUI_PASSWORD}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}└${PLAIN}"
    
    echo -e "\n${CYAN}┌ Access URLs${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        echo -e "${CYAN}│${PLAIN}  Panel (HTTPS)    ${BLUE}https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}${PLAIN}"
        echo -e "${CYAN}│${PLAIN}  Subscription     ${BLUE}https://${SUB_DOMAIN}:8443/${PLAIN}"
    else
        echo -e "${CYAN}│${PLAIN}  Panel (Direct)   ${BLUE}http://${server_ip}:${ACTUAL_PORT}${ACTUAL_WEBBASE}${PLAIN}"
    fi
    
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}└${PLAIN}"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        echo -e "\n${YELLOW}⚠  Panel is not secure with SSL certificate${PLAIN}"
        echo -e "${YELLOW}   Configure SSL in panel settings for production${PLAIN}"
    fi
}

# API login
api_login() {
    echo -e "${YELLOW}→${PLAIN} Authenticating..."
    
    set_panel_url
    
    local response=$(curl -k -s -c /tmp/xui_cookies.txt -X POST \
        "${PANEL_URL}login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}" 2>/dev/null)
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${GREEN}✓${PLAIN} Authentication successful"
        return 0
    else
        echo -e "${RED}✗${PLAIN} Authentication failed"
        echo "Response was: $response"
        return 1
    fi
}

# Generate UUID
generate_uuid() {
    set_panel_url
    
    local response=$(curl -k -s -b /tmp/xui_cookies.txt \
        "${PANEL_URL}panel/api/server/getNewUUID" 2>/dev/null)
    
    local uuid=$(echo "$response" | jq -r '.obj.uuid // empty' 2>/dev/null)
    
    [[ -n "$uuid" && "$uuid" != "null" ]] && echo "$uuid" || echo ""
}

# Generate reality keys
generate_reality_keys() {
    set_panel_url
    
    local response=$(curl -k -s -b /tmp/xui_cookies.txt \
        "${PANEL_URL}panel/api/server/getNewX25519Cert" 2>/dev/null)
    
    REALITY_PRIVATE_KEY=$(echo "$response" | jq -r '.obj.privateKey // empty' 2>/dev/null)
    REALITY_PUBLIC_KEY=$(echo "$response" | jq -r '.obj.publicKey // empty' 2>/dev/null)
    
    [[ -z "$REALITY_PRIVATE_KEY" || "$REALITY_PRIVATE_KEY" == "null" ]] && REALITY_PRIVATE_KEY=""
    [[ -z "$REALITY_PUBLIC_KEY" || "$REALITY_PUBLIC_KEY" == "null" ]] && REALITY_PUBLIC_KEY=""
}

# Validate UUID format
validate_uuid() {
    local uuid=$1
    [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

# Create VLESS Reality inbound
create_vless_reality_inbound() {
    echo -e "${YELLOW}→${PLAIN} Creating VLESS Reality inbound..."
    
    readonly REALITY_PORT=443
    readonly REALITY_SNI="web.max.ru"
    readonly REALITY_DEST="web.max.ru:443"
    readonly CLIENT_EMAIL="user"
    
    local client_uuid=$(generate_uuid)
    if [[ -z "$client_uuid" ]]; then
        echo -e "${RED}✗${PLAIN} Failed to generate UUID"
        return 1
    fi

    if ! validate_uuid "$client_uuid"; then
        echo -e "${RED}✗${PLAIN} Generated UUID has invalid format: $client_uuid"
        return 1
    fi
    
    echo -e "${CYAN}│${PLAIN} UUID generated: $client_uuid"
    
    generate_reality_keys
    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        echo -e "${RED}✗${PLAIN} Failed to generate Reality keys"
        return 1
    fi
    
    echo -e "${CYAN}│${PLAIN} Reality keys generated"
    echo -e "${CYAN}│${PLAIN} Private Key: ${REALITY_PRIVATE_KEY:0:20}..."
    echo -e "${CYAN}│${PLAIN} Public Key:  ${REALITY_PUBLIC_KEY:0:20}..."
    
    local short_id=$(openssl rand -hex 8)

    local inbound_json=$(jq -n \
        --argjson port "$REALITY_PORT" \
        --arg uuid "$client_uuid" \
        --arg email "$CLIENT_EMAIL" \
        --arg dest "$REALITY_DEST" \
        --arg sni "$REALITY_SNI" \
        --arg privkey "$REALITY_PRIVATE_KEY" \
        --arg pubkey "$REALITY_PUBLIC_KEY" \
        --arg shortid "$short_id" \
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

    echo -e "${YELLOW}→${PLAIN} Payload to be sent to API:"
    echo "$inbound_json" | jq .
    echo -e "${BLUE}└${PLAIN}"
    
    set_panel_url
    
    local response=$(curl -k -s -b /tmp/xui_cookies.txt -X POST \
        "${PANEL_URL}panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$inbound_json" 2>/dev/null)

    echo -e "${YELLOW}→${PLAIN} API Response:"
    echo "$response" | jq .
    echo -e "${BLUE}└${PLAIN}"
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo -e "${GREEN}✓${PLAIN} VLESS Reality inbound created"
        
        save_vless_config "$client_uuid" "$short_id"
        display_vless_config "$client_uuid" "$short_id"
        
        return 0
    else
        echo -e "${RED}✗${PLAIN} Failed to create inbound"
        echo "Response was: $response"
        return 1
    fi
}

# Save VLESS configuration to file
save_vless_config() {
    local client_uuid=$1
    local short_id=$2
    local server_ip=$(get_server_ip)
    
    cat > /root/vless_reality_config.txt <<EOF
═══════════════════════════════════════════════════
VLESS Reality Configuration
═══════════════════════════════════════════════════

Server IP: ${server_ip}
Port: ${REALITY_PORT}
UUID: ${client_uuid}
Flow: xtls-rprx-vision
Encryption: none
Network: tcp
Security: reality

Reality Settings:
  SNI: ${REALITY_SNI}
  Public Key: ${REALITY_PUBLIC_KEY}
  Short ID: ${short_id}
  Spider X: /

Client Email: ${CLIENT_EMAIL}

═══════════════════════════════════════════════════
Configuration saved to: /root/vless_reality_config.txt
═══════════════════════════════════════════════════
EOF
}

# Display VLESS configuration
display_vless_config() {
    local client_uuid=$1
    local short_id=$2
    
    echo ""
    echo -e "${CYAN}┌ VLESS Reality Configuration${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Port             ${GREEN}${REALITY_PORT}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  UUID             ${GREEN}${client_uuid}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Flow             ${GREEN}xtls-rprx-vision${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Public Key       ${GREEN}${REALITY_PUBLIC_KEY}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  Short ID         ${GREEN}${short_id}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  SNI              ${GREEN}${REALITY_SNI}${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}│${PLAIN}  ${YELLOW}Config: /root/vless_reality_config.txt${PLAIN}"
    echo -e "${CYAN}│${PLAIN}"
    echo -e "${CYAN}└${PLAIN}"
}

# Configure reality inbound
configure_reality_inbound() {
    echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e "${MAGENTA}  Creating VLESS Reality Inbound...${PLAIN}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}\n"

    if api_login; then
        if create_vless_reality_inbound; then
            echo -e "\n${GREEN}✓ VLESS Reality inbound configured successfully!${PLAIN}\n"
        else
            echo -e "\n${YELLOW}⚠ Failed to create inbound automatically${PLAIN}"
            echo -e "${YELLOW}  Please create it manually in the panel${PLAIN}\n"
        fi
    else
        echo -e "\n${YELLOW}⚠ API authentication failed${PLAIN}"
        echo -e "${YELLOW}  Please create inbound manually in the panel${PLAIN}\n"
    fi
}

# Main execution
main() {
    check_root
    print_banner
    read_credentials
    ask_caddy
    ask_default_inbound
    read_parameters
    install_base
    install_3xui
    
    if [[ "$USE_CADDY" == "true" ]]; then
        install_caddy
        configure_caddy
    fi
    
    show_summary
    
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" ]]; then
        configure_reality_inbound
    fi
}

main
