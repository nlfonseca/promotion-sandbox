#!/usr/bin/env bash
# Usage: open-backflow-pr.sh <head> <base>
# Opens a merge (not fast-forward) PR head → base, unless one is already open
# or base already contains head. Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail
head=$1
base=$2

if [ -z "${GH_TOKEN:-}" ]; then
  echo "::error::Secret PROMOTE_TOKEN is not set (see README → Setup)."
  exit 1
fi

ahead=$(gh api "repos/$GITHUB_REPOSITORY/compare/$base...$head" --jq .ahead_by)
if [ "$ahead" = 0 ]; then
  echo "$base already contains $head: nothing to flow back."
  exit 0
fi

existing=$(gh pr list -R "$GITHUB_REPOSITORY" --base "$base" --head "$head" --state open \
  --json number --jq '.[0].number // empty')
if [ -n "$existing" ]; then
  echo "Backflow PR #$existing ($head → $base) is already open."
  exit 0
fi

{
  echo "Flows a hotfix back from \`$head\` into \`$base\` so every branch contains it (\`$ahead\` commit(s))."
  echo
  echo "**Merge this with \"Create a merge commit\".** Do not squash or rebase: the copied commit would get a new hash, \`$base\` would never become a descendant of \`$head\`, \`sync-check\` would stay red and the next fast-forward promotion would refuse."
  if [ "$base" = beta ]; then
    echo
    echo "When this PR is merged, a \`beta → develop\` backflow PR opens automatically."
  fi
} > body.md

gh pr create -R "$GITHUB_REPOSITORY" --base "$base" --head "$head" \
  --title "Hotfix backflow: $head → $base" --body-file body.md --label backflow
