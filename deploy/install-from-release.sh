#!/bin/sh
set -eu

version=${1:?Usage: install-from-release.sh VERSION}
repository=${CALLUP_REPOSITORY:-ts/callup}

case "$(uname -m)" in
  x86_64|amd64) architecture=amd64 ;;
  *) echo "Callup does not yet publish an artifact for $(uname -m)." >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required." >&2; exit 1; }

archive="callup-${version}-linux-${architecture}.tar.gz"
base_url="https://github.com/${repository}/releases/download/v${version}"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

curl -fsSL "${base_url}/${archive}" -o "${temporary_directory}/${archive}"
curl -fsSL "${base_url}/${archive}.sha256" -o "${temporary_directory}/${archive}.sha256"
(cd "$temporary_directory" && sha256sum -c "${archive}.sha256")
tar -C "$temporary_directory" -xzf "${temporary_directory}/${archive}"
exec "${temporary_directory}/callup-${version}-linux-${architecture}/install.sh"
