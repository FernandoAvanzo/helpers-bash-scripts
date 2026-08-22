#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-iam-inventory-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT_DIR"

aws sts get-caller-identity > "$OUT_DIR/caller-identity.json"
aws iam get-account-summary > "$OUT_DIR/account-summary.json"
aws iam get-account-authorization-details > "$OUT_DIR/account-authorization-details.json"
aws iam list-users > "$OUT_DIR/users.json"
aws iam list-roles > "$OUT_DIR/roles.json"
aws iam list-policies --scope Local > "$OUT_DIR/customer-managed-policies.json"
aws iam list-open-id-connect-providers > "$OUT_DIR/oidc-providers.json"
aws iam list-saml-providers > "$OUT_DIR/saml-providers.json"

aws iam generate-credential-report >/dev/null
for _ in $(seq 1 12); do
  if aws iam get-credential-report --query Content --output text > "$OUT_DIR/credential-report.b64" 2>/dev/null; then
    base64 --decode "$OUT_DIR/credential-report.b64" > "$OUT_DIR/credential-report.csv"
    rm "$OUT_DIR/credential-report.b64"
    break
  fi
  sleep 5
done

aws iam list-users --query 'Users[].UserName' --output text | tr '\t' '\n' | while read -r user; do
  [[ -z "$user" ]] && continue
  aws iam list-access-keys --user-name "$user" > "$OUT_DIR/access-keys-$user.json"
done

echo "IAM inventory saved to $OUT_DIR"
