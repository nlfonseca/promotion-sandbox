#!/usr/bin/env bash
# Idempotent repo configuration: default branch, merge methods, labels, rulesets.
# Run it again after editing the JSON under .github/rulesets.
#   ./scripts/configure-repo.sh [owner/repo]
set -euo pipefail
REPO=${1:-nlfonseca/promotion-sandbox}
here=$(cd "$(dirname "$0")" && pwd)
rulesets="$here/../.github/rulesets"

echo "→ default branch + merge methods (squash for features, merge commit for backflow, no rebase)"
gh repo edit "$REPO" --default-branch develop \
  --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false

echo "→ labels"
label() { gh label create "$1" -R "$REPO" --color "$2" --description "$3" --force >/dev/null; echo "  $1"; }
label promotion 0E8A16 "Auto-opened promotion PR (fast-forward only)"
label promote   5319E7 "Fast-forward this promotion now"
label backflow  FBCA04 "Hotfix backflow: merge with a merge commit"

echo "→ rulesets"
apply_ruleset() {
  local file=$1 name id
  name=$(jq -r .name "$file")
  id=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$REPO/rulesets/$id" --input "$file" >/dev/null
    echo "  $name (updated #$id)"
  else
    id=$(gh api -X POST "repos/$REPO/rulesets" --input "$file" --jq .id)
    echo "  $name (created #$id)"
  fi
}
apply_ruleset "$rulesets/promotion-branches.json"
apply_ruleset "$rulesets/develop.json"
