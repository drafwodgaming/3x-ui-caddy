#!/usr/bin/env bash
set -e

# =========================================
#   3X-UI + Caddy Installer + Auto Inbound
# =========================================

# Цвета
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && exit 1

# Detect OS
if [[ -f /etc/os-release ]]; then source /etc/os-release; fi

arch() {
    case "$(uname -m)" in
        x86_64) echo 'amd64' ;;
        arm64|aarch64) echo 'arm64' ;;
        armv7*) echo 'armv7' ;;
        *) echo 'amd64' ;;
    esac
}

print_banner() {
    clear
    echo -e "${cyan}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │       3X-UI + CADDY INSTALLER          │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
}

read_credentials() {
    echo -e "${blue}┌ Panel Credentials${plain}"
    echo -e "${blue}│${plain}"
    read -rp "$(echo -e ${blue}│${plain}) Username (leave empty to generate): " XUI_USERNAME
    read -rp "$(echo -e ${blue}│${plain}) Password (leave empty to generate): " XUI_PASSWORD
    [[ -z "$XUI_USERNAME" ]] && XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n1)
    [[ -z "$XUI_PASSWORD" ]] && XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#%&*' </dev/urandom | fold -w $((20 + RANDOM % 11)) | head -n1)
    echo -e "${blue}└${plain}"
}

read_parameters() {
    echo -e "${blue}┌ Configuration${plain}"
    echo -e "${blue}│${plain}"
    read -rp "$(echo -e ${blue}│${plain}) Panel port [8080]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
    read -rp "$(echo -e ${blue}│${plain}) Panel domain: " PANEL_DOMAIN
    read -rp "$(echo -e ${blue}│${plain}) Subscription domain: " SUB_DOMAIN
    echo -e "${blue}└${plain}"
}

install_base() {
    echo -e "\n${yellow}→${plain} Installing dependencies..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y wget curl tar jq sqlite3 ca-certificates gnupg >/dev/null 2>&1
    echo -e "${green}✓${plain} Dependencies installed"
}

install_3xui() {
    echo -e "${yellow}→${plain} Installing 3x-ui..."
    cd /usr/local/
    tag=$(curl -s "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" | jq -r .tag_name)
    wget -q "https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag}/x-ui-linux-$(arch).tar.gz"
    tar xzf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz
    mv x-ui /usr/local/x-ui
    chmod +x /usr/local/x-ui/x-ui
    /usr/local/x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$PANEL_PORT" >/dev/null 2>&1
    cp x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl start x-ui
    /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
    echo -e "${green}✓${plain} 3x-ui installed"
}

install_caddy() {
    echo -e "${yellow}→${plain} Installing Caddy..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg
    echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
         > /etc/apt/sources.list.d/caddy.list
    apt update -y >/dev/null 2>&1
    apt install -y caddy >/dev/null 2>&1
    echo -e "${green}✓${plain} Caddy installed"
}

configure_caddy() {
    echo -e "${yellow}→${plain} Configuring Caddy..."
    cat > /etc/caddy/Caddyfile <<EOF
$PANEL_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$PANEL_PORT
    tls internal
}

$SUB_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$PANEL_PORT
}
EOF
    systemctl restart caddy
    echo -e "${green}✓${plain} Caddy configured"
}

login_panel() {
    echo -e "${yellow}→${plain} Logging in to panel API..."
    curl -s -c /tmp/xui_cookies.txt -X POST "http://127.0.0.1:$PANEL_PORT/login" \
         -H "Content-Type: application/json" \
         -d "{\"username\":\"$XUI_USERNAME\",\"password\":\"$XUI_PASSWORD\"}"
}

create_inbound() {
    echo -e "${yellow}→${plain} Adding default VLESS Reality inbound..."
    VLESS_UUID=$(uuidgen)
    PUBLIC_KEY=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | fold -w 64 | head -n1)
    SHORT1=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | fold -w 8 | head -n1)
    SHORT2=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | fold -w 8 | head -n1)

    curl -s -b /tmp/xui_cookies.txt -H "Content-Type: application/json" \
         -X POST "http://127.0.0.1:$PANEL_PORT/panel/api/inbounds/add" \
         -d "{
            \"remark\": \"Auto VLESS Reality\",
            \"port\": 443,
            \"protocol\": \"vless\",
            \"settings\": {\"clients\":[{\"id\":\"$VLESS_UUID\",\"email\":\"user1\",\"enable\":true}]},
            \"streamSettings\": {
                \"network\":\"tcp\",
                \"security\":\"reality\",
                \"realitySettings\":{\"publicKey\":\"$PUBLIC_KEY\",\"shortIds\":[\"$SHORT1\",\"$SHORT2\"]}
            }
         }"
    echo -e "${green}✓${plain} Inbound added"
}

add_client() {
    echo -e "${yellow}→${plain} Adding a client to the inbound..."
    INBOUND_ID=$(curl -s -b /tmp/xui_cookies.txt "http://127.0.0.1:$PANEL_PORT/panel/api/inbounds/list" \
                 | jq -r '.[0].id')
    CLIENT_UUID=$(uuidgen)
    SUB_ID=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | fold -w 12 | head -n1)

    curl -s -b /tmp/xui_cookies.txt -H "Content-Type: multipart/form-data" \
         -F "id=$INBOUND_ID" \
         -F "settings={\"clients\":[{\"id\":\"$CLIENT_UUID\",\"email\":\"$SUB_ID\",\"enable\":true}]}" \
         "http://127.0.0.1:$PANEL_PORT/panel/api/inbounds/addClient"

    echo "Client $SUB_ID with UUID $CLIENT_UUID added."
}

show_summary() {
    SERVER_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')

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
    echo -e "${cyan}└${plain}"

    echo -e "\n${cyan}┌ Access URLs${plain}"
    echo -e "${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Panel (HTTPS)    ${blue}https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}  Panel (Direct)   ${blue}http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}${plain}"
    echo -e "${cyan}│${plain}  Subscription     ${blue}https://${SUB_DOMAIN}:8443/${plain}"
    echo -e "${cyan}└${plain}"

    echo -e "\n${yellow}⚠  Panel is not secure with SSL certificate${plain}"
    echo -e "${yellow}   Configure SSL in panel settings for production${plain}"

    echo -e "\n${green}✓ Ready to use!${plain}\n"
}

main() {
    print_banner
    read_credentials
    read_parameters
    install_base
    install_3xui
    install_caddy
    configure_caddy
    sleep 5
    login_panel
    create_inbound
    add_client
    show_summary
}

main
