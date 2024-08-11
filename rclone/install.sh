#!/bin/bash
#dev
export DEV_RCLONE="$HOME/Projects/helpers-bash-scripts/rclone"
#prod
export RCLONE="$HOME/.Library/rclone"

sudo ln -sf "$HOME"/.Library /root/.Library

cp -f "$DEV_RCLONE"/rclone-mount.service "$RCLONE"
cp -f "$DEV_RCLONE"/init_rclone.sh "$RCLONE"
cp -rf "$DEV_RCLONE"/bin "$RCLONE"

ls -al "$RCLONE"
ls -al "$RCLONE"/bin

sudo ls -al /root/.Library