#!/bin/bash

export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./../../BashLib/src/helpers/shell-utils.sh
source "$HELPERS/shell-utils.sh"

file=$1
sha_512_key="$(generate_sha1_checksum "$file")"
echo "sha512-$(base64_encrypt "$sha_512_key")"

#Install Script
# echo $(get-root-psw) | sudo -S ln -sf $MY_CLI/BashLib/src/create_integrity_key.sh /usr/bin/create_integrity_key
#Remove script
# echo $(get-root-psw) | sudo -S rm -f /usr/bin/create_integrity_key
