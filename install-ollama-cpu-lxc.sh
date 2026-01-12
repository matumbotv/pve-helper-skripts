#!/usr/bin/env bash
# ==========================================================
# Proxmox LXC Installer - Ollama (CPU only)
# ==========================================================

set -euo pipefail

APP="Ollama"
HOSTNAME="ollama"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"
DISK_SIZE="32"
MEMORY="4096"
SWAP="1024"
CORES="4"
BRIDGE="vmbr0"
IP="dhcp"

msg_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
msg_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

[[ "$EUID" -ne 0 ]] && msg_err "Bitte als root auf dem Proxmox Host ausführen!"

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

msg_info "Basis-System vorbereiten"
pct exec "$CTID" -- bash -c "
apt update && apt upgrade -y
apt install -y curl nano git locales ca-certificates
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
"

msg_info "Ollama installieren"
pct exec "$CTID" -- bash -c "
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
systemctl start ollama
"

msg_ok "Ollama installiert & gestartet"

echo "--------------------------------------------------"
echo "CTID:        $CTID"
echo "Ollama URL:  http://<IP>:11434"
echo "Models:      ollama pull qwen2.5-coder:7b"
echo "--------------------------------------------------"
