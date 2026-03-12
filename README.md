# DevOps Scripts

Collection of practical DevOps automation scripts for server setup, SSH management, monitoring, networking, and backups.

## Scripts

| Script | Description |
|--------|-------------|
| [`ssh-menu/menu_ssh.sh`](ssh-menu/menu_ssh.sh) | Interactive SSH connection manager with whiptail TUI. Reads hosts from a config file, organizes by category, supports custom keys and ports. |
| [`setup/setup-server.sh`](setup/setup-server.sh) | Initial server setup for Debian/Ubuntu: updates, essential tools, Docker, SSH hardening, UFW firewall, Fail2Ban. |
| [`monitoring/install-node-exporter.sh`](monitoring/install-node-exporter.sh) | Install Prometheus Node Exporter as a systemd service with security hardening. |
| [`networking/install-wireguard.sh`](networking/install-wireguard.sh) | Install and configure WireGuard VPN server with automatic peer management and QR code generation. |
| [`backup/backup-mysql.sh`](backup/backup-mysql.sh) | MySQL/MariaDB backup with compression (gzip/zstd) and automatic rotation. |

## Quick Start

### SSH Menu

```bash
# Edit the hosts config file with your servers
vim ssh-menu/hosts.conf

# Run the menu
bash ssh-menu/menu_ssh.sh

# Use a custom SSH key
bash ssh-menu/menu_ssh.sh --key ~/.ssh/my_key
```

### Server Setup

```bash
sudo bash setup/setup-server.sh \
  --timezone America/Sao_Paulo \
  --ssh-port 2222 \
  --user deploy \
  --pubkey "ssh-ed25519 AAAA..."
```

### Node Exporter

```bash
sudo bash monitoring/install-node-exporter.sh --version 1.7.0 --port 9100
```

### WireGuard VPN

```bash
# Install server
sudo bash networking/install-wireguard.sh --port 51820

# Add a client
sudo bash /etc/wireguard/add-peer.sh my-laptop
```

### MySQL Backup

```bash
# Run manually
MYSQL_PWD="your_password" bash backup/backup-mysql.sh --dir /backup/mysql --days 30

# Or use a config file
bash backup/backup-mysql.sh --config /etc/backup-mysql.conf

# Cron (daily at 2am)
# 0 2 * * * /path/to/backup-mysql.sh --config /etc/backup-mysql.conf >> /var/log/mysql-backup.log 2>&1
```

## Requirements

- **OS**: Debian 11+ / Ubuntu 20.04+
- **Shell**: Bash 4+
- **Tools**: `whiptail` (for SSH menu), `curl`, `jq`
- **Privileges**: Most scripts require `sudo`

## Host Config Format (SSH Menu)

```
# CATEGORY|HOST|PORT|USER|DESCRIPTION
proxmox|192.168.1.10|22|admin|pve-node-01
vm|10.10.10.11|2222|deploy|web-server-01
monitoring|10.10.10.50|2222|admin|grafana-01
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-script`)
3. Make your changes
4. Test on a clean VM before submitting
5. Submit a Pull Request

**Guidelines:**
- Never hardcode credentials, IPs, or hostnames
- Use config files or environment variables for secrets
- Add `--help` flag to all scripts
- Use `set -euo pipefail` for error handling
- Include usage comments at the top of each script

## License

MIT
