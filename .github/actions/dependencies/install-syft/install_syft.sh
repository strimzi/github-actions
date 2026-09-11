#!/usr/bin/env bash
set -e

ARCH=$1
if [ -z "$ARCH" ]; then
    ARCH="amd64"
fi

curl -fL --retry 3 -o syft.tar.gz "https://github.com/anchore/syft/releases/download/v${VERSION}/syft_${VERSION}_linux_${ARCH}.tar.gz"
tar xf syft.tar.gz -C /tmp
rm -f syft.tar.gz
chmod +x /tmp/syft
sudo mv /tmp/syft /usr/bin
syft version
