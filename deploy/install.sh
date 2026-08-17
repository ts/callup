#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root." >&2
  exit 1
fi

release_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

getent group media >/dev/null 2>&1 || groupadd --gid 1500 media
getent passwd callup >/dev/null 2>&1 || useradd --system --home /var/lib/callup --gid media --shell /usr/sbin/nologin callup

install -d -o callup -g media -m 0750 /var/lib/callup /opt/callup/bin
install -m 0755 "$release_dir/callup" /opt/callup/bin/callup
install -m 0644 "$release_dir/callup.service" /etc/systemd/system/callup.service

systemctl daemon-reload
systemctl enable --now callup.service
systemctl --no-pager --full status callup.service
