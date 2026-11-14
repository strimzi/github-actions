#!/usr/bin/env bash
set -xe

TEST_HELM_VERSION=${TEST_HELM_VERSION:-'v4.3.2'}
TEST_HELM_UNITTEST_VERSION=${TEST_HELM_UNITTEST_VERSION:-'v1.2.1'}

function install_helm {
    # Remove any pre-installed helm binary to avoid PATH conflicts
    # (e.g., GitHub runners have helm in /usr/local/bin which takes precedence over /usr/bin)
    if [ -f /usr/local/bin/helm ]; then
        echo "Removing pre-installed helm at /usr/local/bin/helm..."
        sudo rm -f /usr/local/bin/helm
    fi

    export HELM_INSTALL_DIR=/usr/bin
    curl -fL --retry 3 https://raw.githubusercontent.com/helm/helm/06468084e85c244c712834933d25ea232a4c2093/scripts/get -o get_helm.sh # v4.2.0
    # we need to modify the script with a different path because on the Azure pipelines the HELM_INSTALL_DIR env var is not honoured
    sed -i 's#/usr/local/bin#/usr/bin#g' get_helm.sh
    chmod 700 get_helm.sh

    echo "Installing helm ${TEST_HELM_VERSION}..."
    sudo ./get_helm.sh --version "${TEST_HELM_VERSION}"
    rm -f get_helm.sh

    echo "Verifying the installation of helm binary..."
    # run a proper helm command instead of, for example, "which helm", to verify that we can call the binary
    helm --help
    helmCommandOutput=$?

    if [ $helmCommandOutput != 0 ]; then
        echo "helm binary hasn't been installed properly - exiting..."
        exit 1
    fi
}

function install_helm_unittest {
    echo "Installing helm unittest plugin ..."
    local verify_flag=()
    # Helm 4 verifies plugin signatures by default, which a git source does not support; Helm 3 has no such flag
    if [[ "$(helm version --template '{{.Version}}')" != v3.* ]]; then
        verify_flag=(--verify=false)
    fi
    helm plugin install "${verify_flag[@]}" --version "$TEST_HELM_UNITTEST_VERSION" https://github.com/helm-unittest/helm-unittest.git

    echo "Verifying the installation of helm unittest plugin ..."
    # run a proper helm command instead of, for example, "which helm", to verify that we can call the binary
    helm unittest --help
    helmCommandOutput=$?

    if [ $helmCommandOutput != 0 ]; then
        echo "helm unittest plugin hasn't been installed properly - exiting..."
        exit 1
    fi
}

install_helm
install_helm_unittest
