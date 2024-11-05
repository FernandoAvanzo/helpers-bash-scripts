#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../BashLib/src/helpers/root-password.sh
source "$HELPERS/root-password.sh"

declare -r linux_bin="$MY_CLI/linux/bin"
password="$(getRootPassword)"

check_os_and_run() {
  if [ "$(uname -s)" = "Linux" ]; then
    if grep -q "Ubuntu" /etc/os-release; then
      echo "$password" | sudo -S "$linux_bin"/ubuntu-debullshit.sh
    else
      echo "This is not an Ubuntu system."
    fi
  else
    echo "This is not a Linux system."
  fi
}

check_os_and_run

#Install Script
#echo "$(get-root-psw)" | sudo -S ln -sf "$MY_CLI"/Linux/clean_ubuntu.sh /usr/bin/clean_ubuntu
