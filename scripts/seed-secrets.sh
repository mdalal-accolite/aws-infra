#!/usr/bin/env bash
#
# Fills in the Secrets Manager values that Terraform deliberately leaves as
# placeholders. Run this ONCE per environment, from your laptop, after
# 40-data and 36-secrets have been applied.
#
#   ./scripts/seed-secrets.sh stage
#
# Terraform has `ignore_changes = [secret_string]` on these, so it will never
# overwrite what this script writes.

set -euo pipefail

ENV="${1:-}"
if [[ -z "$ENV" ]]; then echo "usage: $0 <stage|prod>" >&2; exit 1; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="scribl/${ENV}"

echo "==> Reading endpoints from Terraform state"
cd "$ROOT/stacks/40-data"
DB_SECRET_ARN=$(terraform output -raw db_master_secret_arn)
DB_PROXY=$(terraform output -raw db_proxy_endpoint)
DB_DIRECT=$(terraform output -raw db_endpoint)

echo "==> Reading the RDS-managed master password"
CREDS=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" \
          --query SecretString --output text)
DB_USER=$(echo "$CREDS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["username"])')
DB_PASS=$(echo "$CREDS" | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')

PROXY_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_PROXY}:5432/scribl?sslmode=require"
DIRECT_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_DIRECT}:5432/scribl?sslmode=require"

put() {
  echo "    $1"
  aws secretsmanager put-secret-value --secret-id "$1" --secret-string "$2" >/dev/null
}

echo "==> Writing secrets under ${PREFIX}/"
put "${PREFIX}/api" "$(python3 - "$PROXY_URL" <<'PY'
import json,secrets,sys
print(json.dumps({"DATABASE_URL": sys.argv[1], "INTERNAL_JOB_SECRET": secrets.token_hex(32)}))
PY
)"
put "${PREFIX}/db/database-url"                 "$PROXY_URL"
put "${PREFIX}/migrate/database-url"            "$DIRECT_URL"
put "${PREFIX}/admin-api/session-cookie-secret" "$(openssl rand -hex 32)"
put "${PREFIX}/admin-api/origin-verify"         "$(openssl rand -hex 32)"

echo
echo "Left alone on purpose:"
echo "  ${PREFIX}/admin-api/idp-client-secret  - Terraform wrote the Cognito client id/secret"
echo "  ${PREFIX}/db-proxy/credentials         - used by the RDS Proxy itself"
echo "  ${PREFIX}/redis/auth-token             - Terraform generated this"
echo "  ${PREFIX}/ses/smtp-credentials         - written by the 38-email component"
echo
echo "Done. Verify with:"
echo "  aws secretsmanager list-secrets --filters Key=name,Values=${PREFIX} --query 'SecretList[].Name' --output table"
