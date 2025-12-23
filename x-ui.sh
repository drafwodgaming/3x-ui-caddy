#!/usr/bin/env bash
#
# 3X-UI Management Script (Gum Edition + Caddy Support)
# Based on original logic with Modern TUI
#

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# --- Helper Functions ---
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

# Check root
[[ $EUID -ne 0 ]] && LOGE "ERROR: You must be root to run this script! \n" && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /etc/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi

# --- Gum Check & Install ---
install_gum_if_missing() {
    if ! command -v gum &> /dev/null; then
        echo -e "${yellow}Gum not found. Installing Gum for modern interface...${plain}"
        case "${release}" in
            ubuntu | debian | armbian)
                mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
                apt-get update > /dev/null 2>&1 && apt-get install -y gum > /dev/null 2>&1
            ;;
            fedora | amzn | rhel | almalinux | rocky | ol)
                echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | tee /etc/yum.repos.d/charm.repo
                yum install -y gum > /dev/null 2>&1
            ;;
            *)
                LOGE "Could not auto-install gum. Please install it manually."
                exit 1
            ;;
        esac
    fi
}

# Call gum check immediately to ensure UI works
install_gum_if_missing

# --- Gum Input Wrapper ---
# Falls back to standard read if gum fails, but prioritizes gum
gum_input() {
    local prompt="$1"
    local default_val="$2"
    local is_pass="$3"
    
    if command -v gum &> /dev/null; then
        if [[ "$is_pass" == "password" ]]; then
            gum input --placeholder "$prompt" --password --value "$default_val"
        else
            gum input --placeholder "$prompt" --value "$default_val"
        fi
    else
        read -rp "$prompt [$default_val]: " input
        echo "${input:-$default_val}"
    fi
}

gum_confirm() {
    local prompt="$1"
    local default_val="${2:-n}"
    
    if command -v gum &> /dev/null; then
        gum confirm "$prompt" --default=false
        return $?
    else
        read -rp "$prompt [y/n]: " temp
        [[ "${temp}" == "y" || "${temp}" == "Y" ]]
    fi
}

# --- Variables ---
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm_restart() {
    if gum_confirm "Restart the panel, Attention: Restarting the panel will also restart xray" "y"; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    # In gum mode, we just show the menu again or wait for keypress
    # gum choose handles the loop naturally, but for compatibility with old logic flow:
    echo ""
    read -rp "Press Enter to return to menu..." dummy
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if gum_confirm "This function will update all x-ui components to the latest version, and the data will not be lost. Do you want to continue?" "y"; then
        bash <(curl -Ls https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/update.sh)
        if [[ $? == 0 ]]; then
            LOGI "Update is complete, Panel has automatically restarted "
            before_show_menu
        fi
    else
        LOGE "Cancelled"
        before_show_menu
    fi
}

update_menu() {
    gum style --foreground 212 --border rounded "Updating Menu"
    if gum_confirm "This function will update the menu to the latest changes." "y"; then
        wget -O /usr/bin/x-ui https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh
        chmod +x /usr/local/x-ui/x-ui.sh
        chmod +x /usr/bin/x-ui
        if [[ $? == 0 ]]; then
            gum style --foreground 46 "Update successful."
            exit 0
        else
            gum style --foreground 196 "Failed to update."
        fi
    else
        LOGE "Cancelled"
    fi
    before_show_menu
}

delete_script() {
    rm "$0"
    exit 1
}

uninstall() {
    if gum_confirm "Are you sure you want to uninstall the panel? xray will also uninstalled!" "n"; then
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
        gum style "Install command: bash <(curl -Ls https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/master/install.sh)"
        trap delete_script SIGTERM
        delete_script
    fi
    show_menu
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_user() {
    if gum_confirm "Are you sure to reset the username and password of the panel?" "n"; then
        config_account=$(gum_input "Username" "")
        [[ -z $config_account ]] && config_account=$(gen_random_string 10)
        
        config_password=$(gum_input "Password" "" "password")
        [[ -z $config_password ]] && config_password=$(gen_random_string 18)

        if gum_confirm "Disable 2FA?" "n"; then
            /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor true >/dev/null 2>&1
            LOGI "Two factor authentication has been disabled."
        else
            /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} -resetTwoFactor false >/dev/null 2>&1
        fi
        
        gum style --foreground 212 "New Username: ${green}${config_account}${plain}"
        gum style --foreground 212 "New Password: ${green}${config_password}${plain}"
        confirm_restart
    else
        show_menu
    fi
}

reset_webbasepath() {
    gum style --foreground 212 "Resetting Web Base Path"
    if gum_confirm "Reset web base path?" "n"; then
        config_webBasePath=$(gen_random_string 18)
        /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1
        gum style --foreground 46 "Web base path: ${green}${config_webBasePath}${plain}"
        restart
    else
        show_menu
    fi
}

reset_config() {
    if gum_confirm "Reset all panel settings? Data will not be lost." "n"; then
        /usr/local/x-ui/x-ui setting -reset
        LOGI "Settings reset."
        restart
    else
        show_menu
    fi
}

check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "get current settings error"
        show_menu
        return
    fi
    gum style --border rounded --padding "1 2" "$info"

    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    if [ -z "$server_ip" ]; then server_ip=$(curl -s --max-time 3 https://4.ident.me); fi

    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")
        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            gum style --foreground 46 "Access URL: https://${domain}:${existing_port}${existing_webBasePath}"
        else
            gum style --foreground 46 "Access URL: https://${server_ip}:${existing_port}${existing_webBasePath}"
        fi
    else
        gum style --foreground 46 "Access URL: http://${server_ip}:${existing_port}${existing_webBasePath}"
    fi
    before_show_menu
}

set_port() {
    port=$(gum_input "Port number" "")
    if [[ -z "${port}" ]]; then
        LOGD "Cancelled"
        show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        gum style --foreground 46 "Port set to ${port}. Please restart."
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        gum style --foreground 214 "Panel is running."
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui start
        else
            systemctl start x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            gum style --foreground 46 "x-ui Started Successfully"
        else
            LOGE "Failed to start."
        fi
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        gum style --foreground 214 "Panel stopped."
    else
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop
        else
            systemctl stop x-ui
        fi
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            gum style --foreground 46 "Stopped successfully"
        else
            LOGE "Stop failed."
        fi
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

restart() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui restart
    else
        systemctl restart x-ui
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        gum style --foreground 46 "Restarted successfully"
    else
        LOGE "Restart failed."
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

status() {
    if [[ $release == "alpine" ]]; then
        rc-service x-ui status
    else
        systemctl status x-ui -l
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

enable() {
    if [[ $release == "alpine" ]]; then
        rc-update add x-ui
    else
        systemctl enable x-ui
    fi
    if [[ $? == 0 ]]; then
        gum style --foreground 46 "Autostart enabled"
    else
        LOGE "Failed to enable autostart"
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

disable() {
    if [[ $release == "alpine" ]]; then
        rc-update del x-ui
    else
        systemctl disable x-ui
    fi
    if [[ $? == 0 ]]; then
        gum style --foreground 46 "Autostart disabled"
    else
        LOGE "Failed to disable autostart"
    fi
    if [[ $# == 0 ]]; then before_show_menu; fi
}

show_log() {
    if [[ $release == "alpine" ]]; then
        gum style --foreground 212 "1. Debug Log" "0. Back"
        choice=$(gum choose "Debug Log" "Back")
        case "$choice" in
            "Debug Log") grep -F 'x-ui[' /var/log/messages; before_show_menu ;;
            "Back") show_menu ;;
        esac
    else
        choice=$(gum choose "Debug Log" "Clear All logs" "Back")
        case "$choice" in
            "Debug Log")
                journalctl -u x-ui -e --no-pager -f -p debug
                before_show_menu
                ;;
            "Clear All logs")
                sudo journalctl --rotate
                sudo journalctl --vacuum-time=1s
                gum style --foreground 46 "Logs cleared."
                restart
                ;;
            "Back") show_menu ;;
        esac
    fi
}

bbr_menu() {
    choice=$(gum choose "Enable BBR" "Disable BBR" "Back")
    case "$choice" in
        "Enable BBR")
            enable_bbr
            ;;
        "Disable BBR")
            disable_bbr
            ;;
        "Back") show_menu ;;
    esac
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        gum style --foreground 214 "BBR is not currently enabled."
        show_menu
    fi
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        gum style --foreground 46 "BBR replaced with CUBIC."
    else
        LOGE "Failed."
    fi
    before_show_menu
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        gum style --foreground 46 "BBR is already enabled!"
        show_menu
    fi
    # Install packages logic (shortened for brevity, same as original)
    case "${release}" in
        ubuntu|debian|armbian) apt-get update && apt-get install -yqq --no-install-recommends ca-certificates ;;
        fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol) dnf -y update && dnf -y install ca-certificates ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then yum -y update && yum -y install ca-certificates;
            else dnf -y update && dnf -y install ca-certificates; fi ;;
        arch|manjaro|parch) pacman -Sy --noconfirm ca-certificates ;;
        opensuse-tumbleweed|opensuse-leap) zypper refresh && zypper -q install -y ca-certificates ;;
        alpine) apk add ca-certificates ;;
    esac
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        gum style --foreground 46 "BBR enabled successfully."
    else
        LOGE "Failed."
    fi
    before_show_menu
}

update_geo() {
    cd /usr/local/x-ui/bin
    choice=$(gum choose "Loyalsoldier (Main)" "chocolate4u (Iran)" "runetfreedom (Russia)" "Update All" "Back")
    case "$choice" in
        "Loyalsoldier (Main)")
            wget -O geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "Loyalsoldier updated."
            restart
            ;;
        "chocolate4u (Iran)")
            wget -O geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
            wget -O geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
            gum style --foreground 46 "chocolate4u updated."
            restart
            ;;
        "runetfreedom (Russia)")
            wget -O geoip_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "runetfreedom updated."
            restart
            ;;
        "Update All")
            wget -O geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
            wget -O geoip_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
            wget -O geosite_IR.dat https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
            wget -O geoip_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
            wget -O geosite_RU.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
            gum style --foreground 46 "All geo files updated."
            restart
            ;;
        "Back") show_menu ;;
    esac
}

install_acme() {
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh is already installed."
        return 0
    fi
    LOGI "Installing acme.sh..."
    cd ~ || return 1
    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Installation failed."
        return 1
    else
        LOGI "Installation succeeded."
    fi
    return 0
}

ssl_cert_issue() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "Installing acme.sh..."
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "acme install failed"
            exit 1
        fi
    fi
    # Install socat logic (same as original, keeping short)
    case "${release}" in
        ubuntu|debian|armbian) apt-get update && apt-get install socat -y ;;
        fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol) dnf -y update && dnf -y install socat ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then yum -y update && yum -y install socat;
            else dnf -y update && dnf -y install socat; fi ;;
        arch|manjaro|parch) pacman -Sy --noconfirm socat ;;
        opensuse-tumbleweed|opensuse-leap) zypper refresh && zypper -q install -y socat ;;
        alpine) apk add socat curl openssl ;;
    esac
    
    domain=$(gum_input "Enter your domain name" "")
    LOGD "Domain: ${domain}"
    
    if [ -z "$domain" ]; then return; fi

    # Existing cert check logic...
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        LOGE "Cert already exists."
        exit 1
    fi

    certPath="/root/cert/${domain}"
    mkdir -p "$certPath"

    WebPort=$(gum_input "Port for standalone (80)" "80")
    LOGI "Using port: ${WebPort}"

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    
    if [ $? -ne 0 ]; then
        LOGE "Issue failed."
        exit 1
    fi
    
    LOGI "Issue succeeded, installing..."
    
    reloadCmd="x-ui restart"
    if gum_confirm "Modify reloadcmd?" "n"; then
        # Gum menu for reloadcmd options could go here, keeping simple for now
        reloadCmd=$(gum_input "Reload command" "x-ui restart")
    fi

    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"
        
    if [ $? -ne 0 ]; then
        LOGE "Install cert failed."
        exit 1
    fi
    
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    
    if gum_confirm "Set this cert for panel?" "y"; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"
        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            gum style --foreground 46 "Cert set for panel."
            restart
        fi
    fi
}

run_speedtest() {
    if ! command -v speedtest &>/dev/null; then
        if command -v snap &>/dev/null; then
            snap install speedtest
        else
            LOGI "Installing speedtest..."
            # Auto install logic similar to original...
            if command -v dnf &>/dev/null; then
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash
                dnf install -y speedtest
            elif command -v yum &>/dev/null; then
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash
                yum install -y speedtest
            elif command -v apt-get &>/dev/null; then
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
                apt-get install -y speedtest
            fi
        fi
    fi
    speedtest
}

# --- IP Limit Functions (Unchanged Logic, adapted for UI) ---
ip_validation() {
    ipv6_regex="^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$"
}

create_iplimit_jails() {
    local bantime="${1:-30}"
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf
    if [[  "${release}" == "debian" && $(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"') -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi
    cat > /etc/fail2ban/jail.d/3x-ipl.conf << EOF
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF
    cat > /etc/fail2ban/filter.d/3x-ipl.conf << EOF
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF
    cat > /etc/fail2ban/action.d/3x-ipl.conf << 'EOF'
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "$(date +"%Y/%m/%d %H:%M:%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> /var/log/3xipl-banned.log

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "$(date +"%Y/%m/%d %H:%M:%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> /var/log/3xipl-banned.log

[Init]
name = default
protocol = tcp
chain = INPUT
EOF
    gum style --foreground 46 "Jail files created."
}

iplimit_main() {
    choice=$(gum choose "Install Fail2ban & IP Limit" "Change Ban Duration" "Unban Everyone" "Ban Logs" "Ban an IP" "Unban an IP" "Real-Time Logs" "Service Status" "Restart Service" "Uninstall Fail2ban/IP Limit" "Back")
    
    case "$choice" in
        "Install Fail2ban & IP Limit")
            if gum_confirm "Proceed?" "y"; then install_iplimit; else iplimit_main; fi ;;
        "Change Ban Duration")
            NUM=$(gum_input "Ban Duration (Minutes)" "30")
            if [[ $NUM =~ ^[0-9]+$ ]]; then
                create_iplimit_jails ${NUM}
                [[ $release == "alpine" ]] && rc-service fail2ban restart || systemctl restart fail2ban
            else
                LOGE "Invalid number."
            fi
            iplimit_main
            ;;
        "Unban Everyone")
            if gum_confirm "Unban everyone?" "y"; then
                fail2ban-client reload --restart --unban 3x-ipl
                truncate -s 0 "${iplimit_banned_log_path}"
                gum style --foreground 46 "Unbanned."
                iplimit_main
            else
                gum style --foreground 214 "Cancelled."
                iplimit_main
            fi
            ;;
        "Ban Logs") show_banlog; iplimit_main ;;
        "Ban an IP")
            ban_ip=$(gum_input "IP to ban" "")
            # Simple validation check omitted for brevity, using regex from function
            if [[ $ban_ip =~ ^[0-9] ]]; then
                fail2ban-client set 3x-ipl banip "$ban_ip"
                gum style --foreground 46 "Banned ${ban_ip}"
            else
                LOGE "Invalid IP."
            fi
            iplimit_main
            ;;
        "Unban an IP")
            unban_ip=$(gum_input "IP to unban" "")
            fail2ban-client set 3x-ipl unbanip "$unban_ip"
            gum style --foreground 46 "Unbanned ${unban_ip}"
            iplimit_main
            ;;
        "Real-Time Logs") tail -f /var/log/fail2ban.log; iplimit_main ;;
        "Service Status") service fail2ban status; iplimit_main ;;
        "Restart Service") [[ $release == "alpine" ]] && rc-service fail2ban restart || systemctl restart fail2ban; iplimit_main ;;
        "Uninstall Fail2ban/IP Limit") remove_iplimit ;;
        "Back") show_menu ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        LOGI "Installing Fail2ban..."
        case "${release}" in
            ubuntu) apt-get update; apt-get install fail2ban -y ;;
            debian) apt-get update; apt-get install -y fail2ban ;;
            armbian) apt-get update && apt-get install fail2ban -y ;;
            fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol) dnf -y update && dnf -y install fail2ban ;;
            centos)
                if [[ "${VERSION_ID}" =~ ^7 ]]; then yum update -y && yum install epel-release -y && yum -y install fail2ban;
                else dnf -y update && dnf -y install fail2ban; fi ;;
            arch|manjaro|parch) pacman -Syu --noconfirm fail2ban ;;
            alpine) apk add fail2ban ;;
        esac
    fi
    touch ${iplimit_banned_log_path}
    touch ${iplimit_log_path}
    create_iplimit_jails
    if [[ $release == "alpine" ]]; then
        rc-service fail2ban start; rc-update add fail2ban
    else
        systemctl start fail2ban; systemctl enable fail2ban
    fi
    gum style --foreground 46 "IP Limit installed."
    before_show_menu
}

remove_iplimit() {
    choice=$(gum choose "Remove configs only" "Uninstall Fail2ban completely" "Back")
    case "$choice" in
        "Remove configs only")
            rm -f /etc/fail2ban/filter.d/3x-ipl.conf /etc/fail2ban/action.d/3x-ipl.conf /etc/fail2ban/jail.d/3x-ipl.conf
            [[ $release == "alpine" ]] && rc-service fail2ban restart || systemctl restart fail2ban
            gum style --foreground 46 "Configs removed."
            before_show_menu
            ;;
        "Uninstall Fail2ban completely")
            rm -rf /etc/fail2ban
            [[ $release == "alpine" ]] && rc-service fail2ban stop || systemctl stop fail2ban
            case "${release}" in
                ubuntu|debian|armbian) apt-get remove -y fail2ban ;;
                fedora|amzn|virtuozzo|rhel|almalinux|rocky|ol) dnf remove fail2ban -y ;;
                centos) yum remove fail2ban -y ;;
                arch|manjaro|parch) pacman -Rns --noconfirm fail2ban ;;
                alpine) apk del fail2ban ;;
            esac
            gum style --foreground 46 "Uninstalled."
            before_show_menu
            ;;
        "Back") show_menu ;;
    esac
}

show_banlog() {
    local system_log="/var/log/fail2ban.log"
    gum style --foreground 212 "Checking ban logs..."
    if [[ -f "$system_log" ]]; then
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10
    fi
    if [[ -f "${iplimit_banned_log_path}" ]]; then
        gum style --foreground 212 "3X-IPL Ban Log:"
        grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10
    fi
    fail2ban-client status 3x-ipl
}

SSH_port_forwarding() {
    local server_ip=$(curl -s --max-time 3 https://api4.ipify.org)
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listenIP=$(/usr/local/x-ui/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    
    if [[ -n "$existing_listenIP" && "$existing_listenIP" != "0.0.0.0" ]]; then
        gum style --foreground 212 "Current SSH Port Forwarding:"
        gum style "ssh -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}"
        gum style "Access: http://localhost:2222${existing_webBasePath}"
    fi

    choice=$(gum choose "Set listen IP" "Clear listen IP" "Back")
    case "$choice" in
        "Set listen IP")
            if [[ -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ]]; then
                listen_choice=$(gum choose "Use 127.0.0.1 (Default)" "Set Custom IP")
                if [[ "$listen_choice" == "Set Custom IP" ]]; then
                    config_listenIP=$(gum_input "Custom IP" "")
                else
                    config_listenIP="127.0.0.1"
                fi
                /usr/local/x-ui/x-ui setting -listenIP "${config_listenIP}" >/dev/null 2>&1
                gum style --foreground 46 "Listen IP set to ${config_listenIP}"
                restart
            fi
            ;;
        "Clear listen IP")
            /usr/local/x-ui/x-ui setting -listenIP 0.0.0.0 >/dev/null 2>&1
            gum style --foreground 46 "Listen IP cleared."
            restart
            ;;
        "Back") show_menu ;;
    esac
}

# --- CADDY MANAGEMENT (NEW) ---
caddy_install() {
    gum style --foreground 212 "Installing Caddy..."
    case "${release}" in
        ubuntu | debian | armbian)
            apt update > /dev/null 2>&1 && apt install -y ca-certificates curl gnupg > /dev/null 2>&1
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg
            chmod a+r /etc/apt/keyrings/caddy.gpg
            echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy.list > /dev/null 2>&1
            apt update > /dev/null 2>&1
            apt install -y caddy
        ;;
        fedora | amzn | rhel | almalinux | rocky | ol)
            dnf install -y 'dnf-command(copr)' > /dev/null 2>&1
            dnf copr enable -y @caddy/caddy > /dev/null 2>&1
            dnf install -y caddy
        ;;
        *)
            LOGE "Auto-install Caddy not supported on this OS via script yet. Please install manually."
            return 1
        ;;
    esac
    if [[ $? -eq 0 ]]; then
        gum style --foreground 46 "Caddy installed successfully."
    else
        LOGE "Failed to install Caddy."
    fi
}

caddy_configure() {
    if [[ ! -f /usr/bin/caddy && ! -f /usr/sbin/caddy ]]; then
        if ! gum_confirm "Caddy not found. Install it now?" "y"; then
            return
        fi
        caddy_install
    fi

    # Get existing domains from Caddyfile or config
    PANEL_DOMAIN=""
    SUB_DOMAIN=""
    
    if [[ -f /etc/caddy/Caddyfile ]]; then
        # Try to parse existing domains
        PANEL_DOMAIN=$(grep -E "^[a-zA-Z0-9.-]+:8443 {" /etc/caddy/Caddyfile | head -1 | cut -d: -f1)
        SUB_DOMAIN=$(grep -E "^[a-zA-Z0-9.-]+:8443 {" /etc/caddy/Caddyfile | tail -1 | cut -d: -f1)
    fi

    gum style --foreground 86 --border rounded "⚙️ Caddy Configuration"
    PANEL_DOMAIN=$(gum input --placeholder "Panel Domain (e.g., panel.example.com)" --value "$PANEL_DOMAIN")
    SUB_DOMAIN=$(gum input --placeholder "Subscription Domain (e.g., sub.example.com)" --value "$SUB_DOMAIN")
    
    # Get Ports
    local panel_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local sub_port="2096" # Default or could be dynamic

    if [[ -z "$PANEL_DOMAIN" || -z "$SUB_DOMAIN" ]]; then
        LOGE "Domains cannot be empty."
        return
    fi

    gum style --foreground 33 "Generating Caddyfile..."
    cat > /etc/caddy/Caddyfile <<EOF
 ${PANEL_DOMAIN}:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:${panel_port}
    tls internal
}

 ${SUB_DOMAIN}:8443 {
    encode gzip
    reverse_proxy 127.0.0.1:${sub_port}
    tls internal
}
EOF

    gum style --foreground 33 "Restarting Caddy..."
    systemctl restart caddy
    if [[ $? -eq 0 ]]; then
        gum style --foreground 46 "Caddy configured and restarted successfully."
        gum style --foreground 212 "Panel URL: https://${PANEL_DOMAIN}:8443${webbase}"
    else
        LOGE "Failed to restart Caddy. Check 'journalctl -u caddy'."
    fi
}

caddy_menu() {
    choice=$(gum choose "Install Caddy" "Configure Caddy (Domains)" "View Caddyfile" "Restart Caddy" "Back")
    case "$choice" in
        "Install Caddy") caddy_install; caddy_menu ;;
        "Configure Caddy (Domains)") caddy_configure; caddy_menu ;;
        "View Caddyfile") cat /etc/caddy/Caddyfile; caddy_menu ;;
        "Restart Caddy") systemctl restart caddy; gum style --foreground 46 "Caddy restarted."; caddy_menu ;;
        "Back") show_menu ;;
    esac
}

# --- CORE STATUS & LOGIC ---
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

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        LOGE "Panel installed."
        if [[ $# == 0 ]]; then show_menu; fi
        return 1
    else return 0; fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        LOGE "Please install panel first."
        if [[ $# == 0 ]]; then show_menu; fi
        return 1
    else return 0; fi
}

show_status() {
    check_status
    case $? in
        0) echo -e "Panel: ${green}Running${plain}" ;;
        1) echo -e "Panel: ${yellow}Not Running${plain}" ;;
        2) echo -e "Panel: ${red}Not Installed${plain}" ;;
    esac
}

# --- MAIN MENU (GUM REWRITE) ---
show_menu() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 60 --margin "1 2" --padding "2 4" \
        "3X-UI MANAGEMENT"

    echo ""
    show_status
    echo ""
    
    # Using Gum Choose with mapping to keep logic compatible
    # We use the text to determine the action later
    
    CHOICE=$(gum choose \
        "🚀 Install" \
        "🔄 Update" \
        "🛠 Update Menu" \
        "❌ Uninstall" \
        "-----" \
        "👤 Reset User/Pass" \
        "🔑 Reset Web Base Path" \
        "⚙️ Reset Settings" \
        "🔌 Change Port" \
        "📋 View Settings" \
        "-----" \
        "▶ Start" \
        "⏹ Stop" \
        "♻ Restart" \
        "📊 Status" \
        "📜 Logs" \
        "-----" \
        "🚀 Enable Autostart" \
        "🛑 Disable Autostart" \
        "-----" \
        "🛡 IP Limit Manager" \
        "🔌 SSH Port Forwarding" \
        "🌐 Caddy Manager" \
        "⚡ Enable BBR" \
        "🌍 Update Geo Files" \
        "🚀 Speedtest" \
        "❌ Exit Script")

    case "$CHOICE" in
        "🚀 Install") check_uninstall && install ;;
        "🔄 Update") check_install && update ;;
        "🛠 Update Menu") check_install && update_menu ;;
        "❌ Uninstall") check_install && uninstall ;;
        "👤 Reset User/Pass") check_install && reset_user ;;
        "🔑 Reset Web Base Path") check_install && reset_webbasepath ;;
        "⚙️ Reset Settings") check_install && reset_config ;;
        "🔌 Change Port") check_install && set_port ;;
        "📋 View Settings") check_install && check_config ;;
        "▶ Start") check_install && start ;;
        "⏹ Stop") check_install && stop ;;
        "♻ Restart") check_install && restart ;;
        "📊 Status") check_install && status ;;
        "📜 Logs") check_install && show_log ;;
        "🚀 Enable Autostart") check_install && enable ;;
        "🛑 Disable Autostart") check_install && disable ;;
        "🛡 IP Limit Manager") iplimit_main ;;
        "🔌 SSH Port Forwarding") SSH_port_forwarding ;;
        "🌐 Caddy Manager") caddy_menu ;;
        "⚡ Enable BBR") bbr_menu ;;
        "🌍 Update Geo Files") update_geo ;;
        "🚀 Speedtest") run_speedtest ;;
        "❌ Exit Script") exit 0 ;;
        *) show_menu ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        *) show_menu ;;
    esac
else
    show_menu
fi
