#!/bin/bash
export HELPERS="$MY_CLI/BashLib/src/helpers"

# shellcheck source=./helpers/root-password.sh
source "$HELPERS"/root-password.sh

getRootPassword
