#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"
export DEV_RCLONE="$HOME/Projects/helpers-bash-scripts/rclone"
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./bin/root_user_config.sh
source "$DEV_RCLONE"/bin/root_user_config.sh
# shellcheck source=./../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh

password="$(getRootPassword)"

create_library_symlink

cp -f "$DEV_RCLONE"/rclone-mount.service "$RCLONE"
cp -f "$DEV_RCLONE"/init_rclone.sh "$RCLONE"
cp -rf "$DEV_RCLONE"/bin "$RCLONE"

if [ ! -L /usr/bin/init_rclone ]; then
    echo "$password" | sudo -S ln -sf "$RCLONE"/init_rclone.sh /usr/bin/init_rclone
fi

echo "Rclone configured"
