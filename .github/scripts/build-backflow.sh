#!/usr/bin/env bash
# Usage: build-backflow.sh <up>:<down> [...]      e.g. master:beta beta:develop
# For each pair where <up> has commits <down> lacks, builds backflow/<up>-into-<down>
# on top of <down> and opens its PR. Needs GH_TOKEN, GITHUB_REPOSITORY and a full clone
# whose origin credentials can push (the GitHub App token).
set -euo pipefail

git config user.name "${BOT:-promotion-bot}[bot]"
git config user.email "${BOT:-promotion-bot}[bot]@users.noreply.github.com"
git fetch -q origin '+refs/heads/*:refs/remotes/origin/*' --prune

failed=0
backflow() {
  local up=$1 down=$2 branch="backflow/$1-into-$2" legacy existing

  if git merge-base --is-ancestor "origin/$up" "origin/$down"; then
    echo "$down already contains $up."
    return 0
  fi

  # A plain <up> → <down> PR that can still fast-forward needs nothing from us.
  legacy=$(gh pr list -R "$GITHUB_REPOSITORY" --base "$down" --head "$up" --state open \
    --json number --jq '.[0].number // empty')
  if [ -n "$legacy" ] && git merge-base --is-ancestor "origin/$down" "origin/$up"; then
    echo "PR #$legacy ($up → $down) can fast-forward as is: approve it and add 'promote'."
    return 0
  fi

  # Keep a branch that already contains both tips: freshly built, or resolved by hand.
  if git rev-parse -q --verify "origin/$branch" >/dev/null \
    && git merge-base --is-ancestor "origin/$down" "origin/$branch" \
    && git merge-base --is-ancestor "origin/$up" "origin/$branch"; then
    echo "$branch is up to date."
  else
    git checkout -q -B "$branch" "origin/$down"
    if ! git merge --no-edit -m "chore: merge $up into $down (hotfix backflow)" "origin/$up"; then
      git merge --abort
      echo "::error::Cannot merge $up into $down automatically (conflicts). Build the branch by hand; see the commands in this log."
      echo "  git fetch origin && git checkout -B $branch origin/$down && git merge origin/$up   # resolve, commit"
      echo "  git push -f origin $branch"
      echo "  gh pr create --base $down --head $branch --label backflow --title 'Hotfix backflow: $up → $down'"
      echo "Then approve the PR and add the 'promote' label as usual."
      failed=1
      return 0
    fi
    git push -q origin "+HEAD:refs/heads/$branch"
    echo "Built $branch at $(git rev-parse --short HEAD)."
  fi

  existing=$(gh pr list -R "$GITHUB_REPOSITORY" --base "$down" --head "$branch" --state open \
    --json number --jq '.[0].number // empty')
  if [ -n "$existing" ]; then
    echo "Backflow PR #$existing is open."
    return 0
  fi
  {
    echo "Flows the hotfix from \`$up\` back into \`$down\` so every branch contains the same commit."
    echo
    echo "\`$branch\` is built on top of \`$down\`, so \`$down\` can fast-forward to it. Commit hashes are preserved, which is what restores \`master ⊂ beta ⊂ develop\`. A cherry-pick or a squash would not."
    echo
    echo "### How to land it"
    echo "1. A code owner approves this PR."
    echo "2. Someone adds the \`promote\` label."
    echo
    echo "**The merge button is blocked on purpose** (\`promotion-gate\` is red by design). If \`$down\` moves before this is promoted, the \`hotfix-backflow\` workflow rebuilds the branch."
    if [ -n "$legacy" ]; then echo; echo "Supersedes #$legacy, which cannot fast-forward. Close that one."; fi
  } > body.md
  gh pr create -R "$GITHUB_REPOSITORY" --base "$down" --head "$branch" \
    --title "Hotfix backflow: $up → $down" --body-file body.md --label backflow
}

for pair in "$@"; do
  echo "::group::${pair%%:*} → ${pair##*:}"
  backflow "${pair%%:*}" "${pair##*:}"
  echo "::endgroup::"
done
exit "$failed"
