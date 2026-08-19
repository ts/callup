#!/bin/sh
set -eu

version=${1:-latest}
repository=${CALLUP_REPOSITORY:-ts/callup}

case "$(uname -m)" in
  x86_64|amd64) architecture=amd64 ;;
  *) echo "Callup does not yet publish an artifact for $(uname -m)." >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required." >&2; exit 1; }

if [ "$version" = latest ]; then
  version=$(curl -fsSL "https://api.github.com/repos/${repository}/releases?per_page=1" \
    | sed -n 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"v\([^"]*\)".*/\1/p' \
    | head -n 1)
  [ -n "$version" ] || { echo "Could not determine the latest Callup release." >&2; exit 1; }
fi

case "$version" in
  *[!0-9A-Za-z._-]*|'') echo "Invalid Callup release version." >&2; exit 1 ;;
esac

archive="callup-${version}-linux-${architecture}.tar.gz"
base_url="https://github.com/${repository}/releases/download/v${version}"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

curl -fsSL "${base_url}/${archive}" -o "${temporary_directory}/${archive}"
curl -fsSL "${base_url}/${archive}.sha256" -o "${temporary_directory}/${archive}.sha256"
(cd "$temporary_directory" && sha256sum -c "${archive}.sha256")
tar -C "$temporary_directory" -xzf "${temporary_directory}/${archive}"
CALLUP_UPDATE_REPOSITORY=$repository \
  exec "${temporary_directory}/callup-${version}-linux-${architecture}/install.sh"
