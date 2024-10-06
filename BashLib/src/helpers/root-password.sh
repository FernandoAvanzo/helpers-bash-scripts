#!/bin/bash

getRootPassword() {
  local psw
  local secret_iten
  local vault_name
  vault_name="Workstation_Automation"
  secret_iten="$ROOT_SECRET_NAME"
  psw="$(op item get "$secret_iten" --format human-readable --fields password --reveal --vault $vault_name)"
  echo "$psw"
}
