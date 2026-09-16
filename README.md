# Promotion sandbox

Prototype of fast-forward release promotion: `develop → beta → master` with no cherry-picks and no merge commits, so every branch holds the same SHAs. Promoting is one label click on a PR that opens itself.

## Branch model

| Branch | Role | Moves by |
|---|---|---|
| `develop` | integration; feature PRs squash-merge here | merge button (squash) |
| `beta` | preview pointer | fast-forward from `develop` |
| `master` | production pointer | fast-forward from `beta` |

`beta` and `master` never hold commits of their own. Every push to `master` produces a tag and a GitHub Release.

## Promoting

1. Push to `develop`. The `open-promotion-pr` workflow opens **Release: develop → beta**, or refreshes it if it is already open. The body lists the commits waiting.
2. A code owner (@nlfonseca or @fabioop) approves. The PR is authored by the token owner, and nobody can approve their own PR, so in this sandbox @fabioop approves.
3. Add the `promote` label. The `promote` workflow waits for green checks, fast-forwards `beta`, comments on the PR, and the PR closes itself.
4. The push to `beta` opens **Release: beta → master**. Same steps. The push to `master` publishes the release.

The merge button is intentionally useless on `beta` and `master`. The required `promotion-gate` check is red until the `promote` label is on, and by then the fast-forward has already landed.

## Hotfixes

Branch from `master`, open a PR into `master`, get an approval, add `promote`. The executor only requires the head to be a descendant of `master`, so a hotfix branch fast-forwards like any promotion. Then:

1. `hotfix-backflow` sees that `master` has a commit `develop` lacks and opens **Hotfix backflow: master → beta**. Approve it and merge with **Create a merge commit**.
2. That merge opens **Hotfix backflow: beta → develop**. Merge it the same way.
3. `sync-check` is red from the hotfix until step 2 is done. That is the drift alarm working.

Never cherry-pick a hotfix back. The copy has a different hash, `develop` never becomes a descendant of `master`, and the next fast-forward refuses.

## Workflows

| File | Trigger | Does |
|---|---|---|
| `open-promotion-pr.yml` | push to `develop`, `beta` | opens or refreshes the promotion PR into the next branch |
| `promotion-gate.yml` | PRs into `beta`, `master` | required check; red unless `promote` label (or a `master → beta` backflow) |
| `promote.yml` | `promote` label, approving review, manual | guards, waits for green checks, `git merge --ff-only`, push, comments |
| `release.yml` | push to `master` | Conventional Commits version bump, tag, GitHub Release with grouped notes |
| `hotfix-backflow.yml` | push to `master` not in `develop`; backflow PR merged | opens the backflow merge PRs |
| `sync-check.yml` | push to `beta`, `master`; daily | fails if `master ⊄ beta` or `beta ⊄ develop` |

Every push and PR creation uses the `PROMOTE_TOKEN` secret, never `GITHUB_TOKEN`. Events caused by `GITHUB_TOKEN` do not trigger workflows, so the chain would stop silently after the first step. On the company repo, swap the secret for a GitHub App token from `actions/create-github-app-token`. It is one `env` line per workflow.

`promote.yml` runs on `pull_request_target`, so `beta` and `master` execute their own copy of it. Changes to it take effect on a branch once they are promoted there.

## Setup

Done by `scripts/configure-repo.sh`: default branch, merge methods (squash and merge commit, no rebase), labels `promotion`, `promote`, `backflow`, branch protection. Also done: public repo, three branches at one commit, baseline tag `v0.0.0`, collaborator invite for @fabioop.

Still manual:

1. **Token.** Create a fine-grained PAT at <https://github.com/settings/personal-access-tokens/new>, repository access limited to this repo, permissions: Contents read/write, Pull requests read/write, Issues read/write (labels and comments), Workflows read/write (promotions push commits that touch `.github/workflows`), Checks read. Then store it:

   ```bash
   gh secret set PROMOTE_TOKEN -R nlfonseca/promotion-sandbox
   ```

2. **Collaborator.** @fabioop accepts the invitation. The role must be Write: a read-only reviewer's approval does not satisfy a required review.
3. Optional: connect Vercel to see previews follow the branch pointers.

### Branch protection as configured

- `beta`, `master`: PR required, 1 approval, code-owner review, stale approvals dismissed, required check `promotion-gate`, admins included, bypass-PR allowance for @nlfonseca (the PAT identity). Required checks still apply to that direct push, which is why the fast-forwarded SHA must carry a green `promotion-gate`.
- `develop`: PR required, no approvals, no bypass entry, admins not enforced.

To prove the bypass is what makes the push work: set `"users": []` in `.github/branch-protection/promotion-branch.json`, re-run the script, re-add `promote` on a promotion PR, watch the push get rejected, then restore and re-run.

## Test plan

See [TESTING.md](TESTING.md): one scenario per section, "do this, expect this".

## Recovery

- Label added but nothing happened: open the `promote` run in Actions. Remove and re-add `promote` to retry, or run `promote` manually with the PR number (Actions → promote → Run workflow).
- Fast-forward refused: the base has commits the head lacks. Open backflow merge PRs in the direction `master → beta → develop`; `hotfix-backflow` does this automatically for hotfixes.
- On a brand-new company repo where `master` already diverged and nothing depends on it yet: `git push --force origin develop:beta develop:master` once, with protection temporarily off. Never after go-live.
