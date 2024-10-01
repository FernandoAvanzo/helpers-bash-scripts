#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"
# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"
echo "$password" | sudo -S apt update
echo "$password" | sudo -S apt upgrade
flatpak update -y