#!/usr/bin/env bash
set -e

ARCH=$1
if [ -z "$ARCH" ]; then
    ARCH="amd64"
fi

BASE_URL="https://github.com/mikefarah/yq/releases/download/${VERSION}"
FILE="yq_linux_${ARCH}"
curl -fL --retry 3 "${BASE_URL}/${FILE}" -o yq
# The checksums file lists many hashes per file; checksums_hashes_order gives their order
SHA256_INDEX=$(curl -fsSL --retry 3 "${BASE_URL}/checksums_hashes_order" | grep -n '^SHA-256$' | cut -d: -f1)
EXPECTED=$(curl -fsSL --retry 3 "${BASE_URL}/checksums" | awk -v file="${FILE}" -v column="$((SHA256_INDEX + 1))" '$1 == file { print $column }')
echo "${EXPECTED}  yq" | sha256sum -c -
chmod +x yq
sudo mv yq /usr/bin/
yq --version
