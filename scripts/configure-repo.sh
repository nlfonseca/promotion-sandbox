#!/usr/bin/env bash
# Idempotent repo configuration: default branch, merge methods, labels, branch
# protection. Run it again after editing the JSON under .github/branch-protection.
#   ./scripts/configure-repo.sh [owner/repo]
# BYPASS_USER = the account that owns PROMOTE_TOKEN (gets the bypass-PR allowance).
set -euo pipefail
REPO=${1:-nlfonseca/promotion-sandbox}
BYPASS_USER=${BYPASS_USER:-nlfonseca}
here=$(cd "$(dirname "$0")" && pwd)
protection="$here/../.github/branch-protection"

echo "→ default branch + merge methods (squash for features, merge commit for backflow, no rebase)"
gh repo edit "$REPO" --default-branch develop \
  --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false

echo "→ labels"
label() { gh label create "$1" -R "$REPO" --color "$2" --description "$3" --force >/dev/null; echo "  $1"; }
label promotion 0E8A16 "Auto-opened promotion PR (fast-forward only)"
label promote   5319E7 "Fast-forward this promotion now"
label backflow  FBCA04 "Hotfix backflow: merge with a merge commit"

echo "→ branch protection"
for branch in beta master; do
  sed "s/BYPASS_USER/$BYPASS_USER/" "$protection/promotion-branch.json" \
    | gh api -X PUT "repos/$REPO/branches/$branch/protection" --input - >/dev/null
  echo "  $branch (PR + 1 code-owner approval + promotion-gate, admins enforced, bypass-PR: $BYPASS_USER)"
done
gh api -X PUT "repos/$REPO/branches/develop/protection" --input "$protection/develop.json" >/dev/null
echo "  develop (PR required, no approvals, no bypass entry)"
