# Promotion sandbox

Prototype of fast-forward release promotion: `develop → beta → master` with no cherry-picks and no merge commits, so every branch holds the same SHAs. Promoting is one label click on a PR that opens itself. All automation acts as a GitHub App, never as a person.

## Branch model

| Branch | Role | Moves by |
|---|---|---|
| `develop` | integration; feature PRs squash-merge here | merge button (squash) |
| `beta` | preview pointer | fast-forward from `develop` |
| `master` | production pointer | fast-forward from `beta` |

`beta` and `master` never hold commits of their own. Every push to `master` produces a tag and a GitHub Release.

## Promoting

1. Push to `develop`. The `open-promotion-pr` workflow opens **Release: develop → beta** as the App's bot user, or refreshes it if it is already open. The body lists the commits waiting.
2. A code owner (@nlfonseca or @fabioop) approves. The PR is authored by the bot, so any code owner can approve it, including you.
3. Add the `promote` label. The `promote` workflow waits for green checks, fast-forwards `beta`, comments on the PR, and the PR closes itself.
4. The push to `beta` opens **Release: beta → master**. Same steps. The push to `master` publishes the release.

The merge button is intentionally useless on `beta` and `master`. The required `promotion-gate` check is red until the `promote` label is on, and `promote` itself is a required check too, so the button stays disabled while the executor runs and stays blocked if it fails. When it succeeds there is nothing left to merge.

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

Every push and PR creation uses a short-lived token minted from the GitHub App by `actions/create-github-app-token`, never `GITHUB_TOKEN`: events caused by `GITHUB_TOKEN` do not trigger workflows, so the chain would stop silently after the first step. The App is only an identity with permissions. The logic lives in the workflows, and the identity does not die when a person leaves the team. Each workflow mints the token in one step named "Mint promotion token" and hands it to the steps that push or open PRs.

`promote.yml` runs on `pull_request_target`, so `beta` and `master` execute their own copy of it. Changes to it take effect on a branch once they are promoted there.

## Setup

### 1. GitHub App (one time, in the browser)

Sandbox: <https://github.com/settings/apps/new> under your account. Company repo: the same form under the organisation's settings, done by infra. Everything below is identical.

- **Name:** globally unique, e.g. `promotion-sandbox-bot`. **Homepage URL:** this repo. **Webhook:** untick *Active*.
- **Repository permissions:** Contents *Read and write*, Pull requests *Read and write*, Issues *Read and write* (labels and comments), Workflows *Read and write* (promotions push commits that touch `.github/workflows`), Checks *Read-only*. Metadata read is added automatically.
- **Where can this App be installed:** *Only on this account*.
- Create it, then on its General page note the numeric **App ID** and click **Generate a private key** (downloads a `.pem`).
- Left menu **Install App** → your account → *Only select repositories* → `promotion-sandbox`.

Store the two values:

```bash
gh variable set PROMOTE_APP_ID -R nlfonseca/promotion-sandbox --body "<app id>"
```

```bash
gh secret set PROMOTE_APP_PRIVATE_KEY -R nlfonseca/promotion-sandbox < ~/Downloads/<name>.private-key.pem
```

### 2. Rulesets, labels, merge methods

```bash
./scripts/configure-repo.sh
```

Idempotent. It reads `PROMOTE_APP_ID` and makes the App the only bypass actor on `beta`/`master`. `BYPASS=admin` is the bootstrap fallback before the App exists. `BYPASS=none` is used by Test 9.

### 3. Collaborators

@fabioop has the Write role, which a code-owner approval requires. Since the bot authors the promotion PRs, you can approve them yourself; a second owner is optional.

### Branch protection as configured

Rulesets, defined in `.github/rulesets/` and applied by the script:

- `promotion-branches` (`beta`, `master`): PR required, 1 approval, code-owner review, stale approvals dismissed, only "Create a merge commit" offered by the button (that is for backflows), required checks `promotion-gate` and `promote`, no force-push, no deletion. One bypass actor: the GitHub App (`actor_type: Integration`), mode "always". Everyone else, admins and code owners included, cannot push to these branches.
- `develop`: PR required, no approvals, squash or merge commit, no bypass actors, no force-push.

Because the bypass actor skips the rules on a direct push, the `promote` workflow is what guarantees green checks: it refuses to push until every check on the head commit has passed.

## Test plan

See [TESTING.md](TESTING.md): one scenario per section, "do this, expect this".

## Recovery

- Label added but nothing happened: open the `promote` run in Actions. Remove and re-add `promote` to retry, or run `promote` manually with the PR number (Actions → promote → Run workflow). A manual run needs the code-owner approval but not the label, and it executes the copy of `promote.yml` from the branch you pick, so a fix to the workflow itself can be applied by running it from `develop`:

  ```bash
  gh workflow run promote.yml -R nlfonseca/promotion-sandbox --ref develop -f pr=<number>
  ```
- `Input required and not supplied: app-id` or `Bad credentials` in a run: the `PROMOTE_APP_ID` variable or the `PROMOTE_APP_PRIVATE_KEY` secret is missing or wrong, or the App is not installed on the repo. Redo Setup step 1.
- Fast-forward refused: the base has commits the head lacks. Open backflow merge PRs in the direction `master → beta → develop`; `hotfix-backflow` does this automatically for hotfixes.
- On a brand-new company repo where `master` already diverged and nothing depends on it yet: `git push --force origin develop:beta develop:master` once, with the ruleset temporarily off. Never after go-live.
Hello from feature 1.
