# DevOps Scripts

Colecao de scripts praticos de automacao DevOps para configuracao de servidores, gerenciamento SSH, monitoramento, rede e backups.

## Scripts

| Script | Descricao |
|--------|-----------|
| [`ssh-menu/menu_ssh.sh`](ssh-menu/menu_ssh.sh) | Gerenciador interativo de conexoes SSH com TUI whiptail. Le hosts de um arquivo de configuracao, organiza por categoria, suporta chaves e portas customizadas. |
| [`setup/setup-server.sh`](setup/setup-server.sh) | Configuracao inicial de servidor para Debian/Ubuntu: atualizacoes, ferramentas essenciais, Docker, hardening SSH, firewall UFW, Fail2Ban. |
| [`monitoring/install-node-exporter.sh`](monitoring/install-node-exporter.sh) | Instalacao do Prometheus Node Exporter como servico systemd com hardening de seguranca. |
| [`networking/install-wireguard.sh`](networking/install-wireguard.sh) | Instalacao e configuracao de servidor WireGuard VPN com gerenciamento automatico de peers e geracao de QR code. |
| [`backup/backup-mysql.sh`](backup/backup-mysql.sh) | Backup de MySQL/MariaDB com compressao (gzip/zstd) e rotacao automatica. |

## Como Usar

### SSH Menu

```bash
# Edite o arquivo de configuracao de hosts com seus servidores
vim ssh-menu/hosts.conf

# Execute o menu
bash ssh-menu/menu_ssh.sh

# Usar uma chave SSH customizada
bash ssh-menu/menu_ssh.sh --key ~/.ssh/my_key
```

### Configuracao de Servidor

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
# Instalar servidor
sudo bash networking/install-wireguard.sh --port 51820

# Adicionar um cliente
sudo bash /etc/wireguard/add-peer.sh my-laptop
```

### Backup MySQL

```bash
# Executar manualmente
MYSQL_PWD="sua_senha" bash backup/backup-mysql.sh --dir /backup/mysql --days 30

# Ou usar um arquivo de configuracao
bash backup/backup-mysql.sh --config /etc/backup-mysql.conf

# Cron (diario as 2h da manha)
# 0 2 * * * /path/to/backup-mysql.sh --config /etc/backup-mysql.conf >> /var/log/mysql-backup.log 2>&1
```

## Requisitos

- **SO**: Debian 11+ / Ubuntu 20.04+
- **Shell**: Bash 4+
- **Ferramentas**: `whiptail` (para o SSH menu), `curl`, `jq`
- **Privilegios**: A maioria dos scripts requer `sudo`

## Formato de Configuracao de Hosts (SSH Menu)

```
# CATEGORIA|HOST|PORTA|USUARIO|DESCRICAO
proxmox|192.168.1.10|22|admin|pve-node-01
vm|10.10.10.11|2222|deploy|web-server-01
monitoring|10.10.10.50|2222|admin|grafana-01
```

## Contribuicao

1. Faca um fork do repositorio
2. Crie uma branch de feature (`git checkout -b feature/novo-script`)
3. Faca suas alteracoes
4. Teste em uma VM limpa antes de enviar
5. Envie um Pull Request

**Diretrizes:**
- Nunca coloque credenciais, IPs ou hostnames hardcoded
- Use arquivos de configuracao ou variaveis de ambiente para secrets
- Adicione flag `--help` em todos os scripts
- Use `set -euo pipefail` para tratamento de erros
- Inclua comentarios de uso no topo de cada script

## Licenca

MIT
