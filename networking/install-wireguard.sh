#!/bin/bash
# ============================================================
# Install WireGuard and generate initial configuration
# Usage: sudo bash install-wireguard.sh [options]
# ============================================================

set -euo pipefail

# --- Configuration ---
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_NETWORK="10.100.0"
SERVER_IP="${WG_NETWORK}.1/24"
WG_DIR="/etc/wireguard"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)      WG_PORT="$2"; shift 2 ;;
    --network)   WG_NETWORK="$2"; shift 2 ;;
    --interface) WG_INTERFACE="$2"; shift 2 ;;
    --help)
      echo "Usage: sudo $0 [options]"
      echo "  --port       WireGuard listen port (default: 51820)"
      echo "  --network    Network prefix (default: 10.100.0)"
      echo "  --interface  Interface name (default: wg0)"
      exit 0
      ;;
    *) err "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -ne 0 ] && err "Run as root (sudo)"

SERVER_IP="${WG_NETWORK}.1/24"

# --- Detect public IP and main interface ---
PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com || echo "YOUR_PUBLIC_IP")
MAIN_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' || echo "eth0")

# --- Install WireGuard ---
log "Installing WireGuard..."
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools qrencode

# --- Enable IP forwarding ---
log "Enabling IP forwarding..."
sed -i 's/#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- Generate server keys ---
log "Generating server keys..."
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"
umask 077

SERVER_PRIVKEY=$(wg genkey)
SERVER_PUBKEY=$(echo "$SERVER_PRIVKEY" | wg pubkey)

# --- Create server config ---
log "Creating server configuration..."
cat > "${WG_DIR}/${WG_INTERFACE}.conf" <<EOF
# WireGuard Server Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

[Interface]
Address = ${SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVKEY}

# NAT/Masquerade rules
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${MAIN_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${MAIN_IFACE} -j MASQUERADE

# Add peers below or use: bash add-peer.sh <peer-name>
EOF

chmod 600 "${WG_DIR}/${WG_INTERFACE}.conf"

# --- Create add-peer helper script ---
log "Creating peer management script..."
cat > "${WG_DIR}/add-peer.sh" <<'PEERSCRIPT'
#!/bin/bash
# Add a new WireGuard peer
# Usage: sudo bash add-peer.sh <peer-name>

set -euo pipefail

WG_DIR="/etc/wireguard"
WG_INTERFACE="wg0"
PEER_NAME="${1:-}"
DNS="1.1.1.1, 8.8.8.8"

if [ -z "$PEER_NAME" ]; then
  echo "Usage: $0 <peer-name>"
  exit 1
fi

[ "$(id -u)" -ne 0 ] && { echo "Run as root"; exit 1; }

# Read server config
SERVER_PUBKEY=$(grep PrivateKey "${WG_DIR}/${WG_INTERFACE}.conf" | awk '{print $3}' | wg pubkey)
SERVER_PORT=$(grep ListenPort "${WG_DIR}/${WG_INTERFACE}.conf" | awk '{print $3}')
SERVER_NETWORK=$(grep Address "${WG_DIR}/${WG_INTERFACE}.conf" | awk '{print $3}' | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
SERVER_ENDPOINT=$(curl -s4 ifconfig.me)

# Find next available IP
EXISTING_IPS=$(grep AllowedIPs "${WG_DIR}/${WG_INTERFACE}.conf" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' || true)
NEXT_IP=2
for i in $(seq 2 254); do
  if ! echo "$EXISTING_IPS" | grep -q "${SERVER_NETWORK}.${i}$"; then
    NEXT_IP=$i
    break
  fi
done

PEER_IP="${SERVER_NETWORK}.${NEXT_IP}/32"
PEER_PRIVKEY=$(wg genkey)
PEER_PUBKEY=$(echo "$PEER_PRIVKEY" | wg pubkey)
PEER_PSK=$(wg genpsk)

# Add peer to server config
cat >> "${WG_DIR}/${WG_INTERFACE}.conf" <<EOF

# Peer: ${PEER_NAME}
[Peer]
PublicKey = ${PEER_PUBKEY}
PresharedKey = ${PEER_PSK}
AllowedIPs = ${PEER_IP}
EOF

# Generate client config
PEER_CONF="${WG_DIR}/clients/${PEER_NAME}.conf"
mkdir -p "${WG_DIR}/clients"
cat > "$PEER_CONF" <<EOF
# WireGuard Client: ${PEER_NAME}

[Interface]
PrivateKey = ${PEER_PRIVKEY}
Address = ${SERVER_NETWORK}.${NEXT_IP}/24
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUBKEY}
PresharedKey = ${PEER_PSK}
Endpoint = ${SERVER_ENDPOINT}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 "$PEER_CONF"

# Reload WireGuard
wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_INTERFACE") 2>/dev/null || {
  systemctl restart "wg-quick@${WG_INTERFACE}"
}

echo ""
echo "Peer '${PEER_NAME}' created:"
echo "  IP: ${SERVER_NETWORK}.${NEXT_IP}"
echo "  Config: ${PEER_CONF}"
echo ""
echo "QR Code (scan with WireGuard mobile app):"
qrencode -t ansiutf8 < "$PEER_CONF"
PEERSCRIPT

chmod +x "${WG_DIR}/add-peer.sh"

# --- Firewall ---
log "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow "${WG_PORT}/udp" comment "WireGuard"
fi

# --- Enable & Start ---
log "Enabling WireGuard..."
systemctl enable "wg-quick@${WG_INTERFACE}"
systemctl start "wg-quick@${WG_INTERFACE}"

# --- Verify ---
sleep 1
if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}"; then
  log "WireGuard is running"
else
  warn "WireGuard service may need manual start"
fi

echo ""
echo "================================================"
echo " WireGuard Server Configured"
echo "================================================"
echo " Interface:  ${WG_INTERFACE}"
echo " Address:    ${SERVER_IP}"
echo " Port:       ${WG_PORT}"
echo " Public IP:  ${PUBLIC_IP}"
echo " Public Key: ${SERVER_PUBKEY}"
echo ""
echo " Add peers:  sudo bash ${WG_DIR}/add-peer.sh <name>"
echo "================================================"
