#!/usr/bin/env bash

# --- Colors & Variables ---
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && gum style --foreground 196 "ERROR: You must be root to run this script!" && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS" >&2
    exit 1
fi

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# Declare Variables
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

# --- Gum Installation & Helpers ---
ensure_gum() {
    if ! command -v gum &> /dev/null; then
        gum style --foreground 212 "Installing gum..."
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
                ARCH=$(uname -m)
                if [[ "$ARCH" == "x86_64" ]]; then
                    wget -q https://github.com/charmbracelet/gum/releases/download/v0.14.5/gum_0.14.5_linux_amd64.tar.gz
                    tar -xzf gum_0.14.5_linux_amd64.tar.gz
                    mv gum /usr/local/bin/
                    rm gum_0.14.5_linux_amd64.tar.gz
                else
                    echo "Gum auto-install failed for this arch. Please install manually."
                    exit 1
                fi
            ;;
        esac
    fi
}

show_header() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        "3X-UI MANAGEMENT"
    gum style --foreground 240 "Powered by Gum TUI"
}

# --- Basic Functions ---
function LOGD() { gum style --foreground 220 "[DEG] $*"; }
function LOGE() { gum style --foreground 196 "[ERR] $*"; }
function LOGI() { gum style --foreground 46 "[INF] $*"; }

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# --- Status Functions ---
check_status() {
    if [[ $release == "alpine" ]]; then
        if [[ ! -f /etc/init.d/x-ui ]]; then return 2; fi
        if [[ $(rc-service x-ui status | grep -F 'status: started' -c) == 1 ]]; then return 0; else return 1; fi
    else
        if [[ ! -f /etc/systemd/system/x-ui.service ]]; then return 2; fi
        temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ "${temp}" == "running" ]]; then return 0; else return 1; fi
    fi
}

get_status_text() {
    check_status
    case $? in
        0) echo "Running" ;;
        1) echo "Stopped" ;;
        2) echo "Not Installed" ;;
    esac
}

# --- Core Action Functions (Modified for Gum) ---
install() {
    if gum confirm "Download and run the official installer?"; then
        bash <(curl -Ls https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/install.sh)
        if [[ $? == 0 ]]; then
            gum style --foreground 46 "Installation finished. Starting..."
            start 0
        fi
    fi
}

update() {
    if gum confirm "Update all x-ui components to the latest version?"; then
        bash <(curl -Ls https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/update.sh)
        if [[ $? == 0 ]]; then
            gum style --foreground 46 "Update complete."
            start 0
        fi
    fi
}

update_menu() {
    if gum confirm "Update this management menu script?"; then
        wget -O /usr/bin/x-ui https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
        chmod +x /usr/local/x-ui/x-ui.sh
        chmod +x /usr/bin/x-ui
        gum style --foreground 46 "Menu script updated."
        exit 0
    fi
}

uninstall() {
    if gum confirm --affirmative="UNINSTALL" --negative="Cancel" "Are you REALLY sure? This cannot be undone."; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
            rc-update del x-ui
            rm /etc/init.d/x-ui -f
        else
            systemctl stop x-ui
            systemctl disable x-ui
            rm /etc/systemd/system/x-ui.service -f
            systemctl daemon-reload
            systemctl reset-failed
        fi
        rm /etc/x-ui/ -rf
        rm /usr/local/x-ui/ -rf
        gum style --foreground 46 "Uninstalled Successfully."
        exit 0
    fi
}

reset_user() {
    if gum confirm "Reset username and password?"; then
        config_account=$(gum input --placeholder "Username (empty for random)" --value "$config_account")
        [[ -z $config_account ]] && config_account=$(gen_random_string 10)
        
        config_password=$(gum input --placeholder "Password (empty for random)" --password --value "$config_password")
        [[ -z $config_password ]] && config_password=$(gen_random_string 18)

        if gum confirm "Disable 2FA?"; then
            /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor true >/dev/null 2>&1
        else
            /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor false >/dev/null 2>&1
        fi
        
        gum style --foreground 212 "Username: $config_account"
        gum style --foreground 212 "Password: $config_password"
        restart 0
    fi
}

reset_webbasepath() {
    if gum confirm "Reset Web Base Path?"; then
        config_webBasePath=$(gen_random_string 18)
        /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1
        gum style --foreground 46 "New Path: ${config_webBasePath}"
        restart 0
    fi
}

reset_config() {
    if gum confirm "Reset all panel settings to default?"; then
        /usr/local/x-ui/x-ui setting -reset
        restart 0
    fi
}

check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error"
        return
    fi
    gum style --foreground 86 "$info"
    
    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org || curl -s https://4.ident.me)
    
    gum style --foreground 46 "Access URL: http://${server_ip}:${existing_port}${existing_webBasePath}"
}

set_port() {
    port=$(gum input --placeholder "Enter new port (1-65535)" --value "8080")
    if [[ -n "${port}" ]]; then
        /usr/local/x-ui/x-ui setting -port ${port}
        gum style --foreground 46 "Port set to $port. Restarting..."
        restart 0
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        gum style --foreground 220 "Panel is already running."
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui start
        else
            systemctl start x-ui
        fi
        sleep 2
        gum style --foreground 46 "Panel started."
    fi
    if [[ $# == 0 ]]; then gum style --foreground 240 "Press Enter..."; read; fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        gum style --foreground 220 "Panel is already stopped."
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        sleep 2
        gum style --foreground 46 "Panel stopped."
    fi
    if [[ $# == 0 ]]; then gum style --foreground 240 "Press Enter..."; read; fi
}

restart() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui restart
    else
        systemctl restart x-ui
    fi
    sleep 2
    gum style --foreground 46 "Panel restarted."
    if [[ $# == 0 ]]; then gum style --foreground 240 "Press Enter..."; read; fi
}

enable() {
    if [[ $release == "alpine" ]]; then
        rc-update add x-ui
    else
        systemctl enable x-ui
    fi
    gum style --foreground 46 "Autostart enabled."
    gum style --foreground 240 "Press Enter..."; read
}

disable() {
    if [[ $release == "alpine" ]]; then
        rc-update del x-ui
    else
        systemctl disable x-ui
    fi
    gum style --foreground 46 "Autostart disabled."
    gum style --foreground 240 "Press Enter..."; read
}

show_log() {
    if [[ $release == "alpine" ]]; then
        gum choose "Debug Log" "Back" | grep -q "Debug" && grep -F 'x-ui[' /var/log/messages
    else
        CHOICE=$(gum choose "Debug Log" "Clear Logs" "Back")
        case $CHOICE in
            "Debug Log") journalctl -u x-ui -e --no-pager -f -p debug ;;
            "Clear Logs")
                sudo journalctl --rotate
                sudo journalctl --vacuum-time=1s
                gum style --foreground 46 "Logs cleared."
                restart 0
            ;;
        esac
    fi
}

# --- BBR Functions ---
enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        gum style --foreground 220 "BBR already enabled."
        return
    fi
    # Install deps
    case "${release}" in
        ubuntu | debian | armbian) apt-get update && apt-get install -yqq --no-install-recommends ca-certificates ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol) dnf -y update && dnf -y install ca-certificates ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then yum -y update && yum -y install ca-certificates; else dnf -y update && dnf -y install ca-certificates; fi ;;
        arch | manjaro | parch) pacman -Sy --noconfirm ca-certificates ;;
        alpine) apk add ca-certificates ;;
    esac
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p
    gum style --foreground 46 "BBR Enabled."
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        gum style --foreground 220 "BBR is not enabled."
        return
    fi
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
    sysctl -p
    gum style --foreground 46 "BBR Disabled."
}

# --- GeoIP Functions ---
update_geo() {
    CHOICE=$(gum choose "Loyalsoldier" "chocolate4u" "runetfreedom" "All" "Back")
    cd /usr/local/x-ui/bin
    case $CHOICE in
        "Loyalsoldier")
            wget -O geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "Updated."
            restart 0
        ;;
        "chocolate4u")
            wget -O geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
            wget -O geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
            gum style --foreground 46 "Updated."
            restart 0
        ;;
        "runetfreedom")
            wget -O geoip_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "Updated."
            restart 0
        ;;
        "All")
            wget -O geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
            wget -O geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
            wget -O geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
            wget -O geoip_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "All updated."
            restart 0
        ;;
    esac
}

# --- Caddy Management (New) ---
manage_caddy() {
    CADDY_CONFIG="/etc/caddy/Caddyfile"
    
    while true; do
        show_header
        ACTION=$(gum choose \
            "← Back to Menu" \
            "Install Caddy" \
            "Add/Edit Domain" \
            "Edit Caddyfile Manually" \
            "Restart Caddy" \
            "View Caddy Logs" \
            "Uninstall Caddy"
        )

        case $ACTION in
            "← Back to Menu") break ;;
            "Install Caddy")
                if command -v caddy &> /dev/null; then
                    gum style --foreground 220 "Caddy is already installed."
                else
                    if gum confirm "Install Caddy Server?"; then
                        case "${release}" in
                            ubuntu|debian|armbian)
                                apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
                                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
                                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
                                apt update && apt install caddy -y
                            ;;
                            fedora|rhel|almalinux|rocky)
                                dnf install 'dnf-command(copr)' -y
                                dnf copr enable @caddy/caddy -y
                                dnf install caddy -y
                            ;;
                            *)
                                gum style --foreground 196 "Unsupported OS for auto-install."
                            ;;
                        esac
                        gum style --foreground 46 "Installation finished."
                    fi
                fi
            ;;
            "Add/Edit Domain")
                if ! command -v caddy &> /dev/null; then
                    gum style --foreground 196 "Caddy is not installed."
                    continue
                fi
                
                DOMAIN=$(gum input --placeholder "Domain (e.g. panel.example.com)")
                [[ -z "$DOMAIN" ]] && continue
                
                PORT=$(gum input --placeholder "Local Port (e.g. 8080)")
                [[ -z "$PORT" ]] && continue
                
                # Simple append logic
                cat >> "$CADDY_CONFIG" <<EOF
 $DOMAIN {
    reverse_proxy 127.0.0.1:$PORT
}
EOF
                gum style --foreground 46 "Domain added. Restarting Caddy..."
                systemctl restart caddy
            ;;
            "Edit Caddyfile Manually")
                if [[ -f "$CADDY_CONFIG" ]]; then
                    nano "$CADDY_CONFIG"
                    if gum confirm "Restart Caddy to apply changes?"; then
                        systemctl restart caddy
                    fi
                else
                    gum style --foreground 196 "Caddyfile not found."
                fi
            ;;
            "Restart Caddy")
                systemctl restart caddy && gum style --foreground 46 "Restarted" || gum style --foreground 196 "Failed"
            ;;
            "View Caddy Logs")
                journalctl -u caddy -f -n 50
            ;;
            "Uninstall Caddy")
                if gum confirm "Uninstall Caddy?"; then
                    systemctl stop caddy
                    systemctl disable caddy
                    apt remove caddy -y 2>/dev/null || dnf remove caddy -y 2>/dev/null
                    gum style --foreground 46 "Removed."
                fi
            ;;
        esac
        gum style --foreground 240 "Press Enter..."; read
    done
}

# --- Fail2Ban / IP Limit ---
show_banlog() {
    gum style --foreground 86 "Checking ban logs..."
    if [[ -f "/var/log/fail2ban.log" ]]; then
        gum style --foreground 240 "System Fail2ban logs:"
        grep "3x-ipl" /var/log/fail2ban.log | grep -E "Ban|Unban" | tail -n 10 || echo "None found"
    fi
    if [[ -f "${iplimit_banned_log_path}" ]]; then
        gum style --foreground 240 "Custom 3X-UI logs:"
        grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo "None found"
    fi
    gum style --foreground 240 "Press Enter..."; read
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        gum style --foreground 220 "Installing Fail2ban..."
        case "${release}" in
            ubuntu|debian|armbian) apt-get update && apt-get install fail2ban -y ;;
            fedora|rhel|almalinux|rocky) dnf -y install fail2ban ;;
            centos) 
                if [[ "${VERSION_ID}" =~ ^7 ]]; then yum install epel-release -y && yum install fail2ban -y; else dnf install fail2ban -y; fi ;;
            arch|manjaro|parch) pacman -Syu --noconfirm fail2ban ;;
            alpine) apk add fail2ban ;;
        esac
    fi
    
    gum style --foreground 220 "Configuring IP Limit..."
    mkdir -p "${iplimit_banned_log_path%/*}"
    touch "${iplimit_banned_log_path}"
    touch "${iplimit_log_path}"
    
    # Create jail config
    cat > /etc/fail2ban/jail.d/3x-ipl.conf <<EOF
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=30m
EOF
    cat > /etc/fail2ban/filter.d/3x-ipl.conf <<EOF
[Definition]
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
EOF
    cat > /etc/fail2ban/action.d/3x-ipl.conf <<EOF
[INCLUDES]
before = iptables-allports.conf
[Definition]
actionban = <iptables> -I f2b-3x-ipl 1 -s <ip> -j <blocktype>
            echo "\$(date) BAN [IP] = <ip>" >> ${iplimit_banned_log_path}
actionunban = <iptables> -D f2b-3x-ipl -s <ip> -j <blocktype>
              echo "\$(date) UNBAN [IP] = <ip>" >> ${iplimit_banned_log_path}
EOF
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    gum style --foreground 46 "IP Limit configured."
}

iplimit_menu() {
    while true; do
        show_header
        ACTION=$(gum choose \
            "← Back" \
            "Install/Reconfigure IP Limit" \
            "View Ban Logs" \
            "Unban All IPs" \
            "Service Status"
        )
        case $ACTION in
            "← Back") break ;;
            "Install/Reconfigure IP Limit") install_iplimit ;;
            "View Ban Logs") show_banlog ;;
            "Unban All IPs") fail2ban-client reload --restart --unban 3x-ipl && gum style --foreground 46 "Unbanned all." ;;
            "Service Status") systemctl status fail2ban ;;
        esac
        gum style --foreground 240 "Press Enter..."; read
    done
}

# --- SSH Port Forwarding ---
ssh_port_menu() {
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listen=$(/usr/local/x-ui/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    
    ACTION=$(gum choose \
        "← Back" \
        "Set Listen IP (SSH Tunnel)" \
        "Clear Listen IP" \
        "Show Current Command"
    )
    
    case $ACTION in
        "← Back") return ;;
        "Set Listen IP (SSH Tunnel)")
            IP=$(gum input --placeholder "IP (default 127.0.0.1)" --value "127.0.0.1")
            /usr/local/x-ui/x-ui setting -listenIP "$IP"
            gum style --foreground 46 "Listen set to $IP. Restart panel."
            restart 0
        ;;
        "Clear Listen IP")
            /usr/local/x-ui/x-ui setting -listenIP 0.0.0.0
            restart 0
        ;;
        "Show Current Command")
            [[ -z "$existing_listen" || "$existing_listen" == "0.0.0.0" ]] && existing_listen="SERVER_IP"
            gum style --foreground 212 "ssh -L 2222:${existing_listen}:${existing_port} root@YOUR_SERVER_IP"
        ;;
    esac
}

# --- SSL (ACME) ---
ssl_cert_issue() {
    gum style --foreground 220 "Note: This is a simplified SSL issuer. Ensure port 80 is open."
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        gum style --foreground 220 "Installing acme.sh..."
        curl -s https://get.acme.sh | sh
    fi
    DOMAIN=$(gum input --placeholder "Domain Name")
    [[ -z "$DOMAIN" ]] && return
    
    ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --standalone
    if [[ $? -eq 0 ]]; then
        gum style --foreground 46 "Certificate issued!"
        gum style --foreground 240 "Applying to panel..."
        ~/.acme.sh/acme.sh --installcert -d ${DOMAIN} \
            --key-file /root/cert/${domain}/privkey.pem \
            --fullchain-file /root/cert/${domain}/fullchain.pem \
            --reloadcmd "x-ui restart"
    else
        gum style --foreground 196 "Failed to issue certificate."
    fi
}

# --- Speedtest ---
run_speedtest() {
    if ! command -v speedtest &>/dev/null; then
        gum style --foreground 220 "Installing Speedtest..."
        if command -v snap &>/dev/null; then snap install speedtest;
        elif command -v apt &>/dev/null; then curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash && apt install speedtest -y;
        elif command -v dnf &>/dev/null; then curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash && dnf install speedtest -y;
        fi
    fi
    speedtest
}

# --- Main Menu ---
main_menu() {
    ensure_gum
    
    while true; do
        show_header
        STATUS=$(get_status_text)
        
        # Colorize status
        case $STATUS in
            Running) STATUS_COLOR="46" ;; # Green
            Stopped) STATUS_COLOR="220" ;; # Yellow
            *) STATUS_COLOR="196" ;;       # Red
        esac

        CHOICE=$(gum choose \
            "Status: $STATUS" \
            "---" \
            "Install 3X-UI" \
            "Update 3X-UI" \
            "Uninstall 3X-UI" \
            "---" \
            "Start" \
            "Stop" \
            "Restart" \
            "---" \
            "Reset Username & Password" \
            "Reset Web Base Path" \
            "Reset Settings" \
            "Change Port" \
            "View Settings" \
            "---" \
            "Caddy Manager (NEW)" \
            "SSL Certificate Issue (ACME)" \
            "Update Geo Files" \
            "---" \
            "BBR Control" \
            "IP Limit (Fail2ban)" \
            "SSH Port Forwarding" \
            "Speedtest" \
            "Logs" \
            "Exit"
        )

        case $CHOICE in
            "Status: $STATUS") gum style --foreground $STATUS_COLOR "Panel is $STATUS" ;;
            "Install 3X-UI") install ;;
            "Update 3X-UI") update ;;
            "Uninstall 3X-UI") uninstall ;;
            "Start") start 0 ;;
            "Stop") stop 0 ;;
            "Restart") restart 0 ;;
            "Reset Username & Password") reset_user ;;
            "Reset Web Base Path") reset_webbasepath ;;
            "Reset Settings") reset_config ;;
            "Change Port") set_port ;;
            "View Settings") check_config ;;
            "Caddy Manager (NEW)") manage_caddy ;;
            "SSL Certificate Issue (ACME)") ssl_cert_issue ;;
            "Update Geo Files") update_geo ;;
            "BBR Control")
                SUB=$(gum choose "Enable BBR" "Disable BBR" "Back")
                [[ "$SUB" == "Enable BBR" ]] && enable_bbr
                [[ "$SUB" == "Disable BBR" ]] && disable_bbr
            ;;
            "IP Limit (Fail2ban)") iplimit_menu ;;
            "SSH Port Forwarding") ssh_port_menu ;;
            "Speedtest") run_speedtest ;;
            "Logs") show_log ;;
            "Exit") exit 0 ;;
        esac
    done
}

# --- CLI Argument Handler ---
if [[ $# > 0 ]]; then
    case $1 in
        "start") start 0 ;;
        "stop") stop 0 ;;
        "restart") restart 0 ;;
        "status") 
            ensure_gum
            check_status
            case $? in 0) gum style --foreground 46 "Running";; 1) gum style --foreground 220 "Stopped";; 2) gum style --foreground 196 "Not Installed";; esac
        ;;
        "install") install ;;
        "update") update ;;
        *) main_menu ;; # Fallback to GUI for unknown commands
    esac
else
    main_menu
fi
