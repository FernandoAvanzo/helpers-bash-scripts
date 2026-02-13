#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"
# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"
echo "$password" | sudo -S apt update -y
echo "$password" | sudo -S apt upgrade -y --allow-downgrades
echo "$password" | sudo -S apt upgrade -y
echo "$password" | sudo -S apt autoremove -y
echo "$password" | sudo -S apt clean -y
echo "Refresh flatpak"
flatpak update -y
#flatpak uninstall -y --unused

#install Script
#echo "$(get-root-psw)" | sudo -S ln -sf "$MY_CLI"/BashLib/src/update_system.sh /usr/bin/update_system