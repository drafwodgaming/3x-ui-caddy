#!/usr/bin/env bash
set -e
#№№№№№№№№№№
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
    source /etc/lib/os-release
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
                yum install -y gum
            ;;
            *)
                arch_type=$(arch)
                if [[ "$arch_type" == "amd64" ]]; then
                    wget -q https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_linux_amd64.tar.gz
                    tar -xzf gum_0.14.5_linux_amd64.tar.gz
                    mv gum /usr/local/bin/
                    rm gum_0.14.5_linux_amd64.tar.gz
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
        'Version 1.1'
    
    gum style --foreground 86 "Features:"
    gum style --foreground 250 "  • Automatic configuration"
    gum style --foreground 250 "  • SSL/TLS support with Caddy"
    gum style --foreground 250 "  • VLESS Reality inbound creation"
    gum style --foreground 250 "  • Beautiful modern interface"
    
    echo ""
    gum confirm "Ready to start installation?" || exit 0
}

trim_spaces() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
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
    XUI_USERNAME=$(trim_spaces "$(gum input --placeholder "Username" --value "$XUI_USERNAME")")
    XUI_PASSWORD=$(trim_spaces "$(gum input --placeholder "Password" --password --value "$XUI_PASSWORD")")

    echo ""
    gum style --foreground 86 "🔌 Port Configuration:"
    PANEL_PORT=$(trim_spaces "$(gum input --placeholder "Panel Port" --value "${PANEL_PORT:-8080}")")
    SUB_PORT=$(trim_spaces "$(gum input --placeholder "Subscription Port" --value "${SUB_PORT:-2096}")")
    
    echo ""
    gum style --foreground 86 "⚡ Options:"
    
    # Ask about Caddy FIRST
    if gum confirm "Use Caddy Reverse Proxy (SSL/TLS)?"; then
        USE_CADDY="true"
        echo ""
        gum style --foreground 86 "🌐 Caddy Domain Configuration:"
        PANEL_DOMAIN=$(trim_spaces "$(gum input --placeholder "Panel Domain (panel.example.com)" --value "$PANEL_DOMAIN")")
        SUB_DOMAIN=$(trim_spaces "$(gum input --placeholder "Subscription Domain (e.g., sub.example.com)" --value "$SUB_DOMAIN")")

        # Validate domains IMMEDIATELY
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
    
    # Ask about VLESS Reality inbound
    echo ""
    if gum confirm "Create default VLESS Reality inbound?"; then
        CREATE_INBOUND="true"
        echo ""
        gum style --foreground 86 "🔐 VLESS Reality Configuration:"
        INBOUND_PORT=$(trim_spaces "$(gum input --placeholder "Inbound Port (e.g., 443)" --value "${INBOUND_PORT:-443}")")
        REALITY_DEST=$(trim_spaces "$(gum input --placeholder "Reality Dest (e.g., google.com:443)" --value "${REALITY_DEST:-google.com:443}")")
        REALITY_SNI=$(trim_spaces "$(gum input --placeholder "Reality SNI (e.g., google.com)" --value "${REALITY_SNI:-google.com}")")
        
        # Validate inbound configuration
        if [[ -z "$INBOUND_PORT" ]]; then
            gum style --foreground 196 "❌ Inbound Port is required!"
            sleep 2
            show_config_form
            return
        fi
        
        if [[ -z "$REALITY_DEST" ]]; then
            gum style --foreground 196 "❌ Reality Dest is required!"
            sleep 2
            show_config_form
            return
        fi
        
        if [[ -z "$REALITY_SNI" ]]; then
            gum style --foreground 196 "❌ Reality SNI is required!"
            sleep 2
            show_config_form
            return
        fi
    else
        CREATE_INBOUND="false"
        INBOUND_PORT=""
        REALITY_DEST=""
        REALITY_SNI=""
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
    
    # Show summary and confirm
    echo ""
    gum style --foreground 86 "📊 Configuration Summary:"
    gum style --foreground 250 "  Username: $XUI_USERNAME"
    gum style --foreground 250 "  Password: ${XUI_PASSWORD:0:4}***${XUI_PASSWORD: -4}"
    gum style --foreground 250 "  Panel Port: $PANEL_PORT"
    gum style --foreground 250 "  Subscription Port: $SUB_PORT"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "  ✓ Caddy Enabled"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "    Panel Domain: $PANEL_DOMAIN"
    [[ "$USE_CADDY" == "true" ]] && gum style --foreground 250 "    Sub Domain: $SUB_DOMAIN"
    [[ "$CREATE_INBOUND" == "true" ]] && gum style --foreground 250 "  ✓ VLESS Reality Inbound"
    [[ "$CREATE_INBOUND" == "true" ]] && gum style --foreground 250 "    Port: $INBOUND_PORT"
    [[ "$CREATE_INBOUND" == "true" ]] && gum style --foreground 250 "    Dest: $REALITY_DEST"
    [[ "$CREATE_INBOUND" == "true" ]] && gum style --foreground 250 "    SNI: $REALITY_SNI"
    
    echo ""
    gum confirm "Proceed with installation?" || show_config_form
}

install_base() {
    clear
    gum style --foreground 212 "📦 Installing base dependencies..."
    local log_file="/tmp/install_base.log"
    
    # Run the installation in background while showing spinner
    (
        case "${release}" in
            ubuntu | debian | armbian)
                apt-get update > "$log_file" 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >> "$log_file" 2>&1
            ;;
            fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
                dnf -y update > "$log_file" 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
            ;;
            centos)
                if [[ "${VERSION_ID}" =~ ^7 ]]; then
                    yum -y update > "$log_file" 2>&1 && yum install -y wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
                else
                    dnf -y update > "$log_file" 2>&1 && dnf install -y -q wget curl tar tzdata sqlite jq >> "$log_file" 2>&1
                fi
            ;;
            *)
                apt-get update > "$log_file" 2>&1 && apt-get install -y -q wget curl tar tzdata sqlite3 jq >> "$log_file" 2>&1
            ;;
        esac
        echo "EXIT_CODE:$?" >> "$log_file"
    ) &
    
    # Show spinner while installation is running
    local pid=$!
    gum spin --spinner dot --title "Installing packages..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    
    # Check if installation was successful
    wait $pid
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Dependencies installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install dependencies"
        echo "Error details:"
        cat "$log_file" | grep -v "EXIT_CODE"
        exit 1
    fi
    
    rm -f "$log_file"
    sleep 1
}

install_3xui() {
    clear
    gum style --foreground 212 "🚀 Installing 3X-UI..."
    local log_file="/tmp/install_3xui.log"
    
    # Fetch latest version
    (
        echo "Fetching latest version..." > "$log_file"
        tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        [[ ! -n "$tag_version" ]] && echo "EXIT_CODE:1" >> "$log_file" && exit 1
        echo "Version: $tag_version" >> "$log_file"
        
        cd /usr/local/
        
        echo "Downloading 3X-UI..." >> "$log_file"
        wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz \
            https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        
        if [[ $? -ne 0 ]]; then
            echo "Download failed" >> "$log_file"
            echo "EXIT_CODE:1" >> "$log_file"
            exit 1
        fi
        
        echo "Downloading x-ui.sh..." >> "$log_file"
        wget --inet4-only -q -O /usr/bin/x-ui-temp \
            https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
        
        if [[ -e /usr/local/x-ui/ ]]; then
            echo "Stopping existing x-ui service..." >> "$log_file"
            systemctl stop x-ui 2>> "$log_file" || true
            rm -rf /usr/local/x-ui/ 2>> "$log_file"
        fi
        
        echo "Extracting files..." >> "$log_file"
        tar zxf x-ui-linux-$(arch).tar.gz >> "$log_file" 2>&1
        rm x-ui-linux-$(arch).tar.gz -f
        
        cd x-ui
        chmod +x x-ui x-ui.sh
        
        if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
            echo "Adjusting for ARM architecture..." >> "$log_file"
            mv bin/xray-linux-$(arch) bin/xray-linux-arm
            chmod +x bin/xray-linux-arm
        fi
        
        chmod +x x-ui bin/xray-linux-$(arch)
        
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
    
    # Show spinner while installation is running
    local pid=$!
    gum spin --spinner dot --title "Installing 3X-UI..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    
    # Check if installation was successful
    wait $pid
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        tag_version=$(grep "Version:" "$log_file" | cut -d: -f2 | tr -d ' ')
        gum style --foreground 82 "✓ 3X-UI ${tag_version} installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install 3X-UI"
        echo "Error details:"
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
    
    # Run the installation in background while showing spinner
    (
        echo "Adding Caddy repository..." > "$log_file"
        apt update >> "$log_file" 2>&1 && apt install -y ca-certificates curl gnupg >> "$log_file" 2>&1
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>> "$log_file" \
            | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>> "$log_file"
        echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
            | tee /etc/apt/sources.list.d/caddy.list >> "$log_file" 2>&1
        apt update >> "$log_file" 2>&1
        
        echo "Installing Caddy..." >> "$log_file"
        apt install -y caddy >> "$log_file" 2>&1
        
        if [[ $? -eq 0 ]]; then
            echo "EXIT_CODE:0" >> "$log_file"
        else
            echo "EXIT_CODE:1" >> "$log_file"
        fi
    ) &
    
    # Show spinner while installation is running
    local pid=$!
    gum spin --spinner dot --title "Installing Caddy..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    
    # Check if installation was successful
    wait $pid
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Caddy installed successfully"
    else
        gum style --foreground 196 "✗ Failed to install Caddy"
        echo "Error details:"
        cat "$log_file" | grep -v "EXIT_CODE"
        exit 1
    fi
    
    rm -f "$log_file"
    sleep 1
}

configure_caddy() {
    clear
    gum style --foreground 212 "⚙️  Configuring Caddy..."
    local log_file="/tmp/configure_caddy.log"
    
    # Run the configuration in background while showing spinner
    (
        echo "Creating Caddyfile..." > "$log_file"
        cat > /etc/caddy/Caddyfile <<EOF
$PANEL_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$PANEL_PORT
    tls internal
}

$SUB_DOMAIN:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:$SUB_PORT
    tls internal
}
EOF
        
        echo "Restarting Caddy..." >> "$log_file"
        systemctl restart caddy >> "$log_file" 2>&1
        
        if [[ $? -eq 0 ]]; then
            echo "EXIT_CODE:0" >> "$log_file"
        else
            echo "EXIT_CODE:1" >> "$log_file"
        fi
    ) &
    
    # Show spinner while configuration is running
    local pid=$!
    gum spin --spinner dot --title "Configuring Caddy..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    
    # Check if configuration was successful
    wait $pid
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        gum style --foreground 82 "✓ Caddy configured successfully"
    else
        gum style --foreground 196 "✗ Failed to configure Caddy"
        echo "Error details:"
        cat "$log_file" | grep -v "EXIT_CODE"
        exit 1
    fi
    
    rm -f "$log_file"
    sleep 1
}

create_vless_inbound() {
    clear
    gum style --foreground 212 "🔐 Creating VLESS Reality Inbound..."
    local log_file="/tmp/create_inbound.log"
    
    # Get panel configuration
    echo "========================================" > "$log_file"
    echo "VLESS REALITY INBOUND CREATION LOG" >> "$log_file"
    echo "========================================" >> "$log_file"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
    echo "" >> "$log_file"
    
    echo "[STEP 1] Getting panel configuration..." >> "$log_file"
    PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>&1)
    echo "Panel info output:" >> "$log_file"
    echo "$PANEL_INFO" >> "$log_file"
    echo "" >> "$log_file"
    
    ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
    ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
    
    echo "Extracted values:" >> "$log_file"
    echo "  - Actual Port: $ACTUAL_PORT" >> "$log_file"
    echo "  - Web Base Path: $ACTUAL_WEBBASE" >> "$log_file"
    echo "" >> "$log_file"
    
    # Generate keys and certificates
    (
        echo "[STEP 2] Generating Reality keys..." >> "$log_file"
        
        # Generate UUID for client
        CLIENT_UUID=$(cat /proc/sys/kernel/random/uuid)
        echo "  ✓ Generated Client UUID: $CLIENT_UUID" >> "$log_file"
        echo "" >> "$log_file"
        
# Generate X25519 keys for Reality (API way)
echo "[STEP 3] Generating X25519 keypair via API..." >> "$log_file"

X25519_RESPONSE=$(curl -k -s -b "$COOKIE_FILE" \
  "https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}panel/api/server/getNewX25519Cert")

echo "X25519 API response:" >> "$log_file"
echo "$X25519_RESPONSE" | jq '.' >> "$log_file"
echo "" >> "$log_file"

PRIVATE_KEY=$(echo "$X25519_RESPONSE" | jq -r '.obj.privateKey')
PUBLIC_KEY=$(echo "$X25519_RESPONSE" | jq -r '.obj.publicKey')

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" || "$PRIVATE_KEY" == "null" ]]; then
    echo "✗ Failed to generate X25519 keys" >> "$log_file"
    echo "EXIT_CODE:1" >> "$log_file"
    exit 1
fi

echo "Extracted keys:" >> "$log_file"
echo "  - Private Key: $PRIVATE_KEY" >> "$log_file"
echo "  - Public Key: $PUBLIC_KEY" >> "$log_file"
echo "" >> "$log_file"

        
        # Generate short IDs
        echo "[STEP 4] Generating Short ID..." >> "$log_file"
        SHORT_ID=$(openssl rand -hex 8)
        echo "  ✓ Generated Short ID: $SHORT_ID" >> "$log_file"
        echo "" >> "$log_file"
        
        # Wait for panel to be ready
        echo "[STEP 5] Waiting for panel to be ready (3 seconds)..." >> "$log_file"
        sleep 3
        echo "  ✓ Wait complete" >> "$log_file"
        echo "" >> "$log_file"
        
        # Construct URLs
        echo "[STEP 6] Constructing API URLs..." >> "$log_file"
        if [[ "$USE_CADDY" == "true" ]]; then
            LOGIN_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}login"
            API_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}panel/api/inbounds/add"
            echo "  Mode: HTTPS (via Caddy)" >> "$log_file"
        else
            LOGIN_URL="http://127.0.0.1:${ACTUAL_PORT}${ACTUAL_WEBBASE}login"
            API_URL="http://127.0.0.1:${ACTUAL_PORT}${ACTUAL_WEBBASE}panel/api/inbounds/add"
            echo "  Mode: HTTP (direct)" >> "$log_file"
        fi
        echo "  - Login URL: $LOGIN_URL" >> "$log_file"
        echo "  - API URL: $API_URL" >> "$log_file"
        echo "" >> "$log_file"
        
        # Login to get session cookie
        echo "[STEP 7] Authenticating to panel..." >> "$log_file"
        COOKIE_FILE="/tmp/x-ui-cookie.txt"
        
        LOGIN_PAYLOAD="{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}"
        echo "Login payload:" >> "$log_file"
        echo "$LOGIN_PAYLOAD" >> "$log_file"
        echo "" >> "$log_file"
        
        echo "Executing login request..." >> "$log_file"
        LOGIN_RESPONSE=$(curl -k -s -c "$COOKIE_FILE" -X POST "$LOGIN_URL" \
            -H "Content-Type: application/json" \
            -d "$LOGIN_PAYLOAD" 2>&1)
        
        LOGIN_HTTP_CODE=$(curl -k -s -c "$COOKIE_FILE" -X POST "$LOGIN_URL" \
            -H "Content-Type: application/json" \
            -d "$LOGIN_PAYLOAD" -w "%{http_code}" -o /dev/null 2>&1)
        
        echo "Login HTTP Status Code: $LOGIN_HTTP_CODE" >> "$log_file"
        echo "Login Response Body:" >> "$log_file"
        echo "$LOGIN_RESPONSE" | jq '.' 2>/dev/null || echo "$LOGIN_RESPONSE" >> "$log_file"
        echo "" >> "$log_file"
        
        echo "Cookie file contents:" >> "$log_file"
        if [[ -f "$COOKIE_FILE" ]]; then
            cat "$COOKIE_FILE" >> "$log_file"
        else
            echo "  ✗ Cookie file not created!" >> "$log_file"
        fi
        echo "" >> "$log_file"
        
        LOGIN_SUCCESS=$(echo "$LOGIN_RESPONSE" | jq -r '.success' 2>/dev/null)
        echo "Login success status: $LOGIN_SUCCESS" >> "$log_file"
        echo "" >> "$log_file"
        
        if [[ "$LOGIN_SUCCESS" != "true" ]]; then
            echo "✗ LOGIN FAILED!" >> "$log_file"
            echo "Reason: $(echo "$LOGIN_RESPONSE" | jq -r '.msg' 2>/dev/null || echo 'Unknown')" >> "$log_file"
            echo "EXIT_CODE:1" >> "$log_file"
            exit 1
        fi
        
        echo "  ✓ Authentication successful!" >> "$log_file"
        echo "" >> "$log_file"
        
        # Create inbound configuration
        echo "[STEP 8] Preparing inbound configuration..." >> "$log_file"
        echo "Configuration parameters:" >> "$log_file"
        echo "  - Port: $INBOUND_PORT" >> "$log_file"
        echo "  - Protocol: vless" >> "$log_file"
        echo "  - Security: reality" >> "$log_file"
        echo "  - Flow: xtls-rprx-vision" >> "$log_file"
        echo "  - Client Email: default@reality" >> "$log_file"
        echo "  - Reality Dest: $REALITY_DEST" >> "$log_file"
        echo "  - Reality SNI: $REALITY_SNI" >> "$log_file"
        echo "  - Fingerprint: chrome" >> "$log_file"
        echo "" >> "$log_file"
        
        INBOUND_JSON=$(cat <<EOF
{
  "enable": true,
  "remark": "VLESS Reality",
  "listen": "",
  "port": ${INBOUND_PORT},
  "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"${CLIENT_UUID}\",\"flow\":\"xtls-rprx-vision\",\"email\":\"default@reality\"}],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"xver\":0,\"dest\":\"${REALITY_DEST}\",\"serverNames\":[\"${REALITY_SNI}\"],\"privateKey\":\"${PRIVATE_KEY}\",\"minClient\":\"\",\"maxClient\":\"\",\"maxTimediff\":0,\"shortIds\":[\"${SHORT_ID}\"],\"settings\":{\"publicKey\":\"${PUBLIC_KEY}\",\"fingerprint\":\"chrome\",\"serverName\":\"${REALITY_SNI}\",\"spiderX\":\"/\"}}\"",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"metadataOnly\":false,\"routeOnly\":false}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}
EOF
)
        
        echo "Full Inbound JSON payload:" >> "$log_file"
        echo "$INBOUND_JSON" | jq '.' 2>/dev/null || echo "$INBOUND_JSON" >> "$log_file"
        echo "" >> "$log_file"
        
        echo "[STEP 9] Sending inbound creation request..." >> "$log_file"
        echo "Executing POST request to: $API_URL" >> "$log_file"
        echo "" >> "$log_file"
        
        INBOUND_RESPONSE=$(curl -k -s -b "$COOKIE_FILE" -X POST "$API_URL" \
            -H "Content-Type: application/json" \
            -d "$INBOUND_JSON" 2>&1)
        
        INBOUND_HTTP_CODE=$(curl -k -s -b "$COOKIE_FILE" -X POST "$API_URL" \
            -H "Content-Type: application/json" \
            -d "$INBOUND_JSON" -w "%{http_code}" -o /dev/null 2>&1)
        
        echo "Inbound Creation HTTP Status Code: $INBOUND_HTTP_CODE" >> "$log_file"
        echo "Inbound Creation Response Body:" >> "$log_file"
        echo "$INBOUND_RESPONSE" | jq '.' 2>/dev/null || echo "$INBOUND_RESPONSE" >> "$log_file"
        echo "" >> "$log_file"
        
        INBOUND_SUCCESS=$(echo "$INBOUND_RESPONSE" | jq -r '.success' 2>/dev/null)
        echo "Inbound creation success status: $INBOUND_SUCCESS" >> "$log_file"
        echo "" >> "$log_file"
        
        if [[ "$INBOUND_SUCCESS" == "true" ]]; then
            echo "[STEP 10] ✓ INBOUND CREATED SUCCESSFULLY!" >> "$log_file"
            echo "" >> "$log_file"
            echo "========================================" >> "$log_file"
            echo "FINAL CONFIGURATION SUMMARY" >> "$log_file"
            echo "========================================" >> "$log_file"
            echo "Client UUID: $CLIENT_UUID" >> "$log_file"
            echo "Public Key: $PUBLIC_KEY" >> "$log_file"
            echo "Short ID: $SHORT_ID" >> "$log_file"
            echo "Port: $INBOUND_PORT" >> "$log_file"
            echo "SNI: $REALITY_SNI" >> "$log_file"
            echo "Dest: $REALITY_DEST" >> "$log_file"
            echo "========================================" >> "$log_file"
            echo "" >> "$log_file"
            
            echo "CLIENT_UUID:$CLIENT_UUID" >> "$log_file"
            echo "PUBLIC_KEY:$PUBLIC_KEY" >> "$log_file"
            echo "SHORT_ID:$SHORT_ID" >> "$log_file"
            echo "EXIT_CODE:0" >> "$log_file"
        else
            echo "[STEP 10] ✗ INBOUND CREATION FAILED!" >> "$log_file"
            echo "Error message: $(echo "$INBOUND_RESPONSE" | jq -r '.msg' 2>/dev/null || echo 'Unknown error')" >> "$log_file"
            echo "Full error response:" >> "$log_file"
            echo "$INBOUND_RESPONSE" >> "$log_file"
            echo "" >> "$log_file"
            echo "EXIT_CODE:1" >> "$log_file"
        fi
        
        echo "Cleaning up cookie file..." >> "$log_file"
        rm -f "$COOKIE_FILE"
        echo "  ✓ Cleanup complete" >> "$log_file"
        echo "" >> "$log_file"
        echo "========================================" >> "$log_file"
        echo "LOG END: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
        echo "========================================" >> "$log_file"
    ) &
    
    # Show spinner while creating inbound
    local pid=$!
    gum spin --spinner dot --title "Creating VLESS Reality inbound..." -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 1; done"
    
    # Check if creation was successful
    wait $pid
    local exit_code=$(tail -n 1 "$log_file" | grep -o 'EXIT_CODE:[0-9]*' | cut -d: -f2)
    
    if [[ "$exit_code" == "0" ]]; then
        CLIENT_UUID=$(grep "CLIENT_UUID:" "$log_file" | cut -d: -f2-)
        PUBLIC_KEY=$(grep "PUBLIC_KEY:" "$log_file" | cut -d: -f2-)
        SHORT_ID=$(grep "SHORT_ID:" "$log_file" | cut -d: -f2-)
        gum style --foreground 82 "✓ VLESS Reality inbound created successfully"
        echo ""
        gum style --foreground 86 "📄 Full log saved to: $log_file"
    else
        gum style --foreground 196 "✗ Failed to create VLESS Reality inbound"
        echo ""
        gum style --foreground 196 "📄 Full error log:"
        echo ""
        cat "$log_file"
    fi
    
    echo ""
    gum style --foreground 86 "Press any key to continue..."
    read -n 1 -s
    sleep 1
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
    
    if [[ "$CREATE_INBOUND" == "true" && -n "$CLIENT_UUID" ]]; then
        echo ""
        gum style --foreground 212 "🔐 VLESS REALITY CONFIGURATION"
        gum style --border rounded --padding "0 2" --foreground 250 \
            "Client UUID: $CLIENT_UUID" \
            "Public Key: $PUBLIC_KEY" \
            "Short ID: $SHORT_ID" \
            "Port: $INBOUND_PORT" \
            "SNI: $REALITY_SNI" \
            "Dest: $REALITY_DEST"
        
        echo ""
        gum style --foreground 86 "VLESS URI:"
        VLESS_URI="vless://${CLIENT_UUID}@${SERVER_IP}:${INBOUND_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${REALITY_SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#VLESS-Reality"
        gum style --border rounded --padding "0 2" --foreground 250 "$VLESS_URI"
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
    CREATE_INBOUND="false"
    INBOUND_PORT="443"
    REALITY_DEST="google.com:443"
    REALITY_SNI="google.com"
    CLIENT_UUID=""
    PUBLIC_KEY=""
    SHORT_ID=""
    
    show_welcome
    show_config_form

    for var in XUI_USERNAME XUI_PASSWORD PANEL_PORT SUB_PORT PANEL_DOMAIN SUB_DOMAIN INBOUND_PORT REALITY_DEST REALITY_SNI; do
        eval "$var=\"\$(trim_spaces \"\${$var}\")\""
    done

    
    install_base
    install_3xui
    
    if [[ "$USE_CADDY" == "true" ]]; then
        install_caddy
        configure_caddy
    fi
    
    if [[ "$CREATE_INBOUND" == "true" ]]; then
        create_vless_inbound
    fi
    
    show_summary
}

main
