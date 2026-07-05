#!/usr/bin/env bash
# Installs production dependencies for every Lambda so terraform's
# archive_file zips complete bundles.
set -euo pipefail

cd "$(dirname "$0")"

for lambda_dir in lambdas/*/; do
  echo "==> ${lambda_dir}"
  (cd "${lambda_dir}" && npm install --omit=dev --no-audit --no-fund)
done

echo "Done. Now run: cd terraform && terraform apply"
