#!/usr/bin/env bash
set -e

# Colors
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && exit 1

# Check OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
    version_id=$VERSION_ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
    version_id=$VERSION_ID
else
    echo -e "${red}✗ Failed to detect OS${plain}"
    exit 1
fi

# Architecture Function (Improved to exit on fail)
arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) 
            echo -e "${red}✗ Unsupported architecture: $(uname -m)${plain}"
            exit 1 
            ;;
    esac
}

# Ensure arch is set early
ARCH_TYPE=$(arch)

# Install gum if not present
install_gum() {
    if ! command -v gum &> /dev/null; then
        echo "Installing gum..."
        case "${release}" in
            ubuntu | debian | armbian)
                mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
                apt update && apt install -y gum
            ;;
            fedora | amzn | rhel | almalinux | rocky | ol)
                echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | tee /etc/yum.repos.d/charm.repo
                # Try dnf first, fallback to yum
                if command -v dnf &> /dev/null; then dnf install -y gum; else yum install -y gum; fi
            ;;
            centos)
                if [[ "${version_id}" =~ ^7 ]]; then
                    yum install -y gum
                else
                    dnf install -y gum
                fi
            ;;
            arch | manjaro)
                pacman -Syu --noconfirm gum
            ;;
            *)
                if [[ "$ARCH_TYPE" == "amd64" ]]; then
                    # Fallback binary install
                    wget -q https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_linux_amd64.tar.gz
                    tar -xzf gum_0.14.5_linux_amd64.tar.gz
                    mv gum /usr/local/bin/
                    rm gum_0.14.5_linux_amd64.tar.gz
                else
                    echo -e "${yellow}Gum auto-install failed for $ARCH_TYPE. Trying manual install...${plain}"
                    exit 1
                fi
            ;;
        esac
    fi
}

# Show welcome screen
show_welcome() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 60 --margin "1 2" --padding "2 4" \
        '3X-UI + CADDY INSTALLER' \
        '' \
        'Modern TUI Installer' \
        'Version 2.0 (Optimized)'
    
    gum style --foreground 86 "Features:"
    gum style --foreground 250 "  • Automatic configuration"
    gum style --foreground 250 "  • SSL/TLS support with Caddy"
    gum style --foreground 250 "  • VLESS Reality inbound creation"
    gum style --foreground 250 "  • Improved Architecture Support (ARM)"
    
    echo ""
    gum confirm "Ready to start installation?" || exit 0
}

# Configuration form
show_config_form() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border rounded \
        --align center --width 60 --margin "1 2" --padding "1 2" \
        '⚙️  CONFIGURATION'
    
    echo ""
    gum style --foreground 86 "📋 Credentials (leave empty for auto-generation):"
    XUI_USERNAME=$(gum input --placeholder "Username" --value "$XUI_USERNAME" | xargs)
    XUI_PASSWORD=$(gum input --placeholder "Password" --password --value "$XUI_PASSWORD" | xargs)
    
    echo ""
    gum style --foreground 86 "🔌 Port Configuration:"
    PANEL_PORT=$(gum input --placeholder "Panel Port" --value "${PANEL_PORT:-8080}" | xargs)
    SUB_PORT=$(gum input --placeholder "Subscription Port" --value "${SUB_PORT:-2096}" | xargs)
    
    echo ""
    gum style --foreground 86 "⚡ Options:"
    
    # Ask about Caddy FIRST
    if gum confirm "Use Caddy Reverse Proxy (SSL/TLS)?"; then
        USE_CADDY="true"
        echo ""
        gum style --foreground 86 "🌐 Caddy Domain Configuration:"
        PANEL_DOMAIN=$(gum input --placeholder "Panel Domain (e.g., panel.example.com)" --value "$PANEL_DOMAIN" | xargs)
        SUB_DOMAIN=$(gum input --placeholder "Subscription Domain (e.g., sub.example.com)" --value "$SUB_DOMAIN" | xargs)
        
        if [[ -z "$PANEL_DOMAIN" ]]; then
            gum style --foreground 196 "❌ Panel Domain is required when Caddy is enabled!"
            sleep 2
            show_config_form
            return
        fi
        
        if [[ -z "$SUB_DOMAIN" ]]; then
            gum style --foreground 196 "❌ Subscription Domain is required when Caddy is enabled!"
            sleep 2
            show_config_form
            return
        fi
    else
        USE_CADDY="false"
        PANEL_DOMAIN=""
        SUB_DOMAIN=""
    fi

    if gum confirm "Create Default VLESS Reality Inbound?"; then
        CREATE_DEFAULT_INBOUND="true"
    else
        CREATE_DEFAULT_INBOUND="false"
    fi
    
    # Generate credentials if empty
    if [[ -z "$XUI_USERNAME" ]]; then
        XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n 1)
    fi

    if [[ -z "$XUI_PASSWORD" ]]; then
        length=$((20 + RANDOM % 11))
        XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w $length | head -n 1)
    fi
    
    PANEL_PORT=${PANEL_PORT:-8080}
    SUB_PORT=${SUB_PORT:-2096}
    
    # Summary
    echo ""
    gum style --foreground 86 "📊 Configuration Summary:"
    gum style --foreground 250 "  Username: $XUI_USERNAME"
    gum style --foreground 250 "  Password: ${XUI_PASSWORD:0:4}***${XUI_PASSWORD: -4}"
    gum style --foreground 250 "  Panel Port: $PANEL_PORT"
    gum style --foreground 250 "  Subscription Port: $SUB_PORT"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "  ✓ Caddy Enabled"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "    Panel Domain: $PANEL_DOMAIN"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "    Sub Domain: $SUB_DOMAIN"
    [[ "$CREATE_DEFAULT_INBOUND" == "true" ]] && gum style --foreground 250 "  ✓ VLESS Reality Inbound"
    
    echo ""
    gum confirm "Proceed with installation?" || show_config_form
}

install_base() {
    clear
    gum style --foreground 212 "📦 Installing base dependencies..."
    local log_file="/tmp/install_base.log"
    
    (
        case "${release}" in
            ubuntu | debian | armbian)
                apt-get update > "$log_file" 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >> "$log_file" 2>&1
            ;;
            fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
                dnf -y update > "$log_file" 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
            ;;
            centos)
                if [[ "${version_id}" =~ ^7 ]]; then
                    yum -y update > "$log_file" 2>&1 && yum install -y wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
                else
                    dnf -y update > "$log_file" 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
                fi
            ;;
            arch | manjaro)
                pacman -Syu --noconfirm wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
            ;;
            opensuse-tumbleweed | opensuse-leap)
                zypper refresh > "$log_file" 2>&1 && zypper -q install -y wget curl tar timezone sqlite3 jq >> "$log_file" 2>&1
            ;;
            alpine)
                apk update > "$log_file" 2>&1 && apk add wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
            ;;
            *)
                # Fallback for unknown systems (try apt)
                apt-get update > "$log_file" 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >> "$log_file" 2>&1
            ;;
        esac
        echo "EXIT_CODE:$?" >> "$log_file"
    ) &
    
    local pid=$!
    gum spin --spinner dot --title "Installing packages..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    wait $pid
    
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Dependencies installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install dependencies"
        echo "Check $log_file for details."
        exit 1
    fi
    
    rm -f "$log_file"
    sleep 1
}

install_3xui() {
    clear
    gum style --foreground 212 "🚀 Installing 3X-UI..."
    local log_file="/tmp/install_3xui.log"
    
    (
        echo "Fetching latest version..." > "$log_file"
        # Get version
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [[ ! -n "$tag_version" ]]; then
            echo "EXIT_CODE:1" >> "$log_file"
            echo "Failed to fetch version." >> "$log_file"
            exit 1
        fi

        # Version Validation (From original script)
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"
        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo "EXIT_CODE:1" >> "$log_file"
            echo "Version $tag_version is too old. Min required: v2.3.5" >> "$log_file"
            exit 1
        fi

        echo "Target Version: $tag_version" >> "$log_file"
        
        cd /usr/local/
        
        echo "Downloading 3X-UI ($ARCH_TYPE)..." >> "$log_file"
        wget --inet4-only -q -O /usr/local/x-ui-linux-${ARCH_TYPE}.tar.gz \
            https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-${ARCH_TYPE}.tar.gz
        
        if [[ $? -ne 0 ]]; then
            echo "Download failed" >> "$log_file"
            echo "EXIT_CODE:1" >> "$log_file"
            exit 1
        fi
        
        echo "Downloading x-ui.sh..." >> "$log_file"
        wget --inet4-only -q -O /usr/bin/x-ui-temp \
            https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
        
        if [[ -e /usr/local/x-ui/ ]]; then
            echo "Stopping existing x-ui service..." >> "$log_file"
            systemctl stop x-ui 2>> "$log_file" || true
            rm -rf /usr/local/x-ui/ 2>> "$log_file"
        fi
        
        echo "Extracting files..." >> "$log_file"
        tar zxf x-ui-linux-${ARCH_TYPE}.tar.gz >> "$log_file" 2>&1
        rm x-ui-linux-${ARCH_TYPE}.tar.gz -f
        
        cd x-ui
        chmod +x x-ui x-ui.sh
        
        # FIX: Handle ARM architecture binary renaming (Critical from original script)
        if [[ "$ARCH_TYPE" == "armv5" || "$ARCH_TYPE" == "armv6" || "$ARCH_TYPE" == "armv7" ]]; then
            echo "Adjusting Xray binary for ARM architecture..." >> "$log_file"
            mv bin/xray-linux-${ARCH_TYPE} bin/xray-linux-arm
            chmod +x bin/xray-linux-arm
        fi
        
        chmod +x x-ui bin/xray-linux-${ARCH_TYPE}
        
        mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
        chmod +x /usr/bin/x-ui
        
        echo "Configuring panel..." >> "$log_file"
        config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)
        
        /usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" \
            -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >> "$log_file" 2>&1
        
        cp -f x-ui.service /etc/systemd/system/
        systemctl daemon-reload >> "$log_file" 2>&1
        systemctl enable x-ui >> "$log_file" 2>&1
        systemctl start x-ui >> "$log_file" 2>&1
        
        echo "Waiting for service to start..." >> "$log_file"
        sleep 5
        
        echo "Running migration..." >> "$log_file"
        /usr/local/x-ui/x-ui migrate >> "$log_file" 2>&1
        
        echo "EXIT_CODE:0" >> "$log_file"
    ) &
    
    local pid=$!
    gum spin --spinner dot --title "Installing 3X-UI..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    wait $pid
    
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        tag_version=$(grep "Target Version:" "$log_file" | cut -d: -f2 | tr -d ' ')
        gum style --foreground 82 "✓ 3X-UI ${tag_version} installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install 3X-UI"
        cat "$log_file" | grep -v "EXIT_CODE"
        exit 1
    fi
    
    rm -f "$log_file"
    sleep 1
}

install_caddy() {
    clear
    gum style --foreground 212 "🔐 Installing Caddy..."
    local log_file="/tmp/install_caddy.log"
    
    (
        # Only add repo for Debian/Ubuntu based systems
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" || "${release}" == "armbian" ]]; then
            echo "Adding Caddy repository (Debian/Ubuntu)..." > "$log_file"
            apt install -y debian-keyring debian-archive-keyring apt-transport-https curl >> "$log_file" 2>&1
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg >> "$log_file" 2>&1
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >> "$log_file" 2>&1
            apt update >> "$log_file" 2>&1
            apt install -y caddy >> "$log_file" 2>&1
        elif [[ "${release}" == "fedora" || "${release}" == "rhel" || "${release}" == "almalinux" || "${release}" == "rocky" ]]; then
            echo "Adding Caddy repository (RHEL/CentOS/Fedora)..." > "$log_file"
            dnf install 'dnf-command(copr)' >> "$log_file" 2>&1
            dnf copr enable -y @caddy/caddy >> "$log_file" 2>&1
            dnf install -y caddy >> "$log_file" 2>&1
        else
            echo "Unsupported OS for automatic Caddy repo installation. Trying generic binary..." >> "$log_file"
            # Generic fallback if possible, or just fail
            # For simplicity, we try to install via package manager directly if available
            if command -v apt &> /dev/null; then apt install -y caddy >> "$log_file" 2>&1; 
            elif command -v dnf &> /dev/null; then dnf install -y caddy >> "$log_file" 2>&1;
            elif command -v yum &> /dev/null; then yum install -y caddy >> "$log_file" 2>&1;
            fi
        fi

        if command -v caddy &> /dev/null; then
            echo "EXIT_CODE:0" >> "$log_file"
        else
            echo "EXIT_CODE:1" >> "$log_file"
        fi
    ) &
    
    local pid=$!
    gum spin --spinner dot --title "Installing Caddy..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    wait $pid
    
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Caddy installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install Caddy"
        echo "Check $log_file for details."
        # We don't exit here, just warn, as X-UI is already installed
    fi
    
    rm -f "$log_file"
    sleep 1
}

configure_caddy() {
    clear
    gum style --foreground 212 "⚙️  Configuring Caddy..."
    local log_file="/tmp/configure_caddy.log"
    
    (
        echo "Creating Caddyfile..." > "$log_file"
        # Note: Using internal TLS is safe for testing, but for production users need real certs
        cat > /etc/caddy/Caddyfile <<EOF
 ${PANEL_DOMAIN}:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:${PANEL_PORT}
    # tls internal
}

 ${SUB_DOMAIN}:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:${SUB_PORT}
    # tls internal
}
EOF
        
        echo "Validating Caddyfile..." >> "$log_file"
        caddy validate --config /etc/caddy/Caddyfile >> "$log_file" 2>&1
        
        if [[ $? -eq 0 ]]; then
            echo "Restarting Caddy..." >> "$log_file"
            systemctl restart caddy >> "$log_file" 2>&1
            systemctl enable caddy >> "$log_file" 2>&1
            echo "EXIT_CODE:0" >> "$log_file"
        else
            echo "Validation failed. Check logs." >> "$log_file"
            echo "EXIT_CODE:1" >> "$log_file"
        fi
    ) &
    
    local pid=$!
    gum spin --spinner dot --title "Configuring Caddy..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    wait $pid
    
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Caddy configured successfully"
    else
        gum style --foreground 196 "✗ Failed to configure Caddy"
        cat "$log_file" | grep -v "EXIT_CODE"
    fi
    
    rm -f "$log_file"
    sleep 1
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
    echo "$response" | jq -r '.obj.uuid // empty'
}

generate_reality_keys() {
    local response=$(curl -k -s -b /tmp/xui_cookies.txt -X GET \
        "${PANEL_URL}panel/api/server/getNewX25519Cert" 2>/dev/null)
    REALITY_PRIVATE_KEY=$(echo "$response" | jq -r '.obj.privateKey // empty')
    REALITY_PUBLIC_KEY=$(echo "$response" | jq -r '.obj.publicKey // empty')
}

create_vless_reality_inbound() {
    REALITY_PORT=443
    REALITY_SNI="www.microsoft.com" # A common valid SNI
    REALITY_DEST="www.microsoft.com:443"
    CLIENT_EMAIL="user"
    
    CLIENT_UUID=$(generate_uuid)
    if [[ -z "$CLIENT_UUID" || ! "$CLIENT_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
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
        --arg publickey "$REALITY_PUBLIC_KEY" \
        --arg shortid "$SHORT_ID" \
        --arg remark "VLESS-Reality-Vision" \
        --arg subId "uservlessrealityvision" \
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
                        subId: $subId 
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
                        xver: 0,
                        dest: $dest,
                        serverNames: [$sni],
                        privateKey: $privkey,
                        publicKey: $publickey,
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
    clear
    gum style --foreground 212 "🔑 Creating VLESS Reality Inbound..."
    
    if gum spin --spinner dot --title "Authenticating..." -- api_login; then
        gum style --foreground 82 "✓ Authenticated"
    else
        gum style --foreground 196 "✗ Authentication failed!"
        return 1
    fi
    
    gum spin --spinner dot --title "Generating Inbound..." -- bash -c 'sleep 1'
    
    if create_vless_reality_inbound; then
        gum style --foreground 82 "✓ VLESS Reality inbound created successfully"
        sleep 2
    else
        gum style --foreground 196 "✗ Failed to create inbound"
        sleep 2
        return 1
    fi
}

show_summary() {
    sleep 1
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    clear
    gum style \
        --foreground 82 --border-foreground 82 --border double \
        --align center --width 60 --margin "1 2" --padding "2 4" \
        '✓ INSTALLATION COMPLETED' \
        '' \
        'Successfully Installed'
    
    echo ""
    gum style --foreground 212 "📋 CREDENTIALS"
    gum style --border rounded --padding "0 2" --foreground 250 \
        "Username: $XUI_USERNAME" \
        "Password: $XUI_PASSWORD"
    
    echo ""
    gum style --foreground 212 "🔗 ACCESS URLS"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        gum style --border rounded --padding "0 2" --foreground 250 \
            "Panel (HTTPS): https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}" \
            "Subscription: https://${SUB_DOMAIN}:8443/"
    else
        gum style --border rounded --padding "0 2" --foreground 250 \
            "Panel (HTTP): http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}"
    fi
    
    if [[ "$CREATE_DEFAULT_INBOUND" == "true" && -f /root/vless_reality_config.txt ]]; then
        echo ""
        gum style --foreground 212 "🔐 VLESS REALITY"
        gum style --border rounded --padding "0 2" --foreground 250 \
            "✓ Configuration saved to:" \
            "  /root/vless_reality_config.txt"
    fi
    
    echo ""
    gum style --foreground 86 "Installation complete! Press any key to exit..."
    read -n 1 -s
    clear
}

main() {
    install_gum
    
    # Set default values
    XUI_USERNAME=""
    XUI_PASSWORD=""
    PANEL_PORT="8080"
    SUB_PORT="2096"
    PANEL_DOMAIN=""
    SUB_DOMAIN=""
    USE_CADDY="false"
    CREATE_DEFAULT_INBOUND="false"
    
    show_welcome
    show_config_form
    
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
