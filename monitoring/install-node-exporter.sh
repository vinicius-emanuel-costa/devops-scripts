#!/bin/bash
# ============================================================
# Install Node Exporter as a systemd service
# Prometheus node metrics exporter
# Usage: sudo bash install-node-exporter.sh [--version 1.7.0]
# ============================================================

set -euo pipefail

VERSION="1.7.0"
USER="node_exporter"
INSTALL_DIR="/usr/local/bin"
LISTEN_PORT="9100"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --port)    LISTEN_PORT="$2"; shift 2 ;;
    --help)
      echo "Usage: sudo $0 [--version 1.7.0] [--port 9100]"
      exit 0
      ;;
    *) err "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -ne 0 ] && err "Run as root (sudo)"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  armv7l)  ARCH="armv7" ;;
  *) err "Unsupported architecture: $ARCH" ;;
esac

TARBALL="node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${TARBALL}"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Download ---
log "Downloading Node Exporter v${VERSION} (${ARCH})..."
cd "$TMP_DIR"
curl -fsSL -O "$URL"

# --- Extract & Install ---
log "Installing..."
tar xzf "$TARBALL"
cp "node_exporter-${VERSION}.linux-${ARCH}/node_exporter" "$INSTALL_DIR/"
chmod +x "${INSTALL_DIR}/node_exporter"

# --- Create system user ---
if ! id "$USER" &>/dev/null; then
  log "Creating system user: $USER"
  useradd --no-create-home --shell /bin/false "$USER"
fi

# --- Systemd service ---
log "Creating systemd service..."
cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=${USER}
Group=${USER}
Type=simple
ExecStart=${INSTALL_DIR}/node_exporter \\
  --web.listen-address=":${LISTEN_PORT}" \\
  --collector.systemd \\
  --collector.processes
Restart=always
RestartSec=5

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadOnlyPaths=/

[Install]
WantedBy=multi-user.target
EOF

# --- Enable & Start ---
log "Enabling and starting service..."
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# --- Verify ---
sleep 2
if systemctl is-active --quiet node_exporter; then
  log "Node Exporter is running on port ${LISTEN_PORT}"
  log "Test: curl http://localhost:${LISTEN_PORT}/metrics"
else
  err "Node Exporter failed to start. Check: journalctl -u node_exporter"
fi

echo ""
echo "================================================"
echo " Node Exporter v${VERSION} installed successfully"
echo " Port: ${LISTEN_PORT}"
echo " Service: systemctl status node_exporter"
echo " Metrics: http://<server-ip>:${LISTEN_PORT}/metrics"
echo "================================================"
