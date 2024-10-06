#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/root-password.sh
source "$HELPERS"/root-password.sh
# shellcheck source=./../../BashLib/src/helpers/tool_check_script.sh
source "$HELPERS"/tool_check_script.sh

check_and_install_expect

create_library_symlink() {
  local sudo_password
  sudo_password="$(getRootPassword)"

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

create_projects_symlink() {
  local sudo_password
  sudo_password="$(getRootPassword)"

  # Check if the symbolic link exists
  if [ ! -L /root/.Projects ]; then
    # Use expect to provide sudo password and create the symlink
    expect << EOF
      spawn sudo ln -sf "$HOME"/.Library /root/.Projects
      expect "password:"
      send "$sudo_password\r"
      expect eof
EOF
    echo "Symlink created: /root/.Projects"
  else
    echo "Symlink already exists: /root/.Projects"
  fi
}

# Export the function to make it available to other scripts
export -f create_library_symlink
