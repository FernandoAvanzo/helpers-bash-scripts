#!/bin/bash

create_library_symlink() {
  local sudo_password="fer010486"

  # Check if the symbolic link exists
  if [ ! -L /root/.Library ]; then
    # Use expect to provide sudo password and create the symlink
    expect << EOF
      spawn sudo ln -sf "$HOME"/.Library /root/.Library
      expect "password:"
      send "$sudo_password\r"
      expect eof
EOF
    echo "Symlink created: /root/.Library"
  else
    echo "Symlink already exists: /root/.Library"
  fi
}

# Export the function to make it available to other scripts
export -f create_library_symlink