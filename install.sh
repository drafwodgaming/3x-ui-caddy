#!/usr/bin/env bash
set -e
########################
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

# Show configuration form
show_config_form() {
    while true; do
        exec 3>&1
        selection=$(dialog \
            --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
            --title "┤ 3X-UI + CADDY INSTALLER ├" \
            --colors \
            --ok-label "Install" \
            --cancel-label "Exit" \
            --extra-button \
            --extra-label "Toggle Options" \
            --form "\n\Z4✦ Configuration Settings ✦\Zn\n\nUse arrows to navigate, TAB to switch fields" \
            22 78 10 \
            "\Z1┌─ Credentials ──────────────────────────────────────┐\Zn" 1  1 "" 1  1 0  0 \
            "  Username (empty = auto):"                            2  3 "$XUI_USERNAME" 2  30 40 0 \
            "  Password (empty = auto):"                            3  3 "$XUI_PASSWORD" 3  30 40 0 \
            "\Z1└────────────────────────────────────────────────────┘\Zn" 4  1 "" 4  1 0  0 \
            "" 5 1 "" 5 1 0 0 \
            "\Z1┌─ Ports ────────────────────────────────────────────┐\Zn" 6  1 "" 6  1 0  0 \
            "  Panel Port:"                                          7  3 "${PANEL_PORT:-8080}" 7  30 40 0 \
            "  Subscription Port:"                                   8  3 "${SUB_PORT:-2096}" 8  30 40 0 \
            "\Z1└────────────────────────────────────────────────────┘\Zn" 9  1 "" 9  1 0  0 \
            "" 10 1 "" 10 1 0 0 \
            "\Z1┌─ Caddy Domains (if enabled) ──────────────────────┐\Zn" 11 1 "" 11 1 0  0 \
            "  Panel Domain:"                                        12 3 "$PANEL_DOMAIN" 12 30 40 0 \
            "  Subscription Domain:"                                 13 3 "$SUB_DOMAIN" 13 30 40 0 \
            "\Z1└────────────────────────────────────────────────────┘\Zn" 14 1 "" 14 1 0  0 \
            "" 15 1 "" 15 1 0 0 \
            "\Z2┌─ Options ──────────────────────────────────────────┐\Zn" 16 1 "" 16 1 0  0 \
            "  ${USE_CADDY_SYMBOL} Use Caddy Reverse Proxy (SSL/TLS)" 17 3 "" 17 30 0 0 \
            "  ${CREATE_INBOUND_SYMBOL} Create Default VLESS Reality Inbound" 18 3 "" 18 30 0 0 \
            "\Z2└────────────────────────────────────────────────────┘\Zn" 19 1 "" 19 1 0  0 \
            2>&1 1>&3)
        
        exit_status=$?
        exec 3>&-
        
        # Handle button press
        case $exit_status in
            0)  # OK button (Install)
                # Parse form data
                XUI_USERNAME=$(echo "$selection" | sed -n 1p)
                XUI_PASSWORD=$(echo "$selection" | sed -n 2p)
                PANEL_PORT=$(echo "$selection" | sed -n 3p)
                SUB_PORT=$(echo "$selection" | sed -n 4p)
                PANEL_DOMAIN=$(echo "$selection" | sed -n 5p)
                SUB_DOMAIN=$(echo "$selection" | sed -n 6p)
                
                # Validate
                if [[ "$USE_CADDY" == "true" && -z "$PANEL_DOMAIN" ]]; then
                    dialog --title "⚠ Validation Error" \
                        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
                        --colors \
                        --msgbox "\n\Z1Panel Domain is required when Caddy is enabled!\Zn" 8 50
                    continue
                fi
                
                if [[ "$USE_CADDY" == "true" && -z "$SUB_DOMAIN" ]]; then
                    dialog --title "⚠ Validation Error" \
                        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
                        --colors \
                        --msgbox "\n\Z1Subscription Domain is required when Caddy is enabled!\Zn" 8 50
                    continue
                fi
                
                # Generate credentials if empty
                if [[ -z "$XUI_USERNAME" ]]; then
                    XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n 1)
                fi
                if [[ -z "$XUI_PASSWORD" ]]; then
                    length=$((20 + RANDOM % 11))
                    XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w $length | head -n 1)
                fi
                
                # Set defaults
                PANEL_PORT=${PANEL_PORT:-8080}
                SUB_PORT=${SUB_PORT:-2096}
                
                return 0
                ;;
            1)  # Cancel button (Exit)
                clear
                exit 0
                ;;
            3)  # Extra button (Toggle Options)
                show_options_menu
                ;;
            255) # ESC key
                clear
                exit 0
                ;;
        esac
    done
}

# Toggle options menu
show_options_menu() {
    exec 3>&1
    selection=$(dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Toggle Options ├" \
        --colors \
        --checklist "\n\Z4Select features to enable:\Zn\n\nUse SPACE to toggle, ENTER to confirm" \
        15 68 2 \
        1 "Use Caddy Reverse Proxy (SSL/TLS + Domains)" $([ "$USE_CADDY" == "true" ] && echo "on" || echo "off") \
        2 "Create Default VLESS Reality Inbound" $([ "$CREATE_DEFAULT_INBOUND" == "true" ] && echo "on" || echo "off") \
        2>&1 1>&3)
    
    exit_status=$?
    exec 3>&-
    
    if [ $exit_status -eq 0 ]; then
        # Update options based on selection
        if echo "$selection" | grep -q "1"; then
            USE_CADDY="true"
            USE_CADDY_SYMBOL="[\Z2✓\Zn]"
        else
            USE_CADDY="false"
            USE_CADDY_SYMBOL="[ ]"
        fi
        
        if echo "$selection" | grep -q "2"; then
            CREATE_DEFAULT_INBOUND="true"
            CREATE_INBOUND_SYMBOL="[\Z2✓\Zn]"
        else
            CREATE_DEFAULT_INBOUND="false"
            CREATE_INBOUND_SYMBOL="[ ]"
        fi
    fi
}

install_base() {
    (
        echo "10"
        echo "XXX"
        echo "\n\Z4Installing base dependencies...\Zn"
        echo "XXX"
        
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
        
        echo "100"
        echo "XXX"
        echo "\n\Z2✓ Dependencies installed successfully\Zn"
        echo "XXX"
        sleep 1
        
    ) | dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Installation Progress ├" \
        --colors \
        --gauge "\n\Z4Preparing system...\Zn" 10 70 0
}

install_3xui() {
    (
        echo "5"
        echo "XXX"
        echo "\n\Z4Fetching latest 3X-UI version...\Zn"
        echo "XXX"
        sleep 1
        
        cd /usr/local/
        tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [[ ! -n "$tag_version" ]] && echo -e "${red}✗ Failed to fetch version${plain}" && exit 1
        
        echo "15"
        echo "XXX"
        echo "\n\Z4Downloading 3X-UI ${tag_version}...\Zn"
        echo "XXX"
        
        wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz \
            https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        
        [[ $? -ne 0 ]] && echo -e "${red}✗ Download failed${plain}" && exit 1
        
        wget --inet4-only -q -O /usr/bin/x-ui-temp \
            https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
        
        echo "40"
        echo "XXX"
        echo "\n\Z4Extracting files...\Zn"
        echo "XXX"
        
        if [[ -e /usr/local/x-ui/ ]]; then
            systemctl stop x-ui 2>/dev/null || true
            rm /usr/local/x-ui/ -rf
        fi
        
        tar zxf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
        rm x-ui-linux-$(arch).tar.gz -f
        
        echo "60"
        echo "XXX"
        echo "\n\Z4Configuring permissions...\Zn"
        echo "XXX"
        
        cd x-ui
        chmod +x x-ui x-ui.sh
        
        if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
            mv bin/xray-linux-$(arch) bin/xray-linux-arm
            chmod +x bin/xray-linux-arm
        fi
        chmod +x x-ui bin/xray-linux-$(arch)
        
        mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
        chmod +x /usr/bin/x-ui
        
        echo "75"
        echo "XXX"
        echo "\n\Z4Applying configuration...\Zn"
        echo "XXX"
        
        config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)
        
        /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
            -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1
        
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable x-ui >/dev/null 2>&1
        
        echo "90"
        echo "XXX"
        echo "\n\Z4Starting 3X-UI service...\Zn"
        echo "XXX"
        
        systemctl start x-ui
        sleep 5
        
        /usr/local/x-ui/x-ui migrate >/dev/null 2>&1
        
        echo "100"
        echo "XXX"
        echo "\n\Z2✓ 3X-UI ${tag_version} installed successfully!\Zn"
        echo "XXX"
        sleep 1
        
    ) | dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Installing 3X-UI ├" \
        --colors \
        --gauge "\n\Z4Starting installation...\Zn" 10 70 0
}

install_caddy() {
    (
        echo "10"
        echo "XXX"
        echo "\n\Z4Adding Caddy repository...\Zn"
        echo "XXX"
        
        apt update >/dev/null 2>&1 && apt install -y ca-certificates curl gnupg >/dev/null 2>&1
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null \
            | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
            | tee /etc/apt/sources.list.d/caddy.list >/dev/null
        
        echo "40"
        echo "XXX"
        echo "\n\Z4Updating package list...\Zn"
        echo "XXX"
        
        apt update >/dev/null 2>&1
        
        echo "60"
        echo "XXX"
        echo "\n\Z4Installing Caddy...\Zn"
        echo "XXX"
        
        apt install -y caddy >/dev/null 2>&1
        
        echo "100"
        echo "XXX"
        echo "\n\Z2✓ Caddy installed successfully!\Zn"
        echo "XXX"
        sleep 1
        
    ) | dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Installing Caddy ├" \
        --colors \
        --gauge "\n\Z4Starting Caddy installation...\Zn" 10 70 0
}

configure_caddy() {
    (
        echo "30"
        echo "XXX"
        echo "\n\Z4Creating Caddyfile configuration...\Zn"
        echo "XXX"
        
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
        
        echo "70"
        echo "XXX"
        echo "\n\Z4Restarting Caddy service...\Zn"
        echo "XXX"
        
        systemctl restart caddy
        sleep 2
        
        echo "100"
        echo "XXX"
        echo "\n\Z2✓ Caddy configured successfully!\Zn"
        echo "XXX"
        sleep 1
        
    ) | dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Configuring Caddy ├" \
        --colors \
        --gauge "\n\Z4Configuring reverse proxy...\Zn" 10 70 0
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
        echo "10"
        echo "XXX"
        echo "\n\Z4Authenticating with panel API...\Zn"
        echo "XXX"
        sleep 1
        
        if ! api_login; then
            echo "100"
            echo "XXX"
            echo "\n\Z1✗ Authentication failed!\Zn"
            echo "XXX"
            sleep 2
            return 1
        fi
        
        echo "30"
        echo "XXX"
        echo "\n\Z4Generating client UUID...\Zn"
        echo "XXX"
        sleep 1
        
        echo "50"
        echo "XXX"
        echo "\n\Z4Generating Reality keys...\Zn"
        echo "XXX"
        sleep 1
        
        echo "70"
        echo "XXX"
        echo "\n\Z4Creating VLESS Reality inbound...\Zn"
        echo "XXX"
        
        if create_vless_reality_inbound; then
            echo "100"
            echo "XXX"
            echo "\n\Z2✓ VLESS Reality inbound created successfully!\Zn"
            echo "XXX"
            sleep 2
        else
            echo "100"
            echo "XXX"
            echo "\n\Z1✗ Failed to create inbound!\Zn"
            echo "XXX"
            sleep 2
            return 1
        fi
        
    ) | dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Creating VLESS Reality Inbound ├" \
        --colors \
        --gauge "\n\Z4Setting up default inbound...\Zn" 10 70 0
}

show_summary() {
    sleep 1
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    local summary="\n\Z2╔══════════════════════════════════════════════════════════╗\Zn\n"
    summary+="\Z2║          ✓ INSTALLATION COMPLETED SUCCESSFULLY          ║\Zn\n"
    summary+="\Z2╚══════════════════════════════════════════════════════════╝\Zn\n\n"
    
    summary+="\Z4┌─ Credentials ─────────────────────────────────────────┐\Zn\n"
    summary+="│                                                       │\n"
    summary+="│  \Z1Username:\Zn \Z3${XUI_USERNAME}\Zn\n"
    summary+="│  \Z1Password:\Zn \Z3${XUI_PASSWORD}\Zn\n"
    summary+="│                                                       │\n"
    summary+="\Z4└───────────────────────────────────────────────────────┘\Zn\n\n"
    
    summary+="\Z4┌─ Access URLs ─────────────────────────────────────────┐\Zn\n"
    summary+="│                                                       │\n"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        summary+="│  \Z1Panel (HTTPS):\Zn                                     │\n"
        summary+="│    \Z6https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}\Zn\n"
        summary+="│                                                       │\n"
        summary+="│  \Z1Subscription:\Zn                                      │\n"
        summary+="│    \Z6https://${SUB_DOMAIN}:8443/\Zn\n"
    else
        summary+="│  \Z1Panel (HTTP):\Zn                                      │\n"
        summary+="│    \Z6http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}\Zn\n"
    fi
    
    summary+="│                                                       │\n"
    summary+="\Z4└───────────────────────────────────────────────────────┘\Zn\n"
    
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" && -f /root/vless_reality_config.txt ]]; then
        summary+="\n\Z4┌─ VLESS Reality Configuration ─────────────────────────┐\Zn\n"
        summary+="│                                                       │\n"
        summary+="│  \Z2✓ Configuration saved to:\Zn                          │\n"
        summary+="│    \Z6/root/vless_reality_config.txt\Zn\n"
        summary+="│                                                       │\n"
        summary+="\Z4└───────────────────────────────────────────────────────┘\Zn\n"
    fi
    
    dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Installation Complete ├" \
        --colors \
        --ok-label "Finish" \
        --msgbox "$summary" 24 70
    
    clear
}

main() {
    install_dialog
    
    # Set default values
    XUI_USERNAME=""
    XUI_PASSWORD=""
    PANEL_PORT="8080"
    SUB_PORT="2096"
    PANEL_DOMAIN=""
    SUB_DOMAIN=""
    USE_CADDY="false"
    CREATE_DEFAULT_INBOUND="false"
    USE_CADDY_SYMBOL="[ ]"
    CREATE_INBOUND_SYMBOL="[ ]"
    
    # Show welcome screen
    dialog \
        --backtitle "╔═══════════════════════════════════════════════════════════════════╗" \
        --title "┤ Welcome ├" \
        --colors \
        --msgbox "\n\Z4✦ 3X-UI + Caddy Installer ✦\Zn\n\nThis wizard will guide you through the installation\nof 3X-UI with optional Caddy reverse proxy.\n\n\Z2Features:\Zn\n• Automatic configuration\n• SSL/TLS support with Caddy\n• VLESS Reality inbound creation\n• User-friendly interface\n\n\Z1Press OK to continue...\Zn" 18 65
    
    # Show configuration form
    show_config_form
    
    # Start installation
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
