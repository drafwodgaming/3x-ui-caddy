#!/usr/bin/env bash
set -e

# Colors 2
r='\033[0;31m' g='\033[0;32m' b='\033[0;34m' y='\033[0;33m' 
c='\033[0;36m' m='\033[0;35m' p='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && echo -e "${r}✗ Root required${p}" && exit 1

# Detect OS
source /etc/os-release 2>/dev/null || source /usr/lib/os-release 2>/dev/null || { echo -e "${r}✗ OS detection failed${p}"; exit 1; }

# Detect architecture
arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo 'amd64' ;;
        i*86|x86) echo '386' ;;
        armv8*|arm64|aarch64) echo 'arm64' ;;
        armv7*|armv7|arm) echo 'armv7' ;;
        armv6*) echo 'armv6' ;;
        armv5*) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${r}✗ Unsupported arch${p}" && exit 1 ;;
    esac
}

print_banner() {
    clear
    echo -e "${c}
  ╭─────────────────────────────────────────╮
  │      3X-UI + CADDY INSTALLER v2.12     │
  ╰─────────────────────────────────────────╯${p}\n"
}

# Get user input
get_input() {
    echo -e "${b}┌ Panel Credentials${p}"
    read -rp "$(echo -e ${b}│${p}) Username [auto]: " XUI_USERNAME
    read -rp "$(echo -e ${b}│${p}) Password [auto]: " XUI_PASSWORD
    XUI_USERNAME=${XUI_USERNAME:-$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)}
    XUI_PASSWORD=${XUI_PASSWORD:-$(tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | head -c $((20 + RANDOM % 11)))}
    echo -e "${c}│ User: ${g}$XUI_USERNAME ${c}Pass: ${g}$XUI_PASSWORD${p}"
    echo -e "${b}└${p}\n"

    echo -e "${b}┌ Caddy Setup${p}"
    read -rp "$(echo -e ${b}│${p}) Use Caddy reverse proxy? [y/n]: " USE_CADDY
    USE_CADDY=$([[ "$USE_CADDY" =~ ^[Yy]$ ]] && echo "true" || echo "false")
    echo -e "${b}└${p}\n"

    echo -e "${b}┌ Configuration${p}"
    read -rp "$(echo -e ${b}│${p}) Panel port [8080]: " PANEL_PORT
    read -rp "$(echo -e ${b}│${p}) Subscription port [2096]: " SUB_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
    SUB_PORT=${SUB_PORT:-2096}
    
    if [[ "$USE_CADDY" == "true" ]]; then
        read -rp "$(echo -e ${b}│${p}) Panel domain: " PANEL_DOMAIN
        read -rp "$(echo -e ${b}│${p}) Subscription domain: " SUB_DOMAIN
    fi
    echo -e "${b}└${p}\n"

    echo -e "${b}┌ Default Inbound${p}"
    read -rp "$(echo -e ${b}│${p}) Create VLESS Reality inbound? [y/n]: " CREATE_INBOUND
    CREATE_INBOUND=$([[ "$CREATE_INBOUND" =~ ^[Yy]$ ]] && echo "true" || echo "false")
    echo -e "${b}└${p}\n"
}

# Install dependencies
install_deps() {
    echo -e "${y}→${p} Installing dependencies..."
    case "$ID" in
        ubuntu|debian|armbian)
            apt-get update -qq && apt-get install -y -qq wget curl tar tzdata sqlite3 jq 2>&1 | grep -v "^[WE]:" ;;
        fedora|amzn|rhel|almalinux|rocky|ol)
            dnf -y -q update && dnf install -y -q wget curl tar tzdata sqlite jq ;;
        centos)
            [[ "$VERSION_ID" =~ ^7 ]] && yum -y -q update && yum install -y -q wget curl tar tzdata sqlite jq || \
            dnf -y -q update && dnf install -y -q wget curl tar tzdata sqlite jq ;;
        *) apt-get update -qq && apt-get install -y -qq wget curl tar tzdata sqlite3 jq 2>&1 | grep -v "^[WE]:" ;;
    esac
    echo -e "${g}✓${p} Dependencies installed"
}

# Install 3X-UI
install_3xui() {
    echo -e "${y}→${p} Installing 3x-ui..."
    cd /usr/local/
    
    tag=$(curl -sL "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$tag" ]] && echo -e "${r}✗ Version fetch failed${p}" && exit 1
    
    wget -q -O x-ui-linux-$(arch).tar.gz "https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag}/x-ui-linux-$(arch).tar.gz" || { echo -e "${r}✗ Download failed${p}"; exit 1; }
    wget -q -O /usr/bin/x-ui "https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh"
    
    [[ -e /usr/local/x-ui/ ]] && systemctl stop x-ui 2>/dev/null && rm -rf /usr/local/x-ui/
    
    tar xzf x-ui-linux-$(arch).tar.gz && rm x-ui-linux-$(arch).tar.gz
    cd x-ui && chmod +x x-ui x-ui.sh
    
    [[ $(arch) =~ ^armv[567]$ ]] && mv bin/xray-linux-$(arch) bin/xray-linux-arm && chmod +x bin/xray-linux-arm
    chmod +x x-ui bin/xray-linux-$(arch) /usr/bin/x-ui
    
    webpath=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 18)
    /usr/local/x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$PANEL_PORT" -webBasePath "$webpath" >/dev/null 2>&1
    
    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload && systemctl enable x-ui >/dev/null 2>&1 && systemctl start x-ui
    sleep 5
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
    
    echo -e "${g}✓${p} 3x-ui $tag installed"
}

# Install Caddy
install_caddy() {
    echo -e "${y}→${p} Installing Caddy..."
    apt update -qq && apt install -y -qq ca-certificates curl gnupg 2>&1 | grep -v "^[WE]:"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy.list
    apt update -qq && apt install -y -qq caddy 2>&1 | grep -v "^[WE]:"
    
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
    
    systemctl restart caddy && sleep 5
    echo -e "${g}✓${p} Caddy configured"
}

# Show summary
show_summary() {
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    IP=$(curl -s ifconfig.me 2>/dev/null || curl -s api.ipify.org)
    
    clear
    echo -e "${g}
  ╭─────────────────────────────────────────╮
  │         Installation Complete          │
  ╰─────────────────────────────────────────╯${p}\n"
    
    echo -e "${c}┌ Credentials${p}"
    echo -e "${c}│${p}  Username    ${g}$XUI_USERNAME${p}"
    echo -e "${c}│${p}  Password    ${g}$XUI_PASSWORD${p}"
    echo -e "${c}└${p}\n"
    
    echo -e "${c}┌ Access URLs${p}"
    if [[ "$USE_CADDY" == "true" ]]; then
        echo -e "${c}│${p}  Panel        ${b}https://$PANEL_DOMAIN:8443$WEBBASE${p}"
        echo -e "${c}│${p}  Subscription ${b}https://$SUB_DOMAIN:8443/${p}"
    else
        echo -e "${c}│${p}  Panel        ${b}http://$IP:$PORT$WEBBASE${p}"
    fi
    echo -e "${c}└${p}\n"
    
    [[ "$USE_CADDY" == "true" ]] && echo -e "${y}⚠  Configure SSL in panel for production${p}\n"
}

# API functions
api_call() {
    local endpoint=$1
    local method=${2:-GET}
    local data=$3
    
    URL=$([[ "$USE_CADDY" == "true" ]] && echo "https://$PANEL_DOMAIN:8443$WEBBASE" || echo "http://$(curl -s ifconfig.me):$PORT$WEBBASE")
    
    curl -sk -b /tmp/xui_cookies.txt -X $method "${URL}${endpoint}" \
        -H "Content-Type: application/json" \
        ${data:+-d "$data"} 2>/dev/null
}

create_inbound() {
    echo -e "${y}→${p} Creating VLESS Reality inbound..."
    
    # Login
    WEBBASE=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -oP 'webBasePath: \K\S+')
    PORT=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | grep -oP 'port: \K\d+')
    
    URL=$([[ "$USE_CADDY" == "true" ]] && echo "https://$PANEL_DOMAIN:8443$WEBBASE" || echo "http://$(curl -s ifconfig.me):$PORT$WEBBASE")
    
    auth=$(curl -sk -c /tmp/xui_cookies.txt -X POST "${URL}/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}" 2>/dev/null)
    
    [[ $(echo "$auth" | jq -r '.success') != "true" ]] && { echo -e "${r}✗ Auth failed${p}"; return 1; }
    
    # Generate UUID and keys
    uuid=$(api_call "panel/api/server/getNewUUID" | jq -r '.obj.uuid')
    keys=$(api_call "panel/api/server/getNewX25519Cert")
    privkey=$(echo "$keys" | jq -r '.obj.privateKey')
    pubkey=$(echo "$keys" | jq -r '.obj.publicKey')
    shortid=$(openssl rand -hex 8)
    
    [[ -z "$uuid" || -z "$privkey" || -z "$pubkey" ]] && { echo -e "${r}✗ Key generation failed${p}"; return 1; }
    
    # Create inbound
    payload=$(jq -n \
        --arg uuid "$uuid" \
        --arg privkey "$privkey" \
        --arg pubkey "$pubkey" \
        --arg shortid "$shortid" \
        '{
            enable: true, port: 443, protocol: "vless", remark: "VLESS-Reality-Vision",
            settings: ({clients:[{id:$uuid,flow:"xtls-rprx-vision",email:"user",limitIp:0,totalGB:0,expiryTime:0,enable:true,tgId:"",subId:""}],decryption:"none",fallbacks:[]}|@json),
            streamSettings: ({network:"tcp",security:"reality",realitySettings:{show:false,dest:"web.max.ru:443",xver:0,serverNames:["web.max.ru"],privateKey:$privkey,publicKey:$pubkey,minClientVer:"",maxClientVer:"",maxTimeDiff:0,shortIds:[$shortid]},tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}}}|@json),
            sniffing: ({enabled:true,destOverride:["http","tls","quic","fakedns"],metadataOnly:false,routeOnly:false}|@json),
            listen: "", allocate: {strategy:"always",refresh:5,concurrency:3}
        }')
    
    result=$(api_call "panel/api/inbounds/add" POST "$payload")
    
    if [[ $(echo "$result" | jq -r '.success') == "true" ]]; then
        echo -e "${g}✓${p} Inbound created"
        
        cat > /root/vless_reality.txt <<EOF
VLESS Reality Configuration
───────────────────────────────────────────
Server: $(curl -s ifconfig.me)
Port: 443
UUID: $uuid
Flow: xtls-rprx-vision
Public Key: $pubkey
Short ID: $shortid
SNI: web.max.ru
───────────────────────────────────────────
EOF
        
        echo -e "\n${c}┌ VLESS Config${p}"
        echo -e "${c}│${p}  UUID        ${g}$uuid${p}"
        echo -e "${c}│${p}  Public Key  ${g}$pubkey${p}"
        echo -e "${c}│${p}  Short ID    ${g}$shortid${p}"
        echo -e "${c}│${p}  ${y}Saved: /root/vless_reality.txt${p}"
        echo -e "${c}└${p}\n"
    else
        echo -e "${r}✗${p} Inbound creation failed"
    fi
}

# Main
main() {
    print_banner
    get_input
    install_deps
    install_3xui
    [[ "$USE_CADDY" == "true" ]] && install_caddy
    show_summary
    [[ "$CREATE_INBOUND" == "true" ]] && create_inbound
}

main
