#!/usr/bin/env bash
set -e
#
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
        'Version 1.0'
    
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
    
    show_welcome
    show_config_form

    for var in XUI_USERNAME XUI_PASSWORD PANEL_PORT SUB_PORT PANEL_DOMAIN SUB_DOMAIN; do
        declare "$var=$(trim "${!var}")"
    done


    
    install_base
    install_3xui
    
    if [[ "$USE_CADDY" == "true" ]]; then
        install_caddy
        configure_caddy
    fi
    
    show_summary
}

main
