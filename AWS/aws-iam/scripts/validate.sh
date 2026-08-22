#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Parsing JSON policies"
find policies -type f -name '*.json' -print0 | while IFS= read -r -d '' file; do
  jq empty "$file"
done

echo "[2/4] Linting CloudFormation"
if command -v cfn-lint >/dev/null 2>&1; then
  cfn-lint cloudformation/*.yaml
else
  echo "cfn-lint not installed; skipping."
fi

echo "[3/4] Scanning for obvious credential material"
if grep -RInE '(AKIA|ASIA)[A-Z0-9]{16}|aws_secret_access_key|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' \
  --exclude-dir=.git .; then
  echo "Potential secret material found."
  exit 1
fi

echo "[4/4] IAM Access Analyzer validation"
if aws sts get-caller-identity >/dev/null 2>&1; then
  find policies/permissions-boundaries -type f -name '*.json' -print0 | while IFS= read -r -d '' file; do
    echo "Validating IDENTITY_POLICY: $file"
    aws accessanalyzer validate-policy \
      --policy-document "file://$file" \
      --policy-type IDENTITY_POLICY \
      --output table
  done

  find policies/scps -type f -name '*.json' -print0 | while IFS= read -r -d '' file; do
    echo "Validating SERVICE_CONTROL_POLICY: $file"
    aws accessanalyzer validate-policy \
      --policy-document "file://$file" \
      --policy-type SERVICE_CONTROL_POLICY \
      --output table
  done
else
  echo "No usable AWS credentials; skipping live Access Analyzer validation."
fi

echo "Validation complete."
