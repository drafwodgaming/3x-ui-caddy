#!/usr/bin/env bash
set -euo pipefail

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly PLAIN='\033[0m'

# Configuration variables
declare XUI_USERNAME=""
declare XUI_PASSWORD=""
declare PANEL_PORT="8080"
declare SUB_PORT="2096"
declare PANEL_DOMAIN=""
declare SUB_DOMAIN=""
declare USE_CADDY="false"
declare SERVER_IP=""

# Temporary files
readonly TMP_LOG="/tmp/3xui_install_$(date +%s).log"
trap 'rm -f "$TMP_LOG"' EXIT

# Utility functions
log_error() {
    echo -e "${RED}✗ Error:${PLAIN} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${PLAIN} $1"
}

log_info() {
    echo -e "${BLUE}ℹ${PLAIN} $1"
}

check_root() {
    [[ $EUID -ne 0 ]] && log_error "Root privileges required" && exit 1
}

detect_os() {
    local release_file
    for release_file in /etc/os-release /usr/lib/os-release; do
        if [[ -f "$release_file" ]]; then
            source "$release_file"
            echo "$ID"
            return 0
        fi
    done
    log_error "Failed to detect OS"
    exit 1
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|x64|amd64) echo 'amd64' ;;
        i*86|x86) echo '386' ;;
        armv8*|armv8|arm64|aarch64) echo 'arm64' ;;
        armv7*|armv7|arm) echo 'armv7' ;;
        armv6*|armv6) echo 'armv6' ;;
        armv5*|armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) log_error "Unsupported architecture: $(uname -m)" && exit 1 ;;
    esac
}

trim_spaces() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

generate_random_string() {
    local length="${1:-10}"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

generate_password() {
    local length=$((20 + RANDOM % 11))
    LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w "$length" | head -n 1
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        return 1
    fi
    return 0
}

get_server_ip() {
    curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
    curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
    curl -s --connect-timeout 5 https://icanhazip.com 2>/dev/null || \
    echo "unknown"
}

# Gum installation
install_gum() {
    command -v gum &>/dev/null && return 0
    
    log_info "Installing gum..."
    local release arch_type
    release=$(detect_os)
    arch_type=$(detect_arch)
    
    case "$release" in
        ubuntu|debian|armbian)
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list
            apt-get update -qq && apt-get install -y -qq gum
            ;;
        fedora|amzn|rhel|almalinux|rocky|ol)
            cat > /etc/yum.repos.d/charm.repo <<EOF
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
            yum install -y -q gum
            ;;
        *)
            if [[ "$arch_type" == "amd64" ]]; then
                local gum_version="0.14.5"
                wget -q "https://github.com/charmbracelet/gum/releases/download/v${gum_version}/gum_${gum_version}_linux_amd64.tar.gz"
                tar -xzf "gum_${gum_version}_linux_amd64.tar.gz"
                mv gum /usr/local/bin/
                rm -f "gum_${gum_version}_linux_amd64.tar.gz"
            else
                log_error "Unsupported OS/architecture for gum installation"
                exit 1
            fi
            ;;
    esac
}

show_welcome() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 60 --margin "1 2" --padding "2 4" \
        '3X-UI + CADDY INSTALLER' \
        '' \
        'Modern TUI Installer' \
        'Version 2.0'
    
    gum style --foreground 86 "Features:"
    gum style --foreground 250 "  • Automatic configuration"
    gum style --foreground 250 "  • SSL/TLS support with Caddy"
    gum style --foreground 250 "  • VLESS Reality inbound creation"
    gum style --foreground 250 "  • Beautiful modern interface"
    gum style --foreground 250 "  • Enhanced error handling"
    
    echo ""
    gum confirm "Ready to start installation?" || exit 0
}

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
    
    while true; do
        PANEL_PORT=$(trim_spaces "$(gum input --placeholder "Panel Port" --value "${PANEL_PORT}")")
        if validate_port "$PANEL_PORT"; then
            break
        fi
        gum style --foreground 196 "❌ Invalid port number (1-65535)"
        sleep 2
    done
    
    while true; do
        SUB_PORT=$(trim_spaces "$(gum input --placeholder "Subscription Port" --value "${SUB_PORT}")")
        if validate_port "$SUB_PORT"; then
            break
        fi
        gum style --foreground 196 "❌ Invalid port number (1-65535)"
        sleep 2
    done
    
    echo ""
    gum style --foreground 86 "⚡ Options:"
    
    if gum confirm "Use Caddy Reverse Proxy (SSL/TLS)?"; then
        USE_CADDY="true"
        echo ""
        gum style --foreground 86 "🌐 Caddy Domain Configuration:"
        
        while true; do
            PANEL_DOMAIN=$(trim_spaces "$(gum input --placeholder "Panel Domain (panel.example.com)" --value "$PANEL_DOMAIN")")
            if [[ -z "$PANEL_DOMAIN" ]]; then
                gum style --foreground 196 "❌ Panel Domain is required when Caddy is enabled!"
                sleep 2
            elif ! validate_domain "$PANEL_DOMAIN"; then
                gum style --foreground 196 "❌ Invalid domain format!"
                sleep 2
            else
                break
            fi
        done
        
        while true; do
            SUB_DOMAIN=$(trim_spaces "$(gum input --placeholder "Subscription Domain (sub.example.com)" --value "$SUB_DOMAIN")")
            if [[ -z "$SUB_DOMAIN" ]]; then
                gum style --foreground 196 "❌ Subscription Domain is required when Caddy is enabled!"
                sleep 2
            elif ! validate_domain "$SUB_DOMAIN"; then
                gum style --foreground 196 "❌ Invalid domain format!"
                sleep 2
            else
                break
            fi
        done
    else
        USE_CADDY="false"
        PANEL_DOMAIN=""
        SUB_DOMAIN=""
    fi
    
    # Generate credentials if empty
    [[ -z "$XUI_USERNAME" ]] && XUI_USERNAME=$(generate_random_string 10)
    [[ -z "$XUI_PASSWORD" ]] && XUI_PASSWORD=$(generate_password)
    
    # Show summary
    echo ""
    gum style --foreground 86 "📊 Configuration Summary:"
    gum style --foreground 250 "  Username: $XUI_USERNAME"
    gum style --foreground 250 "  Password: ${XUI_PASSWORD:0:4}***${XUI_PASSWORD: -4}"
    gum style --foreground 250 "  Panel Port: $PANEL_PORT"
    gum style --foreground 250 "  Subscription Port: $SUB_PORT"
    
    if [[ "$USE_CADDY" == "true" ]]; then
        gum style --foreground 250 "  ✓ Caddy Enabled"
        gum style --foreground 250 "    Panel Domain: $PANEL_DOMAIN"
        gum style --foreground 250 "    Sub Domain: $SUB_DOMAIN"
    fi
    
    echo ""
    gum confirm "Proceed with installation?" || show_config_form
}

execute_with_spinner() {
    local title="$1"
    local command="$2"
    
    eval "$command" > "$TMP_LOG" 2>&1 &
    local pid=$!
    
    gum spin --spinner dot --title "$title" -- bash -c "while kill -0 $pid 2>/dev/null; do sleep 0.5; done"
    
    wait $pid
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        return 0
    else
        echo "Error details:" >&2
        cat "$TMP_LOG" >&2
        return 1
    fi
}

install_base() {
    clear
    gum style --foreground 212 "📦 Installing base dependencies..."
    
    local release
    release=$(detect_os)
    
    local install_cmd
    case "$release" in
        ubuntu|debian|armbian)
            install_cmd="apt-get update -qq && apt-get install -y -qq wget curl tar tzdata sqlite3 jq"
            ;;
        fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol)
            install_cmd="dnf -y -q update && dnf install -y -q wget curl tar tzdata sqlite jq"
            ;;
        centos)
            if [[ "${VERSION_ID:-}" =~ ^7 ]]; then
                install_cmd="yum -y -q update && yum install -y -q wget curl tar tzdata sqlite jq"
            else
                install_cmd="dnf -y -q update && dnf install -y -q wget curl tar tzdata sqlite jq"
            fi
            ;;
        *)
            install_cmd="apt-get update -qq && apt-get install -y -qq wget curl tar tzdata sqlite3 jq"
            ;;
    esac
    
    if execute_with_spinner "Installing packages..." "$install_cmd"; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies"
        exit 1
    fi
    
    sleep 1
}

install_3xui() {
    clear
    gum style --foreground 212 "🚀 Installing 3X-UI..."
    
    local arch_type
    arch_type=$(detect_arch)
    
    local install_cmd
    read -r -d '' install_cmd <<'EOF' || true
tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
[[ -z "$tag_version" ]] && exit 1

cd /usr/local/ || exit 1

wget --inet4-only -q -O "x-ui-linux-ARCH.tar.gz" \
    "https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-ARCH.tar.gz" || exit 1

wget --inet4-only -q -O /usr/bin/x-ui \
    "https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh" || exit 1

[[ -e /usr/local/x-ui/ ]] && systemctl stop x-ui 2>/dev/null && rm -rf /usr/local/x-ui/

tar zxf "x-ui-linux-ARCH.tar.gz" || exit 1
rm -f "x-ui-linux-ARCH.tar.gz"

cd x-ui || exit 1
chmod +x x-ui

if [[ "ARCH" == "armv5" ]] || [[ "ARCH" == "armv6" ]] || [[ "ARCH" == "armv7" ]]; then
    mv bin/xray-linux-ARCH bin/xray-linux-arm
    chmod +x bin/xray-linux-arm
fi

chmod +x bin/xray-linux-ARCH
chmod +x /usr/bin/x-ui

webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)

/usr/local/x-ui/x-ui setting -username "USERNAME" -password "PASSWORD" \
    -port "PORT" -webBasePath "$webBasePath" || exit 1

cp -f x-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable x-ui
systemctl start x-ui

sleep 5

/usr/local/x-ui/x-ui migrate
EOF
    
    install_cmd="${install_cmd//ARCH/$arch_type}"
    install_cmd="${install_cmd//USERNAME/$XUI_USERNAME}"
    install_cmd="${install_cmd//PASSWORD/$XUI_PASSWORD}"
    install_cmd="${install_cmd//PORT/$PANEL_PORT}"
    
    if execute_with_spinner "Installing 3X-UI..." "$install_cmd"; then
        log_success "3X-UI installed successfully"
    else
        log_error "Failed to install 3X-UI"
        exit 1
    fi
    
    sleep 1
}

install_caddy() {
    clear
    gum style --foreground 212 "🔐 Installing Caddy..."
    
    local install_cmd
    read -r -d '' install_cmd <<'EOF' || true
apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg
echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy.list
apt-get update -qq
apt-get install -y -qq caddy
EOF
    
    if execute_with_spinner "Installing Caddy..." "$install_cmd"; then
        log_success "Caddy installed successfully"
    else
        log_error "Failed to install Caddy"
        exit 1
    fi
    
    sleep 1
}

configure_caddy() {
    clear
    gum style --foreground 212 "⚙️  Configuring Caddy..."
    
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
    
    if execute_with_spinner "Configuring Caddy..." "systemctl restart caddy"; then
        log_success "Caddy configured successfully"
    else
        log_error "Failed to configure Caddy"
        exit 1
    fi
    
    sleep 1
}

show_summary() {
    sleep 1
    
    local panel_info actual_port actual_webbase
    panel_info=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null || echo "")
    actual_port=$(echo "$panel_info" | grep -oP 'port: \K\d+' || echo "$PANEL_PORT")
    actual_webbase=$(echo "$panel_info" | grep -oP 'webBasePath: \K\S+' || echo "")
    
    [[ -z "$SERVER_IP" ]] && SERVER_IP=$(get_server_ip)
    
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
            "Panel (HTTPS): https://${PANEL_DOMAIN}:8443${actual_webbase}" \
            "Subscription: https://${SUB_DOMAIN}:8443/"
    else
        gum style --border rounded --padding "0 2" --foreground 250 \
            "Panel (HTTP): http://${SERVER_IP}:${actual_port}${actual_webbase}"
    fi
    
    echo ""
    gum style --foreground 86 "Installation complete! Press any key to exit..."
    read -n 1 -s
    clear
}

main() {
    check_root
    install_gum
    
    SERVER_IP=$(get_server_ip)
    
    show_welcome
    show_config_form
    
    install_base
    install_3xui
    
    if [[ "$USE_CADDY" == "true" ]]; then
        install_caddy
        configure_caddy
    fi
    
    show_summary
}

main "$@"
