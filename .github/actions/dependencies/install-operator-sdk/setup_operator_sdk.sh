OPERATOR_SDK_VERSION=${OPERATOR_SDK_VERSION:-1.42.2}
OS=$(uname | awk '{print tolower($0)}')

ARCH=$1
if [ -z "$ARCH" ]; then
    ARCH="amd64"
fi

OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v${OPERATOR_SDK_VERSION}

curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}

chmod +x operator-sdk_${OS}_${ARCH} && sudo mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk
