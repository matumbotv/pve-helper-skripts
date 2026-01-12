#!/usr/bin/env bash

# ==========================================================
# Proxmox LXC Installer - ClawdBot
# Compatible with tteck / community-scripts style
# ==========================================================

set -e

APP="ClawdBot"
CTID=""
HOSTNAME="clawdbot"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"
DISK_SIZE="16"
MEMORY="2048"
SWAP="512"
CORES="2"
BRIDGE="vmbr0"
IP="dhcp"

# ---------- Helper Functions ----------
msg_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
msg_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# ---------- Root Check ----------
if [[ "$EUID" -ne 0 ]]; then
  msg_err "Dieses Skript muss als root ausgeführt werden!"
fi

# ---------- Get Next CTID ----------
CTID=$(pvesh get /cluster/nextid)
msg_info "Verwende CTID: $CTID"

# ---------- Download Template ----------
msg_info "Prüfe LXC Template..."
pveam update
pveam download local "$TEMPLATE"

# ---------- Create Container ----------
msg_info "Erstelle LXC Container für $APP..."

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

msg_ok "Container erstellt"

# ---------- Start Container ----------
msg_info "Starte Container..."
pct start "$CTID"
sleep 5

# ---------- Install Dependencies ----------
msg_info "Installiere Abhängigkeiten..."

pct exec "$CTID" -- bash -c "
apt update && apt upgrade -y
apt install -y curl git nano build-essential
"

msg_ok "System vorbereitet"

# ---------- Install Node.js 20 ----------
msg_info "Installiere Node.js 20..."

pct exec "$CTID" -- bash -c "
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
"

msg_ok "Node.js installiert"

# ---------- Install ClawdBot ----------
msg_info "Installiere ClawdBot..."

pct exec "$CTID" -- bash -c "
cd /opt
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot
npm install
"

msg_ok "ClawdBot installiert"

# ---------- Install PM2 ----------
msg_info "Installiere PM2..."

pct exec "$CTID" -- bash -c "
npm install -g pm2
pm2 start npm --name clawdbot -- run start || true
pm2 save
pm2 startup systemd -u root --hp /root
"

msg_ok "PM2 eingerichtet"

# ---------- Final Info ----------
echo ""
msg_ok "ClawdBot LXC Installation abgeschlossen!"
echo "--------------------------------------------------"
echo "CTID:        $CTID"
echo "Hostname:    $HOSTNAME"
echo "Pfad:        /opt/clawdbot"
echo ""
echo "⚠️ WICHTIG:"
echo "1. Bearbeite die Konfiguration:"
echo "   pct exec $CTID -- nano /opt/clawdbot/.env"
echo ""
echo "2. Danach Neustart:"
echo "   pct exec $CTID -- pm2 restart clawdbot"
echo "--------------------------------------------------"
