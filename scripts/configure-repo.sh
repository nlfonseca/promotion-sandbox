#!/usr/bin/env bash
# Idempotent repo configuration: default branch, merge methods, labels, rulesets.
#   ./scripts/configure-repo.sh [owner/repo]
#
# BYPASS decides who may push straight to develop/beta/master (the promotion identity):
#   app   (default) the GitHub App whose id is in repo variable PROMOTE_APP_ID (or env)
#   admin           the Repository-admin role; bootstrap fallback before the App exists
#   none            nobody; used by TESTING.md Test 9 to prove the push gets rejected
set -euo pipefail
REPO=${1:-nlfonseca/promotion-sandbox}
BYPASS=${BYPASS:-app}
here=$(cd "$(dirname "$0")" && pwd)
rulesets="$here/../.github/rulesets"

echo "→ default branch + merge methods"
gh repo edit "$REPO" --default-branch develop \
  --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false

echo "→ labels"
label() { gh label create "$1" -R "$REPO" --color "$2" --description "$3" --force >/dev/null; echo "  $1"; }
label promotion 0E8A16 "Auto-opened promotion PR (fast-forward only)"
label promote   5319E7 "Fast-forward this promotion now"
label backflow  FBCA04 "Hotfix backflow: merge with a merge commit"

case "$BYPASS" in
  app)
    app_id=${PROMOTE_APP_ID:-$(gh variable get PROMOTE_APP_ID -R "$REPO" 2>/dev/null || true)}
    if [ -z "$app_id" ]; then
      echo "PROMOTE_APP_ID is not set (repo variable or env). Create the App first (README → Setup), or run with BYPASS=admin." >&2
      exit 1
    fi
    actors="[{\"actor_id\": $app_id, \"actor_type\": \"Integration\", \"bypass_mode\": \"always\"}]"
    who="GitHub App #$app_id" ;;
  admin) actors='[{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]'; who="repository admins" ;;
  none)  actors='[]'; who="nobody" ;;
  *) echo "BYPASS must be app, admin or none" >&2; exit 1 ;;
esac

echo "→ rulesets (bypass actor: $who)"
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
# The same identity bypasses all three branches: it fast-forwards beta/master for
# releases and hotfixes, and develop for hotfix backflows.
for file in promotion-branches.json develop.json; do
  tmp=$(mktemp)
  jq --argjson actors "$actors" '.bypass_actors = $actors' "$rulesets/$file" > "$tmp"
  apply_ruleset "$tmp"
  rm -f "$tmp"
done
