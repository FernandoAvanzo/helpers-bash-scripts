#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export DEV_RCLONE="$MY_CLI/rclone"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./bin/root_user_config.sh
source "$DEV_RCLONE"/bin/root_user_config.sh
# shellcheck source=./../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh
# shellcheck source=./bin/manage_rclone_service.sh
source "$MY_CLI"/rclone/bin/manage_rclone_service.sh

password="$(getRootPassword)"

create_library_symlink
create_projects_symlink

cp -f  "$DEV_RCLONE"/rclone-mount.service "$RCLONE"
cp -f  "$DEV_RCLONE"/init_rclone.sh "$RCLONE"
cp -f  "$DEV_RCLONE"/rclone.desktop "$RCLONE"
cp -rf "$DEV_RCLONE"/resource "$RCLONE"
cp -rf "$DEV_RCLONE"/bin "$RCLONE"

edit_rclone_service_file
edit_rclone_desktop_file

if [ ! -L /usr/bin/init_rclone ]; then
    echo "$password" | sudo -S ln -sf "$RCLONE"/init_rclone.sh /usr/bin/init_rclone
fi

if [ ! -L "$HOME"/.config/autostart/rclone.desktop ]; then
    ln -sf "$RCLONE"/rclone.desktop "$HOME"/.config/autostart/rclone.desktop
fi

echo "Rclone configured"
