#!/usr/bin/env bash
set -e

ARCH=$1
if [ -z "$ARCH" ]; then
    ARCH="amd64"
fi

BASE_URL="https://github.com/anchore/syft/releases/download/v${VERSION}"
FILE="syft_${VERSION}_linux_${ARCH}.tar.gz"
curl -fL --retry 3 -o "${FILE}" "${BASE_URL}/${FILE}"
curl -fsSL --retry 3 "${BASE_URL}/syft_${VERSION}_checksums.txt" | grep " ${FILE}$" | sha256sum -c -
tar xf "${FILE}" -C /tmp
rm -f "${FILE}"
chmod +x /tmp/syft
sudo mv /tmp/syft /usr/bin
syft version
