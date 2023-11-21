#!/bin/bash -e
################################################################################
##  File:  packer.sh
##  Desc:  Installs packer
################################################################################

source $HELPER_SCRIPTS/install.sh

# Install Packer
URL=$(curl -fsSL https://api.releases.hashicorp.com/v1/releases/packer/latest | jq -r '.builds[] | select((.arch=="'$ARCH'") and (.os=="linux")).url')
ZIP_NAME="packer_linux_$ARCH.zip"
download_with_retries "${URL}" "/tmp" "${ZIP_NAME}"
unzip -qq "/tmp/${ZIP_NAME}" -d /usr/local/bin
rm -f "/tmp/${ZIP_NAME}"

invoke_tests "Tools" "Packer"
