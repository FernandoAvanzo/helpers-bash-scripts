#!/bin/bash
#dev
export DEV_RCLONE="$HOME/Projects/helpers-bash-scripts/rclone"
#prod
export RCLONE="$HOME/.Library/rclone"

# shellcheck source=./bin/root_user_config.sh
source "$DEV_RCLONE"/bin/root_user_config.sh

create_library_symlink

cp -f "$DEV_RCLONE"/rclone-mount.service "$RCLONE"
cp -f "$DEV_RCLONE"/init_rclone.sh "$RCLONE"
cp -rf "$DEV_RCLONE"/bin "$RCLONE"

echo "Rclone configured"