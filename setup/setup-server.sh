#!/bin/bash
# ============================================================
# Server Initial Setup Script
# Configures a fresh Debian/Ubuntu server with essentials
# Usage: sudo bash setup-server.sh
# ============================================================

set -euo pipefail

# --- Configuration ---
TIMEZONE="America/Sao_Paulo"
SSH_PORT="2222"
ADMIN_USER="deploy"
ADMIN_PUBKEY=""  # Paste your public key here or pass via --pubkey

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timezone)  TIMEZONE="$2"; shift 2 ;;
    --ssh-port)  SSH_PORT="$2"; shift 2 ;;
    --user)      ADMIN_USER="$2"; shift 2 ;;
    --pubkey)    ADMIN_PUBKEY="$2"; shift 2 ;;
    --help)
      echo "Usage: sudo $0 [options]"
      echo "  --timezone   Timezone (default: America/Sao_Paulo)"
      echo "  --ssh-port   SSH port (default: 2222)"
      echo "  --user       Admin username (default: deploy)"
      echo "  --pubkey     SSH public key for admin user"
      exit 0
      ;;
    *) err "Unknown option: $1" ;;
  esac
done

# --- Root check ---
if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root (use sudo)"
fi

# --- System update ---
log "Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get dist-upgrade -y -qq

# --- Install essential tools ---
log "Installing essential tools..."
apt-get install -y -qq \
  curl wget vim htop net-tools \
  git unzip jq tree tmux \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg lsb-release \
  fail2ban ufw \
  ncdu iotop iftop \
  bash-completion

# --- Timezone ---
log "Setting timezone to $TIMEZONE..."
timedatectl set-timezone "$TIMEZONE"

# --- Create admin user ---
log "Creating admin user: $ADMIN_USER..."
if ! id "$ADMIN_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
  echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN_USER"
  chmod 440 "/etc/sudoers.d/$ADMIN_USER"

  if [ -n "$ADMIN_PUBKEY" ]; then
    mkdir -p "/home/$ADMIN_USER/.ssh"
    echo "$ADMIN_PUBKEY" > "/home/$ADMIN_USER/.ssh/authorized_keys"
    chmod 700 "/home/$ADMIN_USER/.ssh"
    chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
    chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
    log "SSH key added for $ADMIN_USER"
  else
    warn "No SSH public key provided. Add one manually to /home/$ADMIN_USER/.ssh/authorized_keys"
  fi
else
  warn "User $ADMIN_USER already exists, skipping creation"
fi

# --- Harden SSH ---
log "Hardening SSH configuration..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?X11Forwarding .*/X11Forwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 300/' "$SSHD_CONFIG"
sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 2/' "$SSHD_CONFIG"

# Add AllowUsers if not present
if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
  echo "AllowUsers $ADMIN_USER" >> "$SSHD_CONFIG"
fi

systemctl restart sshd || systemctl restart ssh
log "SSH hardened: port=$SSH_PORT, root login disabled, password auth disabled"

# --- UFW Firewall ---
log "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable
log "UFW enabled with ports: $SSH_PORT (SSH), 80 (HTTP), 443 (HTTPS)"

# --- Fail2Ban ---
log "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<JAILEOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
JAILEOF
systemctl enable fail2ban
systemctl restart fail2ban

# --- Install Docker ---
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$ADMIN_USER"
  systemctl enable docker
  systemctl start docker
  log "Docker installed and $ADMIN_USER added to docker group"
else
  warn "Docker already installed, skipping"
fi

# --- Install Docker Compose (plugin) ---
log "Installing Docker Compose plugin..."
apt-get install -y -qq docker-compose-plugin 2>/dev/null || {
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}
log "Docker Compose installed: $(docker compose version 2>/dev/null || echo 'check manually')"

# --- Cleanup ---
log "Cleaning up..."
apt-get autoremove -y -qq
apt-get autoclean -qq

# --- Summary ---
echo ""
echo "========================================"
echo " Server Setup Complete"
echo "========================================"
echo " Timezone:   $TIMEZONE"
echo " SSH Port:   $SSH_PORT"
echo " Admin User: $ADMIN_USER"
echo " Firewall:   UFW enabled"
echo " Fail2Ban:   Enabled"
echo " Docker:     $(docker --version 2>/dev/null || echo 'N/A')"
echo ""
warn "IMPORTANT: Test SSH on port $SSH_PORT before closing this session!"
echo ""
