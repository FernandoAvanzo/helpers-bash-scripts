#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"
# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"
echo "$password" | sudo -S apt update -y
echo "$password" | sudo -S apt upgrade -y
echo "$password" | sudo -S apt autoremove -y
echo "Refresh flatpak"
flatpak update -y
