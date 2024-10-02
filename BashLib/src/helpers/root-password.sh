#!/bin/bash

getRootPassword() {
  local psw
  local vault
  vault="$ROOT_VAULT_NAME"
  psw="$(op item get "$vault" --format human-readable --fields password --reveal)"
  echo "$psw"
}