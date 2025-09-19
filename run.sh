#!/bin/bash
set -e

VLESS_URI="$1"
if [ -z "$VLESS_URI" ]; then
  echo "Usage: $0 <vless://...>"
  exit 1
fi

# -------------------------------
# 1. Ensure xray installed
# -------------------------------
if ! command -v xray &>/dev/null; then
  echo "[*] Xray not found. Installing..."
  sudo apt-get update -y
  sudo apt-get install -y unzip curl
  curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip
  unzip /tmp/xray.zip -d /tmp/xray
  sudo mv /tmp/xray/xray /usr/local/bin/xray
  sudo chmod +x /usr/local/bin/xray
  rm -rf /tmp/xray /tmp/xray.zip
fi

# -------------------------------
# 2. Parse VLESS URI
# -------------------------------
uuid=$(echo "$VLESS_URI" | sed -n 's#vless://\([^@]*\)@.*#\1#p')
server=$(echo "$VLESS_URI" | sed -n 's#.*@\([^:]*\):.*#\1#p')
port=$(echo "$VLESS_URI" | sed -n 's#.*:\([0-9]*\)?.*#\1#p')
type=$(echo "$VLESS_URI" | grep -o "type=[^&]*" | cut -d= -f2)
path=$(echo "$VLESS_URI" | grep -o "path=[^&]*" | cut -d= -f2 | sed 's/%2F/\//g')
host=$(echo "$VLESS_URI" | grep -o "host=[^&]*" | cut -d= -f2)
tls=$(echo "$VLESS_URI" | grep -o "security=[^&]*" | cut -d= -f2)

# -------------------------------
# 3. Generate config.json
# -------------------------------
TMPDIR=$(mktemp -d)
CONFIG="$TMPDIR/config.json"

cat > "$CONFIG" <<EOF
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "udp": true,
        "auth": "noauth"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$server",
            "port": $port,
            "users": [
              {
                "id": "$uuid",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "$type",
        "security": "$tls",
        "tlsSettings": {
          "allowInsecure": true,
          "serverName": "$host"
        },
        "wsSettings": {
          "path": "$path",
          "headers": {
            "Host": "$host"
          }
        }
      }
    }
  ]
}
EOF

echo "[*] Generated config: $CONFIG"

# -------------------------------
# 4. Run Xray
# -------------------------------
echo "[*] Starting Xray..."
xray -c "$CONFIG" &
XRAY_PID=$!

sleep 2

# -------------------------------
# 5. Test download
# -------------------------------
echo "[*] Downloading 10MB test file via proxy..."
curl --socks5 127.0.0.1:1080 -L -o /dev/null https://github.com/JerryMouseZ/raw_file/raw/refs/heads/master/rawfile

kill $XRAY_PID
