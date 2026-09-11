#!/usr/bin/env bash
set -e

ARCH=$1
if [ -z "$ARCH" ]; then
    ARCH="amd64"
fi

curl -fL --retry 3 "https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_${ARCH}" -o yq
chmod +x yq
sudo mv yq /usr/bin/
yq --version
