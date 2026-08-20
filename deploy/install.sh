#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root." >&2
  exit 1
fi

release_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

for resource in index.html app.css app.js; do
  [ -f "$release_dir/Callup_CallupServer.resources/Web/$resource" ] \
    || { echo "Missing Callup web resource: $resource" >&2; exit 1; }
done

getent group media >/dev/null 2>&1 || groupadd --gid 1500 media
getent passwd callup >/dev/null 2>&1 || useradd --system --home /var/lib/callup --gid media --shell /usr/sbin/nologin callup

install -d -o callup -g media -m 0750 /var/lib/callup /var/lib/callup/updates
install -d -o root -g root -m 0755 /opt/callup/bin /opt/callup/libexec
install -d -o root -g media -m 0750 /etc/callup
install -m 0755 "$release_dir/callup" /opt/callup/bin/callup
install -d -o root -g root -m 0755 \
  /opt/callup/bin/Callup_CallupServer.resources/Web
for resource in index.html app.css app.js; do
  install -m 0644 "$release_dir/Callup_CallupServer.resources/Web/$resource" \
    "/opt/callup/bin/Callup_CallupServer.resources/Web/$resource"
done
install -m 0755 "$release_dir/callup-update" /opt/callup/libexec/callup-update
install -m 0644 "$release_dir/callup.service" /etc/systemd/system/callup.service
install -m 0644 "$release_dir/callup-update.service" /etc/systemd/system/callup-update.service
install -m 0644 "$release_dir/callup-update.path" /etc/systemd/system/callup-update.path
install -m 0644 "$release_dir/callup-release.env" /etc/callup/callup-release.env

if [ ! -e /etc/callup/callup.env ]; then
  install -m 0640 -o root -g media "$release_dir/callup.env" /etc/callup/callup.env
fi
if [ ! -e /etc/callup/callup-update.env ]; then
  update_repository=${CALLUP_UPDATE_REPOSITORY:-ts/callup}
  printf '%s\n' "$update_repository" | grep -Eq '^[0-9A-Za-z_.-]+/[0-9A-Za-z_.-]+$' \
    || { echo "Invalid Callup update repository." >&2; exit 1; }
  printf 'CALLUP_UPDATE_REPOSITORY=%s\n' "$update_repository" \
    > /etc/callup/callup-update.env
  chmod 0644 /etc/callup/callup-update.env
fi

systemctl daemon-reload
systemctl enable callup.service
systemctl enable --now callup-update.path
install -o root -g root -m 0644 /dev/null /var/lib/callup/updates/ready
systemctl restart callup.service
systemctl --no-pager --full status callup.service
