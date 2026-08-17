#!/bin/sh
set -eu

: "${CALLUP_CTID:=110}"
: "${CALLUP_HOSTNAME:=callup}"
: "${CALLUP_STORAGE:=local}"
: "${CALLUP_TEMPLATE_STORAGE:=local}"
: "${CALLUP_RELEASE:=0.1.0-dev.1}"
: "${CALLUP_CORES:=1}"
: "${CALLUP_MEMORY:=768}"
: "${CALLUP_SWAP:=256}"
: "${CALLUP_DISK_SIZE:=4}"
: "${CALLUP_BRIDGE:=vmbr0}"

command -v pct >/dev/null 2>&1 || { echo "Run this on a Proxmox VE host." >&2; exit 1; }
command -v pveam >/dev/null 2>&1 || { echo "Run this on a Proxmox VE host." >&2; exit 1; }

if pct status "$CALLUP_CTID" >/dev/null 2>&1; then
  echo "Container $CALLUP_CTID already exists; refusing to overwrite it." >&2
  exit 1
fi

template=$(pveam list "$CALLUP_TEMPLATE_STORAGE" 2>/dev/null \
  | awk '$1 ~ /debian-13-standard_.*_amd64\\.tar\\.zst$/ { print $1; exit }')
if [ -z "$template" ]; then
  echo "Download a Debian 13 amd64 LXC template to $CALLUP_TEMPLATE_STORAGE first." >&2
  exit 1
fi

pct create "$CALLUP_CTID" "$template" \
  --hostname "$CALLUP_HOSTNAME" \
  --cores "$CALLUP_CORES" \
  --memory "$CALLUP_MEMORY" \
  --swap "$CALLUP_SWAP" \
  --rootfs "$CALLUP_STORAGE:$CALLUP_DISK_SIZE" \
  --net0 "name=eth0,bridge=$CALLUP_BRIDGE,firewall=1,ip=dhcp" \
  --unprivileged 1 \
  --onboot 1

if [ -n "${CALLUP_MEDIA_SOURCE:-}" ]; then
  pct set "$CALLUP_CTID" --mp0 "$CALLUP_MEDIA_SOURCE,mp=/data"
fi

pct start "$CALLUP_CTID"
pct exec "$CALLUP_CTID" -- sh -lc 'apt-get update && apt-get install -y --no-install-recommends ca-certificates curl'
pct exec "$CALLUP_CTID" -- sh -lc \
  "curl -fsSL https://raw.githubusercontent.com/ts/callup/v${CALLUP_RELEASE}/deploy/install-from-release.sh | sh -s -- ${CALLUP_RELEASE}"

if [ -n "${CALLUP_TV_LIBRARY_PATH:-}" ] || [ -n "${CALLUP_MOVIE_LIBRARY_PATH:-}" ]; then
  {
    [ -z "${CALLUP_TV_LIBRARY_PATH:-}" ] || printf '%s\n' "CALLUP_TV_LIBRARY_PATH=$CALLUP_TV_LIBRARY_PATH"
    [ -z "${CALLUP_MOVIE_LIBRARY_PATH:-}" ] || printf '%s\n' "CALLUP_MOVIE_LIBRARY_PATH=$CALLUP_MOVIE_LIBRARY_PATH"
  } | pct exec "$CALLUP_CTID" -- sh -c 'cat >> /etc/callup/callup.env'
  pct exec "$CALLUP_CTID" -- systemctl restart callup.service
fi

pct exec "$CALLUP_CTID" -- curl -fsS http://127.0.0.1:8484/health
echo
echo "Callup is running in container $CALLUP_CTID."
