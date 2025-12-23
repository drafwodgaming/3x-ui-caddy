#!/usr/bin/env bash
set -e
#############
# Colors
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
cyan='\033[0;36m'
magenta='\033[0;35m'
plain='\033[0m'

# Check root
[[ $EUID -ne 0 ]] && echo -e "${red}✗ Error:${plain} Root privileges required" && exit 1

# Detect OS
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

# Architecture detection
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

# Create web interface directory
create_web_interface() {
    mkdir -p /tmp/3x-ui-installer
    cd /tmp/3x-ui-installer
    
    # Create the HTML interface
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3X-UI + Caddy Installer</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 800px;
            width: 100%;
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2em;
            margin-bottom: 10px;
        }
        
        .header p {
            opacity: 0.9;
        }
        
        .content {
            padding: 40px;
        }
        
        .section {
            margin-bottom: 30px;
        }
        
        .section-title {
            font-size: 1.3em;
            color: #333;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            margin-bottom: 8px;
            color: #555;
            font-weight: 500;
        }
        
        input[type="text"],
        input[type="password"],
        input[type="number"] {
            width: 100%;
            padding: 12px 15px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 16px;
            transition: all 0.3s;
        }
        
        input[type="text"]:focus,
        input[type="password"]:focus,
        input[type="number"]:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        
        .toggle-group {
            display: flex;
            gap: 15px;
            margin-top: 10px;
        }
        
        .toggle-option {
            flex: 1;
        }
        
        .toggle-option input[type="radio"] {
            display: none;
        }
        
        .toggle-option label {
            display: block;
            padding: 12px;
            text-align: center;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            cursor: pointer;
            transition: all 0.3s;
            margin: 0;
        }
        
        .toggle-option input[type="radio"]:checked + label {
            background: #667eea;
            color: white;
            border-color: #667eea;
        }
        
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            font-size: 18px;
            border-radius: 30px;
            cursor: pointer;
            transition: all 0.3s;
            display: block;
            margin: 30px auto 0;
            min-width: 200px;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        
        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .progress-container {
            display: none;
            margin-top: 30px;
        }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #f0f0f0;
            border-radius: 15px;
            overflow: hidden;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            width: 0%;
            transition: width 0.3s;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        
        .log-container {
            margin-top: 20px;
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            max-height: 300px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            display: none;
        }
        
        .log-entry {
            margin-bottom: 5px;
            padding: 5px;
            border-radius: 5px;
        }
        
        .log-success {
            background: #d4edda;
            color: #155724;
        }
        
        .log-error {
            background: #f8d7da;
            color: #721c24;
        }
        
        .log-info {
            background: #d1ecf1;
            color: #0c5460;
        }
        
        .result-container {
            display: none;
            margin-top: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 10px;
        }
        
        .result-item {
            margin-bottom: 15px;
            padding: 10px;
            background: white;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        
        .result-label {
            font-weight: bold;
            color: #667eea;
        }
        
        .copy-btn {
            background: #28a745;
            color: white;
            border: none;
            padding: 5px 10px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 12px;
            margin-left: 10px;
        }
        
        .copy-btn:hover {
            background: #218838;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .spinner {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255,255,255,.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s ease-in-out infinite;
            margin-right: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 3X-UI + Caddy Installer</h1>
            <p>Configure your proxy server with a modern web interface</p>
        </div>
        
        <div class="content">
            <form id="installForm">
                <div class="section">
                    <h2 class="section-title">🔐 Panel Credentials</h2>
                    <div class="form-group">
                        <label for="username">Username (leave empty to generate)</label>
                        <input type="text" id="username" name="username" placeholder="Auto-generated if empty">
                    </div>
                    <div class="form-group">
                        <label for="password">Password (leave empty to generate)</label>
                        <input type="password" id="password" name="password" placeholder="Auto-generated if empty">
                    </div>
                </div>
                
                <div class="section">
                    <h2 class="section-title">⚙️ Configuration</h2>
                    <div class="form-group">
                        <label for="panel_port">Panel Port</label>
                        <input type="number" id="panel_port" name="panel_port" value="8080" min="1" max="65535">
                    </div>
                    <div class="form-group">
                        <label for="sub_port">Subscription Port</label>
                        <input type="number" id="sub_port" name="sub_port" value="2096" min="1" max="65535">
                    </div>
                </div>
                
                <div class="section">
                    <h2 class="section-title">🌐 Caddy Configuration</h2>
                    <div class="form-group">
                        <label>Use Caddy as reverse proxy?</label>
                        <div class="toggle-group">
                            <div class="toggle-option">
                                <input type="radio" id="caddy_yes" name="use_caddy" value="true" checked>
                                <label for="caddy_yes">Yes</label>
                            </div>
                            <div class="toggle-option">
                                <input type="radio" id="caddy_no" name="use_caddy" value="false">
                                <label for="caddy_no">No</label>
                            </div>
                        </div>
                    </div>
                    <div id="caddy_domains" class="form-group">
                        <label for="panel_domain">Panel Domain</label>
                        <input type="text" id="panel_domain" name="panel_domain" placeholder="panel.example.com">
                        
                        <label for="sub_domain" style="margin-top: 15px;">Subscription Domain</label>
                        <input type="text" id="sub_domain" name="sub_domain" placeholder="sub.example.com">
                    </div>
                </div>
                
                <div class="section">
                    <h2 class="section-title">📡 Default Inbound</h2>
                    <div class="form-group">
                        <label>Create default VLESS Reality inbound?</label>
                        <div class="toggle-group">
                            <div class="toggle-option">
                                <input type="radio" id="inbound_yes" name="create_inbound" value="true" checked>
                                <label for="inbound_yes">Yes</label>
                            </div>
                            <div class="toggle-option">
                                <input type="radio" id="inbound_no" name="create_inbound" value="false">
                                <label for="inbound_no">No</label>
                            </div>
                        </div>
                    </div>
                </div>
                
                <button type="submit" class="btn" id="installBtn">
                    Start Installation
                </button>
            </form>
            
            <div class="progress-container" id="progressContainer">
                <div class="progress-bar">
                    <div class="progress-fill" id="progressFill">0%</div>
                </div>
            </div>
            
            <div class="log-container" id="logContainer"></div>
            
            <div class="result-container" id="resultContainer">
                <h2 class="section-title">✅ Installation Complete!</h2>
                <div id="resultContent"></div>
            </div>
        </div>
    </div>
    
    <script>
        // Toggle Caddy domains visibility
        document.querySelectorAll('input[name="use_caddy"]').forEach(radio => {
            radio.addEventListener('change', function() {
                const domainsDiv = document.getElementById('caddy_domains');
                domainsDiv.style.display = this.value === 'true' ? 'block' : 'none';
            });
        });
        
        // Form submission
        document.getElementById('installForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const formData = new FormData(this);
            const data = Object.fromEntries(formData);
            
            // Validate required fields
            if (data.use_caddy === 'true' && (!data.panel_domain || !data.sub_domain)) {
                alert('Please enter both panel and subscription domains when using Caddy');
                return;
            }
            
            // Disable form and show progress
            document.getElementById('installBtn').disabled = true;
            document.getElementById('installBtn').innerHTML = '<span class="spinner"></span>Installing...';
            document.getElementById('progressContainer').style.display = 'block';
            document.getElementById('logContainer').style.display = 'block';
            
            try {
                // Start installation
                const response = await fetch('/install', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(data)
                });
                
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    
                    const chunk = decoder.decode(value);
                    const lines = chunk.split('\n');
                    
                    for (const line of lines) {
                        if (line.startsWith('data: ')) {
                            const data = JSON.parse(line.slice(6));
                            updateProgress(data);
                        }
                    }
                }
            } catch (error) {
                addLogEntry('Error: ' + error.message, 'error');
            }
        });
        
        function updateProgress(data) {
            if (data.progress) {
                const progressFill = document.getElementById('progressFill');
                progressFill.style.width = data.progress + '%';
                progressFill.textContent = data.progress + '%';
            }
            
            if (data.message) {
                addLogEntry(data.message, data.type || 'info');
            }
            
            if (data.complete) {
                showResults(data.results);
            }
        }
        
        function addLogEntry(message, type = 'info') {
            const logContainer = document.getElementById('logContainer');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            entry.textContent = message;
            logContainer.appendChild(entry);
            logContainer.scrollTop = logContainer.scrollHeight;
        }
        
        function showResults(results) {
            const resultContainer = document.getElementById('resultContainer');
            const resultContent = document.getElementById('resultContent');
            
            resultContent.innerHTML = '';
            
            for (const [key, value] of Object.entries(results)) {
                const item = document.createElement('div');
                item.className = 'result-item';
                item.innerHTML = `
                    <span class="result-label">${key}:</span>
                    <span>${value}</span>
                    <button class="copy-btn" onclick="copyToClipboard('${value}')">Copy</button>
                `;
                resultContent.appendChild(item);
            }
            
            resultContainer.style.display = 'block';
            document.getElementById('installBtn').style.display = 'none';
        }
        
        function copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => {
                alert('Copied to clipboard!');
            });
        }
    </script>
</body>
</html>
EOF
}

# Start web server
start_web_server() {
    WEB_PORT=8888
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)
    
    echo -e "${cyan}═══════════════════════════════════════════════════${plain}"
    echo -e "${cyan}  🌐 Web Interface Started${plain}"
    echo -e "${cyan}═══════════════════════════════════════════════════${plain}"
    echo -e "${blue}📡 Open your browser and navigate to:${plain}"
    echo -e "${yellow}http://${SERVER_IP}:${WEB_PORT}${plain}"
    echo -e "${cyan}═══════════════════════════════════════════════════${plain}"
    echo -e "${plain}Waiting for configuration...${plain}\n"
    
    # Create Python server script
    cat > server.py << 'EOF'
import http.server
import socketserver
import json
import subprocess
import threading
import sys
import os
from urllib.parse import urlparse, parse_qs

class InstallerHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.path = '/index.html'
        return super().do_GET()
    
    def do_POST(self):
        if self.path == '/install':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            config = json.loads(post_data.decode('utf-8'))
            
            # Start installation in background thread
            threading.Thread(target=self.run_installation, args=(config,)).start()
            
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            
            # Start streaming progress
            self.wfile.write(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n\r\n')
    
    def run_installation(self, config):
        # Save config to file
        with open('/tmp/install_config.json', 'w') as f:
            json.dump(config, f)
        
        # Run the actual installation script
        subprocess.run(['/bin/bash', '/tmp/3x-ui-installer/install.sh'], check=True)

# Start server
PORT = 8888
with socketserver.TCPServer(("", PORT), InstallerHandler) as httpd:
    print(f"Serving at port {PORT}")
    httpd.serve_forever()
EOF
    
    # Create the actual installation script
    cat > install.sh << 'EOF'
#!/bin/bash
set -e

# Function to send progress update
send_progress() {
    local message="$1"
    local type="${2:-info}"
    local progress="${3:-0}"
    echo "data: {\"message\":\"$message\",\"type\":\"$type\",\"progress\":$progress}" >&3
    echo "" >&3
}

# Open file descriptor for progress updates
exec 3>/tmp/progress_fifo

# Load configuration
config=$(cat /tmp/install_config.json)
XUI_USERNAME=$(echo "$config" | jq -r '.username // empty')
XUI_PASSWORD=$(echo "$config" | jq -r '.password // empty')
PANEL_PORT=$(echo "$config" | jq -r '.panel_port // "8080"')
SUB_PORT=$(echo "$config" | jq -r '.sub_port // "2096"')
USE_CADDY=$(echo "$config" | jq -r '.use_caddy // "true"')
PANEL_DOMAIN=$(echo "$config" | jq -r '.panel_domain // empty')
SUB_DOMAIN=$(echo "$config" | jq -r '.sub_domain // empty')
CREATE_DEFAULT_INBOUND=$(echo "$config" | jq -r '.create_inbound // "true"')

# Generate credentials if empty
if [[ -z "$XUI_USERNAME" ]]; then
    XUI_USERNAME=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 10 | head -n 1)
fi
if [[ -z "$XUI_PASSWORD" ]]; then
    length=$((20 + RANDOM % 11))
    XUI_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' </dev/urandom | fold -w $length | head -n 1)
fi

send_progress "Starting installation..." "info" 5

# Install base dependencies
send_progress "Installing base dependencies..." "info" 10
apt-get update >/dev/null 2>&1
apt-get install -y -q wget curl tar tzdata sqlite3 jq python3 >/dev/null 2>&1
send_progress "Dependencies installed" "success" 20

# Install 3X-UI
send_progress "Installing 3X-UI..." "info" 30
cd /usr/local/
tag_version=$(curl -Ls "https://api.github.com/repos/drafwodgaming/3x-ui-caddy/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
wget --inet4-only -q -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/drafwodgaming/3x-ui-caddy/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
wget --inet4-only -q -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/drafwodgaming/3x-ui-caddy/main/x-ui.sh

if [[ -e /usr/local/x-ui/ ]]; then
    systemctl stop x-ui 2>/dev/null || true
    rm /usr/local/x-ui/ -rf
fi

tar zxf x-ui-linux-$(arch).tar.gz >/dev/null 2>&1
rm x-ui-linux-$(arch).tar.gz -f

cd x-ui
chmod +x x-ui x-ui.sh

if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
    mv bin/xray-linux-$(arch) bin/xray-linux-arm
    chmod +x bin/xray-linux-arm
fi
chmod +x x-ui bin/xray-linux-$(arch)

mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
chmod +x /usr/bin/x-ui

config_webBasePath=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 18 | head -n 1)

/usr/local/x-ui/x-ui setting -username "${XUI_USERNAME}" -password "${XUI_PASSWORD}" -port "${PANEL_PORT}" -webBasePath "${config_webBasePath}" >/dev/null 2>&1

cp -f x-ui.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable x-ui >/dev/null 2>&1
systemctl start x-ui
sleep 5

/usr/local/x-ui/x-ui migrate >/dev/null 2>&1
send_progress "3X-UI installed successfully" "success" 50

# Install Caddy if needed
if [[ "$USE_CADDY" == "true" ]]; then
    send_progress "Installing Caddy..." "info" 60
    apt update >/dev/null 2>&1
    apt install -y ca-certificates curl gnupg >/dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/caddy.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/caddy.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy.list >/dev/null
    apt update >/dev/null 2>&1
    apt install -y caddy >/dev/null 2>&1
    
    send_progress "Configuring Caddy..." "info" 70
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
    sleep 5
    send_progress "Caddy configured" "success" 80
fi

# Get panel info
PANEL_INFO=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null)
ACTUAL_PORT=$(echo "$PANEL_INFO" | grep -oP 'port: \K\d+')
ACTUAL_WEBBASE=$(echo "$PANEL_INFO" | grep -oP 'webBasePath: \K\S+')
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://api.ipify.org)

# Create default inbound if requested
if [[ "$CREATE_DEFAULT_INBOUND" == "true" ]]; then
    send_progress "Creating default VLESS Reality inbound..." "info" 85
    
    # API login
    if [[ "$USE_CADDY" == "true" ]]; then
        PANEL_URL="https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}"
    else
        PANEL_URL="http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}"
    fi
    
    response=$(curl -k -s -c /tmp/xui_cookies.txt -X POST "${PANEL_URL}login" -H "Content-Type: application/json" -H "Accept: application/json" -d "{\"username\":\"${XUI_USERNAME}\",\"password\":\"${XUI_PASSWORD}\"}" 2>/dev/null)
    
    if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        # Generate UUID and keys
        CLIENT_UUID=$(curl -k -s -b /tmp/xui_cookies.txt -X GET "${PANEL_URL}panel/api/server/getNewUUID" | jq -r '.obj.uuid')
        REALITY_KEYS=$(curl -k -s -b /tmp/xui_cookies.txt -X GET "${PANEL_URL}panel/api/server/getNewX25519Cert")
        REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | jq -r '.obj.publicKey')
        REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | jq -r '.obj.privateKey')
        SHORT_ID=$(openssl rand -hex 8)
        
        # Create inbound
        inbound_json=$(jq -n \
            --argjson port 443 \
            --arg uuid "$CLIENT_UUID" \
            --arg email "user" \
            --arg dest "www.google.com:443" \
            --arg sni "www.google.com" \
            --arg privkey "$REALITY_PRIVATE_KEY" \
            --arg shortid "$SHORT_ID" \
            --arg remark "VLESS-Reality-Vision" \
            '{
                enable: true,
                port: $port,
                protocol: "vless",
                settings: {
                    clients: [{ id: $uuid, flow: "xtls-rprx-vision", email: $email, limitIp: 0, totalGB: 0, expiryTime: 0, enable: true, tgId: "", subId: "" }],
                    decryption: "none",
                    fallbacks: []
                },
                streamSettings: {
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
                    tcpSettings: { acceptProxyProtocol: false, header: { type: "none" } }
                },
                sniffing: {
                    enabled: true,
                    destOverride: ["http", "tls", "quic", "fakedns"],
                    metadataOnly: false,
                    routeOnly: false
                },
                remark: $remark,
                listen: "",
                allocate: { strategy: "always", refresh: 5, concurrency: 3 }
            }')
        
        response=$(curl -k -s -b /tmp/xui_cookies.txt -X POST "${PANEL_URL}panel/api/inbounds/add" -H "Content-Type: application/json" -H "Accept: application/json" -d "$inbound_json" 2>/dev/null)
        
        if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
            send_progress "VLESS Reality inbound created" "success" 90
        else
            send_progress "Failed to create inbound" "error" 90
        fi
    else
        send_progress "Failed to authenticate with panel" "error" 90
    fi
fi

# Final results
send_progress "Installation complete!" "success" 100

# Prepare results
results="{"
results+="\"Username\":\"$XUI_USERNAME\","
results+="\"Password\":\"$XUI_PASSWORD\","

if [[ "$USE_CADDY" == "true" ]]; then
    results+="\"Panel URL\":\"https://${PANEL_DOMAIN}:8443${ACTUAL_WEBBASE}\","
    results+="\"Subscription URL\":\"https://${SUB_DOMAIN}:8443/\","
else
    results+="\"Panel URL\":\"http://${SERVER_IP}:${ACTUAL_PORT}${ACTUAL_WEBBASE}\","
fi

if [[ "$CREATE_DEFAULT_INBOUND" == "true" && -n "$CLIENT_UUID" ]]; then
    results+="\"VLESS Port\":\"443\","
    results+="\"VLESS UUID\":\"$CLIENT_UUID\","
    results+="\"VLESS Public Key\":\"$REALITY_PUBLIC_KEY\","
    results+="\"VLESS Short ID\":\"$SHORT_ID\","
fi

results+="}"

echo "data: {\"complete\":true,\"results\":$results}" >&3
echo "" >&3

# Close file descriptor
exec 3>&-
EOF
    
    chmod +x install.sh
    
    # Create named pipe for progress updates
    mkfifo /tmp/progress_fifo
    
    # Start Python web server
    python3 server.py &
    WEB_SERVER_PID=$!
    
    # Wait for user to complete configuration
    while [[ ! -f /tmp/install_config.json ]]; do
        sleep 1
    done
    
    # Wait for installation to complete
    while [[ ! -f /tmp/installation_complete ]]; do
        sleep 1
    done
    
    # Cleanup
    kill $WEB_SERVER_PID 2>/dev/null || true
    rm -rf /tmp/3x-ui-installer
}

# Main execution
main() {
    clear
    echo -e "${cyan}"
    echo "  ╭─────────────────────────────────────────╮"
    echo "  │                                         │"
    echo "  │        3X-UI + CADDY INSTALLER          │"
    echo "  │                                         │"
    echo "  ╰─────────────────────────────────────────╯"
    echo -e "${plain}"
    
    # Install Python if not present
    if ! command -v python3 &> /dev/null; then
        echo -e "${yellow}→${plain} Installing Python3..."
        apt-get update >/dev/null 2>&1
        apt-get install -y python3 >/dev/null 2>&1
    fi
    
    # Create web interface
    create_web_interface
    
    # Start web server
    start_web_server
    
    # Show final summary
    echo -e "\n${green}✓ Installation completed successfully!${plain}"
}

main
