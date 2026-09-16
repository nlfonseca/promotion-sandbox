# Testing the promotion flow

Each test is "do this, then expect this". Run them in order the first time. Everything happens on GitHub: <https://github.com/nlfonseca/promotion-sandbox>.

**Before you start**

- [ ] The GitHub App exists and is installed on the repo, `PROMOTE_APP_ID` and `PROMOTE_APP_PRIVATE_KEY` are stored, and `./scripts/configure-repo.sh` has been run (README → Setup).
- [ ] You are a code owner. The promotion PRs are authored by the App's bot user, so you can approve them yourself. @fabioop (Write role) can play the second reviewer.

Handy commands (run from a clone):

```bash
# Where do the three branches point? Same SHA = in sync.
git fetch origin && git rev-parse --short origin/develop origin/beta origin/master
```

```bash
# Watch workflow runs as they happen
gh run list -R nlfonseca/promotion-sandbox --limit 10
```

---

## Test 1: the promotion PR opens by itself

**Do**

```bash
git checkout develop && git pull && git checkout -b feature/hello
echo "Hello from feature 1" >> README.md
git commit -am "feat: add hello line" && git push -u origin feature/hello
gh pr create --base develop --fill && gh pr merge --squash --delete-branch
```

**Expect**

- Actions → `open-promotion-pr` run is green.
- A PR **Release: develop → beta** exists, authored by the bot, with label `promotion`, listing `feat: add hello line`.
- Actions → `promotion-gate` run on that PR is **red** (no `promote` label yet). That is correct.

---

## Test 2: more commits join the same PR, no duplicates

**Do** the same as Test 1 with a second branch, e.g. `fix: typo in hello line`.

**Expect**

- Still exactly one open **Release: develop → beta** PR.
- Its description now lists two commits.

---

## Test 3: the merge button is blocked

**Do** open the promotion PR in the browser.

**Expect**

- "Merge" is disabled: required check `promotion-gate` failing, review required.
- Only "Create a merge commit" is offered on `beta`/`master`; squash and rebase are hidden by the ruleset.
- No "bypass rules" checkbox for anyone: the App is the only bypass actor.

---

## Test 4: the label alone is not enough

**Do** add the `promote` label **before** any approval.

**Expect**

- `promotion-gate` re-runs and goes green (label present).
- `promote` run finishes with a notice "Waiting for a code-owner approval". Nothing moved.
- Remove the label again before Test 5, so you see the normal order.

---

## Test 5: approve + label = fast-forward

**Do**

1. As a code owner: Files changed → Review → **Approve**.
2. Add the `promote` label.

**Expect**

- `promote` run: guards pass, waits for checks, `git merge --ff-only`, push.
- The PR gets a comment "✅ Fast-forwarded `beta` to <sha>" and closes itself (state "Closed", not "Merged": there was nothing to merge).
- `git rev-parse origin/develop origin/beta` prints the same SHA.
- `sync-check` run is green.
- History on `beta` is linear: no merge commit, same hashes as `develop`.

---

## Test 6: the chain continues to master

**Do** nothing. This is what the App token is for.

**Expect**

- The push to `beta` (made by the App, not by `GITHUB_TOKEN`) opened **Release: beta → master** on its own.
- If it did not open, the push was made with the wrong token. See README → Workflows.

---

## Test 7: release with the right version and notes

**Do** approve and label **Release: beta → master** exactly like Test 5.

**Expect**

- `master` now points at the same SHA as `beta` and `develop`.
- `release` run is green; the Releases page shows a new tag with the minor number bumped (a `feat:` bumps minor from the previous tag, e.g. `v0.0.1 → v0.1.0`).
- Notes are grouped: Features (`feat: add hello line`), Fixes (`fix: typo...`), plus a compare link.
- A `fix:`-only promotion later bumps patch; a `feat!:` or `BREAKING CHANGE` bumps major.

---

## Test 8: hotfix straight to production, then backflow

**Do**

```bash
git checkout master && git pull && git checkout -b hotfix/urgent
echo "Hotfix applied" >> README.md
git commit -am "fix: urgent production fix" && git push -u origin hotfix/urgent
gh pr create --base master --title "fix: urgent production fix" --body "hotfix"
```

Then approve and add `promote`, like Test 5.

**Expect, in order**

1. `master` fast-forwards to the hotfix commit; a patch release is published.
2. `sync-check` goes **red** (`master` has a commit `beta` lacks). Expected: this is the alarm.
3. `hotfix-backflow` opens **Hotfix backflow: master → beta** with label `backflow`. `promotion-gate` is green for it (backflow is the one allowed merge).
4. Approve; merge it with **Create a merge commit** (the only option offered).
5. **Hotfix backflow: beta → develop** opens by itself. Merge it, again with a merge commit.
6. `sync-check` (re-run it manually: Actions → sync-check → Run workflow) is green again.
7. `git log --oneline --graph origin/develop -5` shows the hotfix and one merge commit per backflow step, same hashes on all three branches.

The push to `beta` in step 4 also opens a new **Release: beta → master** (beta now has the merge commit). Promote it whenever you like; it fast-forwards cleanly.

---

## Test 9: the bypass entry is what lets the App push

**Do**

1. Remove the bypass actor: `BYPASS=none ./scripts/configure-repo.sh`
2. Create a promotion (Tests 1 + 5).

**Expect**

- `promote` run fails at the **Push** step with `GH013: Repository rule violations ... Changes must be made through a pull request`.
- The PR gets a "❌ ... push was rejected ..." comment and the `promote` label is removed.
- Restore with `./scripts/configure-repo.sh`, re-add `promote`: the push goes through.

This is the exact thing to ask infra for on the company repo: the GitHub App as a bypass actor on the `beta`/`master` ruleset.

---

## Test 10: manual recovery

**Do** Actions → `promote` → Run workflow → enter the PR number.

**Expect** the same guards as the label path. It is the escape hatch if a label event was missed.

---

## What "in sync" looks like

```
develop  a1b2c3d  ← everything lands here
beta     a1b2c3d  ← same SHA after promotion
master   a1b2c3d  ← same SHA after promotion, tagged vX.Y.Z
```

Any branch pointing at a commit the branch above it does not contain is drift, and `sync-check` says so.
