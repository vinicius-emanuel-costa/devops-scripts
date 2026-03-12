#!/bin/bash
# ============================================================
# SSH Menu — Interactive SSH connection manager using whiptail
# Reads hosts from hosts.conf (no hardcoded credentials)
# Usage: bash menu_ssh.sh [--config /path/to/hosts.conf]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/hosts.conf"
SSH_KEY="$HOME/.ssh/id_ed25519"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --key)    SSH_KEY="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--config hosts.conf] [--key ~/.ssh/id_ed25519]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Dependency check ---
if ! command -v whiptail &>/dev/null; then
  echo "whiptail not found. Install it: sudo apt install whiptail"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE"
  echo "Copy hosts.conf.example and edit with your hosts."
  exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "SSH key not found: $SSH_KEY"
  echo "Generate one: ssh-keygen -t ed25519"
  echo "Or specify with: $0 --key /path/to/key"
  exit 1
fi

# --- Connect function ---
connect() {
  local DATA="$1"
  local HOST PORT USER
  HOST=$(echo "$DATA" | cut -d'|' -f1)
  PORT=$(echo "$DATA" | cut -d'|' -f2)
  USER=$(echo "$DATA" | cut -d'|' -f3)
  clear
  echo ">>> ssh -p $PORT -i $SSH_KEY $USER@$HOST"
  echo ""
  ssh -p "$PORT" -i "$SSH_KEY" "$USER@$HOST"
}

# --- Load categories from config ---
get_categories() {
  grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | cut -d'|' -f1 | sort -u
}

# --- Load hosts for a category ---
load_category() {
  local category="$1"
  grep -v '^#' "$CONFIG_FILE" | grep -v '^$' | grep "^${category}|"
}

# --- Count hosts in a category ---
count_category() {
  local category="$1"
  load_category "$category" | wc -l
}

# --- Category submenu ---
menu_category() {
  local category="$1"
  local title
  title=$(echo "$category" | sed 's/.*/\u&/')

  while true; do
    local HOSTS_DATA=()
    local HOSTS_DESC=()
    local idx=0

    while IFS='|' read -r _cat host port user desc; do
      HOSTS_DATA+=("${host}|${port}|${user}")
      HOSTS_DESC+=("${user}@${host}:${port}  ${desc}")
      idx=$((idx + 1))
    done < <(load_category "$category")

    if [ ${#HOSTS_DATA[@]} -eq 0 ]; then
      whiptail --title "SSH Menu" --msgbox "No hosts found in category: $category" 8 50
      return
    fi

    local ARGS=()
    for i in "${!HOSTS_DESC[@]}"; do
      ARGS+=("$i" "${HOSTS_DESC[$i]}")
    done

    local HEIGHT=$((${#HOSTS_DESC[@]} + 8))
    [ "$HEIGHT" -gt 25 ] && HEIGHT=25

    local CHOICE
    CHOICE=$(whiptail --title "SSH Menu > ${title}" \
      --menu "Select host:" "$HEIGHT" 65 $((HEIGHT - 7)) \
      "${ARGS[@]}" 3>&1 1>&2 2>&3) || return

    connect "${HOSTS_DATA[$CHOICE]}"
  done
}

# --- Main menu ---
while true; do
  CATEGORIES=()
  while IFS= read -r cat; do
    local count
    count=$(count_category "$cat")
    CATEGORIES+=("$cat" "$(printf '%-15s (%d)' "$cat" "$count")")
  done < <(get_categories)

  if [ ${#CATEGORIES[@]} -eq 0 ]; then
    echo "No hosts found in $CONFIG_FILE"
    exit 1
  fi

  CAT=$(whiptail --title "SSH Menu" \
    --menu "Select category:" 18 50 10 \
    "${CATEGORIES[@]}" \
    3>&1 1>&2 2>&3) || exit 0

  menu_category "$CAT"
done
