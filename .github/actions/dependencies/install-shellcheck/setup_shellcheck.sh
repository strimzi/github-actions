#!/usr/bin/env bash
set -e

ARCH=$1
if [ -z "$ARCH" ] || [ "$ARCH" == "amd64" ]; then
    ARCH="x86_64"
fi

if [ "$ARCH" == "arm64" ]; then
    ARCH="aarch64"
fi

FILE="shellcheck-v${VERSION}.linux.${ARCH}.tar.xz"
curl -fL --retry 3 -o shellcheck.tar.xz "https://github.com/koalaman/shellcheck/releases/download/v${VERSION}/${FILE}"

# ShellCheck publishes no checksum file, so use the SHA-256 digest GitHub records for the release asset.
# GitHub records digests only for assets uploaded since mid-2025 (ShellCheck v0.11.0 and newer).
AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
EXPECTED=$(curl -fsSL --retry 3 "${AUTH[@]}" "https://api.github.com/repos/koalaman/shellcheck/releases/tags/v${VERSION}" \
    | jq -r --arg file "${FILE}" '.assets[] | select(.name == $file) | .digest // empty' | sed 's/^sha256://')
if [ -z "${EXPECTED}" ]; then
    echo "::error::No SHA-256 digest published for ${FILE}; use ShellCheck v0.11.0 or newer"
    exit 1
fi
echo "${EXPECTED}  shellcheck.tar.xz" | sha256sum -c -
tar xf shellcheck.tar.xz -C /tmp --strip-components 1
rm -f shellcheck.tar.xz
chmod +x /tmp/shellcheck
sudo mv /tmp/shellcheck /usr/bin
shellcheck --version
