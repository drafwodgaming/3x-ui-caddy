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

# Install dialog if not present
install_dialog() {
    if ! command -v dialog &> /dev/null; then
        case "${release}" in
            ubuntu | debian | armbian)
                apt-get update >/dev/null 2>&1 && apt-get install -y dialog >/dev/null 2>&1
            ;;
            fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
                dnf install -y dialog >/dev/null 2>&1
            ;;
            centos)
                if [[ "${VERSION_ID}" =~ ^7 ]]; then
                    yum install -y dialog >/dev/null 2>&1
                else
                    dnf install -y dialog >/dev/null 2>&1
                fi
            ;;
            *)
                apt-get update >/dev/null 2>&1 && apt-get install -y dialog >/dev/null 2>&1
            ;;
        esac
    fi
}

read_credentials() {
    exec 3>&1
    values=$(dialog --title "Panel Credentials" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --form "Enter credentials (leave empty to auto-generate):" 12 60 2 \
        "Username:" 1 1 "" 1 15 40 0 \
        "Password:" 2 1 "" 2 15 40 0 \
        2>&1 1>&3)
    exec 3>&-
    
    if [[ $? -ne 0 ]]; then
        clear
        exit 0
    fi
    
    XUI_USERNAME=$(echo "$values" | sed -n 1p)
    XUI_PASSWORD=$(echo "$values" | sed -n 2p)
    
    if [[ -z "$XUI_USERNAME" ]]; then
        XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n 1)
    fi
    if [[ -z "$XUI_PASSWORD" ]]; then
        length=$((20 + RANDOM % 11))
        XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w $length | head -n 1)
    fi
}

ask_caddy() {
    dialog --title "Caddy Configuration" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --yesno "Do you want to use Caddy as a reverse proxy?\n\nThis will allow you to use domains and SSL certificates." 10 60
    
    if [[ $? -eq 0 ]]; then
        USE_CADDY="true"
    else
        USE_CADDY="false"
    fi
}

ask_default_inbound() {
    dialog --title "Default Inbound" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --yesno "Do you want to create a default VLESS Reality inbound?\n\nThis will create an inbound with predefined settings." 10 60
    
    if [[ $? -eq 0 ]]; then
        CREATE_DEFAULT_INBOUND="true"
    else
        CREATE_DEFAULT_INBOUND="false"
    fi
}

read_parameters() {
    exec 3>&1
    
    if [[ "$USE_CADDY" == "true" ]]; then
        values=$(dialog --title "Configuration" \
            --backtitle "3X-UI + CADDY INSTALLER" \
            --form "Enter configuration details:" 14 65 4 \
            "Panel port:"        1 1 "8080" 1 20 40 0 \
            "Subscription port:" 2 1 "2096" 2 20 40 0 \
            "Panel domain:"      3 1 ""     3 20 40 0 \
            "Subscription domain:" 4 1 ""   4 20 40 0 \
            2>&1 1>&3)
        
        exec 3>&-
        
        if [[ $? -ne 0 ]]; then
            clear
            exit 0
        fi
        
        PANEL_PORT=$(echo "$values" | sed -n 1p)
        SUB_PORT=$(echo "$values" | sed -n 2p)
        PANEL_DOMAIN=$(echo "$values" | sed -n 3p)
        SUB_DOMAIN=$(echo "$values" | sed -n 4p)
    else
        values=$(dialog --title "Configuration" \
            --backtitle "3X-UI + CADDY INSTALLER" \
            --form "Enter configuration details:" 12 65 2 \
            "Panel port:"        1 1 "8080" 1 20 40 0 \
            "Subscription port:" 2 1 "2096" 2 20 40 0 \
            2>&1 1>&3)
        
        exec 3>&-
        
        if [[ $? -ne 0 ]]; then
            clear
            exit 0
        fi
        
        PANEL_PORT=$(echo "$values" | sed -n 1p)
        SUB_PORT=$(echo "$values" | sed -n 2p)
    fi
    
    PANEL_PORT=${PANEL_PORT:-8080}
    SUB_PORT=${SUB_PORT:-2096}
}

install_base() {
    dialog --title "Installing Dependencies" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --infobox "Installing base dependencies...\nPlease wait..." 5 50
    
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
    sleep 1
}

install_3xui() {
    (
        echo "10" ; sleep 1
        echo "XXX" ; echo "Fetching latest version..." ; echo "XXX"
        
        cd /usr/local/
        tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [[ ! -n "$tag_version" ]] && echo -e "${red}✗ Failed to fetch version${plain}" && exit 1
        
        echo "30" ; sleep 1
        echo "XXX" ; echo "Downloading 3x-ui ${tag_version}..." ; echo "XXX"
        
        wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz \
            https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        
        [[ $? -ne 0 ]] && echo -e "${red}✗ Download failed${plain}" && exit 1
        
        wget --inet4-only -q -O /usr/bin/x-ui-temp \
            https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
        
        echo "50" ; sleep 1
        echo "XXX" ; echo "Extracting files..." ; echo "XXX"
        
        if [[ -e /usr/local/x-ui/ ]]; then
            systemctl stop x-ui 2>/dev/null || true
            rm /usr/local/x-ui/ -rf
        fi
        
        tar zxf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
        rm x-ui-linux-$(arch).tar.gz -f
        
        echo "70" ; sleep 1
        echo "XXX" ; echo "Setting permissions..." ; echo "XXX"
        
        cd x-ui
        chmod +x x-ui x-ui.sh
        
        if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
            mv bin/xray-linux-$(arch) bin/xray-linux-arm
            chmod +x bin/xray-linux-arm
        fi
        chmod +x x-ui bin/xray-linux-$(arch)
        
        mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
        chmod +x /usr/bin/x-ui
        
        echo "85" ; sleep 1
        echo "XXX" ; echo "Configuring panel..." ; echo "XXX"
        
        config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)
        
        /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
            -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1
        
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui >/dev/null 2>&1
        
        echo "95" ; sleep 1
        echo "XXX" ; echo "Starting service..." ; echo "XXX"
        
        systemctl start x-ui
        sleep 5
        
        /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
        
        echo "100" ; sleep 1
        echo "XXX" ; echo "Installation complete!" ; echo "XXX"
        
    ) | dialog --title "Installing 3X-UI" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --gauge "Starting installation..." 10 60 0
}

install_caddy() {
    (
        echo "10" ; sleep 1
        echo "XXX" ; echo "Adding Caddy repository..." ; echo "XXX"
        
        apt update >/dev/null 2>&1 && apt install -y ca-certificates curl gnupg >/dev/null 2>&1
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null \
            | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
            | tee /etc/apt/sources.list.d/caddy.list >/dev/null
        
        echo "50" ; sleep 1
        echo "XXX" ; echo "Installing Caddy..." ; echo "XXX"
        
        apt update >/dev/null 2>&1
        apt install -y caddy >/dev/null 2>&1
        
        echo "100" ; sleep 1
        echo "XXX" ; echo "Caddy installed successfully!" ; echo "XXX"
        
    ) | dialog --title "Installing Caddy" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --gauge "Starting Caddy installation..." 10 60 0
}

configure_caddy() {
    dialog --title "Configuring Caddy" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --infobox "Configuring reverse proxy...\nPlease wait..." 5 50
    
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
    sleep 2
}

api_login() {
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
        return 0
    else
        return 1
    fi
}

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

create_vless_reality_inbound() {
    REALITY_PORT=443
    REALITY_SNI="www.google.com"
    REALITY_DEST="www.google.com:443"
    CLIENT_EMAIL="user"
    
    CLIENT_UUID=$(generate_uuid)
    if [[ -z "$CLIENT_UUID" ]]; then
        return 1
    fi
    
    if [[ ! "$CLIENT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 1
    fi
    
    generate_reality_keys
    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        return 1
    fi
    
    SHORT_ID=$(openssl rand -hex 8)
    
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
        return 0
    else
        return 1
    fi
}

configure_reality_inbound() {
    (
        echo "10" ; sleep 1
        echo "XXX" ; echo "Authenticating with panel..." ; echo "XXX"
        
        if ! api_login; then
            echo "100"
            echo "XXX" ; echo "Authentication failed!" ; echo "XXX"
            sleep 2
            return 1
        fi
        
        echo "30" ; sleep 1
        echo "XXX" ; echo "Generating UUID..." ; echo "XXX"
        sleep 1
        
        echo "50" ; sleep 1
        echo "XXX" ; echo "Generating Reality keys..." ; echo "XXX"
        sleep 1
        
        echo "70" ; sleep 1
        echo "XXX" ; echo "Creating inbound..." ; echo "XXX"
        
        if create_vless_reality_inbound; then
            echo "100"
            echo "XXX" ; echo "VLESS Reality inbound created!" ; echo "XXX"
            sleep 2
        else
            echo "100"
            echo "XXX" ; echo "Failed to create inbound!" ; echo "XXX"
            sleep 2
            return 1
        fi
        
    ) | dialog --title "Creating VLESS Reality Inbound" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --gauge "Starting inbound creation..." 10 60 0
}

show_summary() {
    sleep 2
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    local summary="╔══════════════════════════════════════════════╗\n"
    summary+="║     INSTALLATION COMPLETED SUCCESSFULLY      ║\n"
    summary+="╚══════════════════════════════════════════════╝\n\n"
    summary+="CREDENTIALS:\n"
    summary+="  Username: ${XUI_USERNAME}\n"
    summary+="  Password: ${XUI_PASSWORD}\n\n"
    summary+="ACCESS URLS:\n"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        summary+="  Panel (HTTPS):\n"
        summary+="    https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}\n\n"
        summary+="  Subscription:\n"
        summary+="    https://${SUB_DOMAIN}:8443/\n"
    else
        summary+="  Panel (Direct):\n"
        summary+="    http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}\n"
    fi
    
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" && -f /root/vless_reality_config.txt ]]; then
        summary+="\n\nVLESS REALITY CONFIG:\n"
        summary+="  Saved to: /root/vless_reality_config.txt\n"
    fi
    
    dialog --title "Installation Complete" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --msgbox "$summary" 20 70
    
    clear
}

main() {
    install_dialog
    
    dialog --title "Welcome" \
        --backtitle "3X-UI + CADDY INSTALLER" \
        --msgbox "Welcome to 3X-UI + Caddy Installer\n\nThis wizard will guide you through the installation process." 10 60
    
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
    
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" ]]; then
        configure_reality_inbound
    fi
    
    show_summary
}

main
