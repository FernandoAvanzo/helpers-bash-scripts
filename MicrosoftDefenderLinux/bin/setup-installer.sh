#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export RCLONE="$HOME/.Library/rclone"
export MDE_INSTALL="$MY_CLI/MicrosoftDefenderLinux/bin"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

echo "$password" | sudo -S ln -sf "$MDE_INSTALL"/mde_installer.sh /usr/local/bin/mde_installer
