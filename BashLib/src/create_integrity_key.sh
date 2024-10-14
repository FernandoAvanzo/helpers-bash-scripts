#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/shell-utils.sh
source "$HELPERS/shell-utils.sh"

file=$1

generate_sha1_checksum "$file"

#Install Script
# echo $(get-root-psw) | sudo -S ln -sf $MY_CLI/BashLib/src/create_integrity.sh /usr/bin/create_integrity
