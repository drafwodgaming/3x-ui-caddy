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
    
    echo -e "${blue}│${plain}"
    read -rp "$(echo -e ${blue}│${plain}) VLESS Reality port [443]: " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    
    read -rp "$(echo -e ${blue}│${plain}) Server Name (SNI) [www.google.com]: " VLESS_SNI
    VLESS_SNI=${VLESS_SNI:-www.google.com}
    
    read -rp "$(echo -e ${blue}│${plain}) Client email [user@example.com]: " CLIENT_EMAIL
    CLIENT_EMAIL=${CLIENT_EMAIL:-user@example.com}
    
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
    
    tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ ! -n "$tag_version" ]] && echo -e "${red}✗ Failed to fetch version${plain}" && exit 1
    
    wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz \
        https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    
    [[ $? -ne 0 ]] && echo -e "${red}✗ Download failed${plain}" && exit 1
    
    wget --inet4-only -q -O /usr/bin/x-ui-temp \
        https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
    
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

# --- API Login ---
api_login() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local response=$(curl -s -X POST "http://127.0.0.1:${PANEL_PORT}${config_webBasePath}/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}" \
            -c /tmp/x-ui-cookie.txt)
        
        if echo "$response" | grep -q "success"; then
            echo -e "${green}✓${plain} API login successful"
            return 0
        fi
        
        echo -e "${yellow}⟳${plain} Waiting for panel... (attempt $attempt/$max_attempts)"
        sleep 3
        ((attempt++))
    done
    
    echo -e "${red}✗ API login failed after $max_attempts attempts${plain}"
    echo -e "${red}Response: $response${plain}"
    return 1
}

# --- Add VLESS Reality Inbound ---
add_vless_reality() {
    echo -e "${yellow}→${plain} Creating VLESS Reality inbound..."
    
    # Check if x-ui service is running
    echo -e "${cyan}│${plain} Checking x-ui service status..."
    if ! systemctl is-active --quiet x-ui; then
        echo -e "${red}✗ x-ui service is not running${plain}"
        echo -e "${yellow}⚠${plain}  Service status:"
        systemctl status x-ui --no-pager -l
        return 1
    fi
    echo -e "${green}✓${plain} x-ui service is running"
    
    # Check if port is listening
    echo -e "${cyan}│${plain} Checking if panel port ${PANEL_PORT} is open..."
    local port_check=0
    for i in {1..15}; do
        if netstat -tln 2>/dev/null | grep -q ":${PANEL_PORT}" || ss -tln 2>/dev/null | grep -q ":${PANEL_PORT}"; then
            port_check=1
            break
        fi
        echo -e "${yellow}⟳${plain} Waiting for port to open... ($i/15)"
        sleep 2
    done
    
    if [ $port_check -eq 0 ]; then
        echo -e "${red}✗ Port ${PANEL_PORT} is not open${plain}"
        echo -e "${yellow}⚠${plain}  Open ports:"
        netstat -tln 2>/dev/null | grep LISTEN || ss -tln 2>/dev/null | grep LISTEN
        return 1
    fi
    echo -e "${green}✓${plain} Port ${PANEL_PORT} is open"
    
    # Test panel connectivity
    echo -e "${cyan}│${plain} Testing panel connectivity..."
    local test_response=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PANEL_PORT}${config_webBasePath}/login" --max-time 5)
    echo -e "${cyan}│${plain}   Response code: ${test_response}"
    
    if [ "$test_response" == "000" ]; then
        echo -e "${red}✗ Cannot connect to panel${plain}"
        echo -e "${yellow}⚠${plain}  Panel logs:"
        journalctl -u x-ui -n 20 --no-pager
        return 1
    fi
    
    # Login to get session
    if ! api_login; then
        echo -e "${red}✗ Failed to login to API${plain}"
        return 1
    fi
    
    echo -e "${cyan}│${plain} Generating keys..."
    
    # Generate keys
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    echo -e "${cyan}│${plain}   UUID: ${uuid}"
    
    local x25519_keys=$(/usr/local/x-ui/x-ui x25519)
    local private_key=$(echo "$x25519_keys" | grep "Private key:" | awk '{print $3}')
    local public_key=$(echo "$x25519_keys" | grep "Public key:" | awk '{print $3}')
    echo -e "${cyan}│${plain}   Private Key: ${private_key}"
    echo -e "${cyan}│${plain}   Public Key: ${public_key}"
    
    local short_id=$(openssl rand -hex 8)
    echo -e "${cyan}│${plain}   Short ID: ${short_id}"
    
    # Create inbound JSON
    local inbound_json=$(cat <<EOF
{
  "enable": true,
  "remark": "VLESS-Reality-TCP",
  "listen": "",
  "port": ${VLESS_PORT},
  "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"${uuid}\",\"email\":\"${CLIENT_EMAIL}\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true,\"tgId\":\"\",\"subId\":\"${uuid}\",\"reset\":0}],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"reality\",\"externalProxy\":[],\"realitySettings\":{\"show\":false,\"xver\":0,\"dest\":\"${VLESS_SNI}:443\",\"serverNames\":[\"${VLESS_SNI}\"],\"privateKey\":\"${private_key}\",\"minClient\":\"\",\"maxClient\":\"\",\"maxTimediff\":0,\"shortIds\":[\"${short_id}\"],\"settings\":{\"publicKey\":\"${public_key}\",\"fingerprint\":\"chrome\",\"serverName\":\"\",\"spiderX\":\"/\"}},\"tcpSettings\":{\"acceptProxyProtocol\":false,\"header\":{\"type\":\"none\"}}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"metadataOnly\":false,\"routeOnly\":false}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}
EOF
)
    
    echo -e "${cyan}│${plain} Sending API request..."
    echo -e "${cyan}│${plain}   Endpoint: http://127.0.0.1:${PANEL_PORT}${config_webBasePath}/panel/api/inbounds/add"
    
    # Add inbound via API
    local response=$(curl -s -w "\n%{http_code}" -X POST "http://127.0.0.1:${PANEL_PORT}${config_webBasePath}/panel/api/inbounds/add" \
        -H "Content-Type: application/json" \
        -b /tmp/x-ui-cookie.txt \
        -d "$inbound_json")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    echo -e "${cyan}│${plain}   HTTP Code: ${http_code}"
    echo -e "${cyan}│${plain}   Response Body: ${body}"
    
    if echo "$body" | grep -q "success"; then
        echo -e "${green}✓${plain} VLESS Reality inbound created successfully"
        
        # Store config for summary
        VLESS_UUID="$uuid"
        VLESS_PUBLIC_KEY="$public_key"
        VLESS_SHORT_ID="$short_id"
        return 0
    else
        echo -e "${red}✗ Failed to create inbound${plain}"
        echo -e "${red}┌ Error Details${plain}"
        echo -e "${red}│${plain}"
        echo -e "${red}│${plain} HTTP Status: ${http_code}"
        echo -e "${red}│${plain} Response: ${body}"
        echo -e "${red}│${plain}"
        
        # Try to parse error message if JSON
        if echo "$body" | jq -e . >/dev/null 2>&1; then
            local error_msg=$(echo "$body" | jq -r '.msg // .message // .error // "Unknown error"')
            echo -e "${red}│${plain} Error Message: ${error_msg}"
        fi
        
        echo -e "${red}│${plain}"
        echo -e "${red}│${plain} Debug Info:"
        echo -e "${red}│${plain}   Cookie file: $(cat /tmp/x-ui-cookie.txt 2>/dev/null | head -n5 || echo 'Cookie file empty/missing')"
        echo -e "${red}│${plain}   Panel Port: ${PANEL_PORT}"
        echo -e "${red}│${plain}   Web Base Path: ${config_webBasePath}"
        echo -e "${red}│${plain}"
        echo -e "${red}└${plain}"
        
        # Save full request for debugging
        echo "$inbound_json" > /tmp/x-ui-inbound-request.json
        echo -e "${yellow}⚠${plain}  Full JSON request saved to: /tmp/x-ui-inbound-request.json"
        
        return 1
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
    echo -e "${cyan}│${plain}  Panel (HTTPS)    ${blue}https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}  Panel (Direct)   ${blue}http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Subscription     ${blue}https://${SUB_DOMAIN}:8443/sub/${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}└${plain}"
    
    if [[ -n "$VLESS_UUID" ]]; then
        echo -e "\n${cyan}┌ VLESS Reality Configuration${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}│${plain}  Protocol         ${green}VLESS${plain}"
        echo -e "${cyan}│${plain}  Port             ${green}${VLESS_PORT}${plain}"
        echo -e "${cyan}│${plain}  UUID             ${green}${VLESS_UUID}${plain}"
        echo -e "${cyan}│${plain}  Flow             ${green}xtls-rprx-vision${plain}"
        echo -e "${cyan}│${plain}  SNI              ${green}${VLESS_SNI}${plain}"
        echo -e "${cyan}│${plain}  Public Key       ${green}${VLESS_PUBLIC_KEY}${plain}"
        echo -e "${cyan}│${plain}  Short ID         ${green}${VLESS_SHORT_ID}${plain}"
        echo -e "${cyan}│${plain}  Client Email     ${green}${CLIENT_EMAIL}${plain}"
        echo -e "${cyan}│${plain}"
        echo -e "${cyan}└${plain}"
    fi
    
    echo -e "\n${yellow}⚠  Panel is using self-signed SSL certificate${plain}"
    echo -e "${yellow}   Configure real SSL in panel settings for production${plain}"
    
    echo -e "\n${green}✓ Ready to use!${plain}\n"
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
    add_vless_reality
    show_summary
}

main
