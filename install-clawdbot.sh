#!/usr/bin/env bash
# ==========================================================
# Proxmox LXC Installer - ClawdBot
# Compatible with tteck / community-scripts
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

# ---------- Helper ----------
msg_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
msg_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# ---------- Root Check ----------
if [[ "$EUID" -ne 0 ]]; then
  msg_err "Bitte als root auf dem Proxmox Host ausführen!"
fi

# ---------- CTID ----------
CTID=$(pvesh get /cluster/nextid)
msg_info "Verwende CTID: $CTID"

# ---------- Template ----------
msg_info "Aktualisiere Template-Liste"
pveam update
pveam download local "$TEMPLATE"

# ---------- Create Container ----------
msg_info "Erstelle LXC Container für $APP"

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

# ---------- Start ----------
msg_info "Starte Container"
pct start "$CTID"
sleep 6

# ---------- Base Setup ----------
msg_info "Installiere Basis-Pakete & Locale"

pct exec "$CTID" -- bash -c "
set -e
apt update && apt upgrade -y
apt install -y curl git nano build-essential locales ca-certificates gnupg

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
"

msg_ok "Basis-System vorbereitet"

# ---------- Node.js 22 ----------
msg_info "Installiere Node.js 22 LTS"

pct exec "$CTID" -- bash -c "
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
node -v
npm -v
"

msg_ok "Node.js 22 installiert"

# ---------- ClawdBot ----------
msg_info "Installiere ClawdBot"

pct exec "$CTID" -- bash -c "
cd /opt
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot
npm install
"

msg_ok "ClawdBot installiert"

# ---------- PM2 ----------
msg_info "Installiere & konfiguriere PM2"

pct exec "$CTID" -- bash -c "
npm install -g pm2
pm2 start npm --name clawdbot -- run start || true
pm2 save
pm2 startup systemd -u root --hp /root
"

msg_ok "PM2 aktiv"

# ---------- Final ----------
echo ""
msg_ok "ClawdBot LXC erfolgreich installiert"
echo "--------------------------------------------------"
echo "CTID:        $CTID"
echo "Hostname:    $HOSTNAME"
echo "Pfad:        /opt/clawdbot"
echo ""
echo "NÄCHSTE SCHRITTE:"
echo "1) Konfiguration bearbeiten:"
echo "   pct exec $CTID -- nano /opt/clawdbot/.env"
echo ""
echo "2) Bot neu starten:"
echo "   pct exec $CTID -- pm2 restart clawdbot"
echo ""
echo "3) Logs ansehen:"
echo "   pct exec $CTID -- pm2 logs clawdbot"
echo "--------------------------------------------------"
