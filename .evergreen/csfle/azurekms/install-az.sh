#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

# Check for already installed az
if command -v az >/dev/null 2>&1; then
    echo "Azure cli already installed:"
    az --version
    exit 0
fi

# Install az CLI for Darwin
if [ $(uname -s) == "Darwin" ]; then
    echo "Install az ... begin"
    brew install az
    echo "Install az ... end"
    exit 0
fi

# Install az CLI for Debian/Ubuntu.
# https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt#option-2-step-by-step-installation-instructions
echo "Install az ... begin"
# Once a sufficient version of `az` is installed on all tested distros, remove the install-az.sh script. BUILD-16836 requests installation of the latest `az` on supported distros.
sudo apt-get update
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install ca-certificates curl apt-transport-https lsb-release gnupg
curl -sL https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor |
    sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
    sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-get update
sudo apt-get -y -o DPkg::Lock::Timeout=-1 install -y azure-cli
az --version
echo "Install az ... end"
