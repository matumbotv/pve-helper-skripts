#!/usr/bin/env bash
# ==========================================================
# Proxmox LXC Installer - ClawdBot (Bugfix Edition)
# ==========================================================

set -euo pipefail

APP="ClawdBot"
HOSTNAME="clawdbot"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"
DISK_SIZE="16"
MEMORY="2048"
SWAP="512"
CORES="2"
BRIDGE="vmbr0"
IP="dhcp"

msg_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
msg_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

[[ "$EUID" -ne 0 ]] && msg_err "Als root auf dem Proxmox Host ausführen!"

CTID=$(pvesh get /cluster/nextid)
msg_info "CTID: $CTID"

pveam update
pveam download local "$TEMPLATE"

pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$SWAP" \
  --rootfs "$STORAGE:$DISK_SIZE" \
  --net0 name=eth0,bridge="$BRIDGE",ip="$IP" \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1 \
  --ostype ubuntu

pct start "$CTID"
sleep 6

msg_info "Basis-System & Locale"
pct exec "$CTID" -- bash -c "
apt update && apt upgrade -y
apt install -y curl git nano build-essential locales ca-certificates gnupg
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
"

msg_info "Node.js 22 LTS"
pct exec "$CTID" -- bash -c "
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
node -v
"

msg_info "ClawdBot (postinstall übersprungen)"
pct exec "$CTID" -- bash -c "
cd /opt
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot
npm install --ignore-scripts
"

msg_info "PM2 Setup"
pct exec "$CTID" -- bash -c "
npm install -g pm2
pm2 start npm --name clawdbot -- run start || true
pm2 save
pm2 startup systemd -u root --hp /root
"

msg_ok "Installation abgeschlossen"

echo "--------------------------------------------------"
echo "CTID: $CTID"
echo "Config: /opt/clawdbot/.env"
echo "Restart: pm2 restart clawdbot"
echo "Logs:    pm2 logs clawdbot"
echo "--------------------------------------------------"
