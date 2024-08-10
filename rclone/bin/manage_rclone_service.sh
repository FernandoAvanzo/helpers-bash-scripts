#!/bin/bash

manage_rclone_service() {
  # Reload the systemd manager configuration
  if ! systemctl daemon-reload; then
    echo "Failed to reload the systemd daemon."
    return 1
  fi

  # Enable the rclone service
  if ! systemctl enable rclone-mount.service; then
    echo "Failed to enable rclone-mount.service."
    return 1
  fi

  # Start the rclone service
  if ! systemctl start rclone-mount.service; then
    echo "Failed to start rclone-mount.service."
    return 1
  fi

  echo "rclone-mount.service successfully reloaded, enabled, and started."
  return 0
}