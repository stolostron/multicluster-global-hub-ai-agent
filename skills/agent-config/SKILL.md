---
name: agent-config
description: Agent workflow defaults for GitHub PR work and GitLab GH release pipeline handoffs — DCO sign-off, pre-push CodeRabbit triage and gofmt/tests/Sonar checks, no sensitive data in PR text, PR comments after push, merge pipeline fixes to the run branch (main) before telling the user to rerun. Use when creating or updating PRs, fixing acm-global-hub-release GitLab jobs, pushing fixes, babysitting CI, retesting, or when the user asks about agent config or PR conventions.
---

# Agent Config

## NO code changes without a PR — ever

**Never push code directly to any branch** (`main`, `release-*`, or any other) using the GitHub contents API, `git push`, or any other mechanism that bypasses a pull request.

Every code change — no matter how small or "obviously correct" — must go through a PR:

1. Create a feature branch off the target branch.
2. Push the change to the feature branch.
3. Open a PR targeting the correct base branch.
4. Post a PR comment after push (see **PR comments after every push** below).

This applies even when the change is a one-liner, a test-only fix, or a direct revert. **No exceptions.**

### Why this matters

- Direct pushes bypass CI, DCO check, and code review.
- Direct pushes to `main` or `release-*` may break branch protection rules or ffwd invariants silently.
- A merged PR is the audit trail that justifies a change; a bare commit on a branch has no context for reviewers.

### How to create a branch via GitHub API

```bash
# 1. Get the SHA of the target branch tip
sha=$(gh api repos/OWNER/REPO/git/ref/heads/TARGET-BRANCH --jq '.object.sha')

# 2. Create the feature branch
gh api --method POST repos/OWNER/REPO/git/refs \
  --field ref="refs/heads/fix/my-change" \
  --field sha="$sha"

# 3. Push file(s) to the feature branch via contents API, then open PR
gh pr create --base TARGET-BRANCH --head fix/my-change --title "..." --body "..."
```

## Release branch fast-forward (main → release-*)

**Never commit directly to a protected release branch** (e.g. `release-5.0`) when that repo uses **main → release fast-forward** (OpenShift CI promotion / branch sync). Direct pushes break ffwd and leave the release branch ahead/behind main.

### How to tell

- Repo has both `main` and `release-<version>` branches
- OpenShift CI `ci-operator/config/.../stolostron-<repo>-main.yaml` promotes to the release namespace (e.g. `5.0`)
- User or runbook says "main ffwd to release-X"

### Rules

1. **All code changes go to `main` first** — via PR with DCO, normal CI.
2. **Release branch updates via ffwd only** — after merge to `main`, CI fast-forwards `release-*`. Do not `git push origin release-*` with new commits.
3. **If ffwd is broken** (release branch ahead/behind main): open a **merge PR** `main` → `release-*` (protected branches block force-push). Example: [compare main...release-5.0](https://github.com/stolostron/multicluster-global-hub/compare/main...release-5.0).
4. **Release-only commits** (e.g. 5.0 CPE labels in Containerfiles) still go through a PR targeting the release branch — but avoid duplicating dependency bumps that belong on `main`.
5. Check `workflows/cve-service/config/repo_mapping.json` → `repo_branch_policy` for ffwd per repo (`glo-grafana` has **no** ffwd — no `main` branch).

### Mandatory railcheck before push

**Before any `git push` to a release branch**, run the ffwd railcheck:

```bash
# From ai-agent repo root (or set FFWD_POLICY_FILE to repo_mapping.json)
scripts/check-ffwd-push.sh --repo stolostron/multicluster-global-hub --branch release-5.0
```

- Exit **0** → proceed with push.
- Exit **1** → **stop** — push to `dev_branch` via PR instead (see `repo_branch_policy` in `repo_mapping.json`).
- Never use `FFWD_ALLOW_DIRECT=1` unless the user explicitly overrides.

Repos with `ffwd_from_main: true` today: `stolostron/multicluster-global-hub`, `stolostron/postgres_exporter`.

### Local git hook (optional)

Developers can install the same check as a pre-push hook:

```bash
cd /path/to/stolostron/multicluster-global-hub
/path/to/multicluster-global-hub-ai-agent/scripts/install-ffwd-hook.sh
```

This chains with existing hooks (e.g. release checklist `pre-push` in multicluster-global-hub).

### Author identity

**The user's name is Valentina Birsan.** Always use exactly:

```
Signed-off-by: Valentina Birsan <vbirsan@redhat.com>
```

Never use "Vladislav", "V.", or any other variation. The GitHub account name and the `Signed-off-by` must match — a mismatch fails the DCO check.

## DCO sign-off on every commit

**Always add DCO.** stolostron repos require the Developer Certificate of Origin on every commit (`dco` / `dco-signoff: yes` label). Never push a PR commit without `Signed-off-by`.

### How to sign

Use the author's git identity (from `git config user.name` / `user.email`):

```bash
git commit -s -m "$(cat <<'EOF'
Your commit message here.

EOF
)"
```

To fix a commit that was already pushed (same change, missing sign-off):

```bash
git commit --amend -s --no-edit
git push --force-with-lease origin <branch>
```

### Commit message format

```text
Short subject line

Optional body paragraphs.

Signed-off-by: First Last <email@redhat.com>
Co-authored-by: Cursor <cursoragent@cursor.com>
```

### Rules

- Run `git commit -s` (or `--signoff`) on **every** new commit before pushing.
- After amend for DCO, force-push the PR branch and post a PR comment (see below).
- Verify with `git log -1 --format='%B'` that `Signed-off-by:` is present before `git push`.

## Jira keys in PR title and description

**Always include Jira when one exists.** Private Jira is not accessible to the agent — use only the **key** and **link**; do not invent ticket titles or descriptions.

Canonical example: [multicluster-global-hub-operator-bundle#1289](https://github.com/stolostron/multicluster-global-hub-operator-bundle/pull/1289) (ACM-30175 / TLS profile RBAC sync).

### Title format

```
<ACM-KEY>: <short PR summary> (#<related-pr> when follow-up)
```

Examples:

- `ACM-30175: Sync operator CSV RBAC for TLS profile support (#2487)`
- `ACM-32313: NetworkPolicy ipBlock hardening (API server + Kafka bootstrap) (#2493)`

### Description format

Add at the **top** of the PR body (before `## Summary`), then use `## Summary`, optional `## Context`, and `## Test plan`:

```markdown
Fixes: [ACM-30175](https://redhat.atlassian.net/browse/ACM-30175)

## Summary

- <what changed>

## Context

- <why / parent PR / companion work>

Related:

- [stolostron/multicluster-global-hub#2487](https://github.com/stolostron/multicluster-global-hub/pull/2487) — parent feature PR
- [ACM-30175](https://redhat.atlassian.net/browse/ACM-30175) — Jira

## Test plan

- [ ] ...
```

**Always link Jira keys** in `Fixes:` and `Related:` — never plain `Fixes: ACM-35632`:

```markdown
Fixes: [ACM-35632](https://redhat.atlassian.net/browse/ACM-35632)
```

For multiple keys:

```markdown
Fixes: [ACM-12345](https://redhat.atlassian.net/browse/ACM-12345), [ACM-67890](https://redhat.atlassian.net/browse/ACM-67890)
```

Link pattern: `https://redhat.atlassian.net/browse/<KEY>`

### Rules

- If the work references a Jira key (from the original PR, commit message, or user), put it in **both** title and description.
- **`Fixes:` line first** — never bury the Jira key only at the bottom of the body.
- **`Fixes:` / `Related:` must use markdown Jira links** — e.g. `[ACM-35632](https://redhat.atlassian.net/browse/ACM-35632)`, not bare `ACM-35632`.
- Use `Fixes:` for work that closes or completes the ticket scope; use `Related:` for sibling QE/epic keys.
- Do **not** paste Jira body text into the PR unless the user provides it.
- When updating an existing PR that has a Jira, run `gh pr edit` to add the key to title/body if missing.

### Operator-bundle CSV sync (GH 5.0 stage)

When a product PR on `stolostron/multicluster-global-hub` adds or changes operator **ClusterRole** rules (`operator/config/rbac/role.yaml` / main-repo CSV), **also open a companion PR** on `stolostron/multicluster-global-hub-operator-bundle` targeting **`release-5.0`**. OLM installs permissions from the bundle CSV, not from the main repo YAML alone.

Prior examples:

| Bundle PR | Jira / topic | Main repo |
|-----------|--------------|-----------|
| [operator-bundle#1289](https://github.com/stolostron/multicluster-global-hub-operator-bundle/pull/1289) | ACM-30175 — `apiservers` `get` | [#2487](https://github.com/stolostron/multicluster-global-hub/pull/2487) |
| [operator-bundle#1323](https://github.com/stolostron/multicluster-global-hub-operator-bundle/pull/1323) | ACM-31409 — `networkpolicies` RBAC | [#2493](https://github.com/stolostron/multicluster-global-hub/pull/2493) |

**Workflow:**

1. Land (or open) the main-repo PR with RBAC + bundle CSV in `multicluster-global-hub`.
2. Mirror the **same rules** into `multicluster-global-hub-operator-bundle` `bundle/manifests/multicluster-global-hub-operator.clusterserviceversion.yaml` on branch `fix/<topic>-rbac-sync` → `release-5.0`.
3. Link both PRs in **Context**; note stage bundle / Konflux publish in **Test plan**.
4. Title: `ACM-XXXXX: Sync operator CSV RBAC for <topic> (#<main-pr>)` with `Fixes: [ACM-XXXXX](https://redhat.atlassian.net/browse/ACM-XXXXX)` in the body.

Never push commits directly to `release-5.0` on the bundle repo — PR only.

## Cross-PR references in title and description

When referencing another GitHub PR, **always use a markdown link** — never bare `#1234`.

### Link format

```markdown
Supersedes [#2371](https://github.com/stolostron/multicluster-global-hub/pull/2371)
Related: [#1323](https://github.com/stolostron/multicluster-global-hub-operator-bundle/pull/1323)
```

Link pattern: `https://github.com/<org>/<repo>/pull/<number>`

### Rules

- Include the full `org/repo` in the URL so the link works outside the current repo context.
- Apply when mentioning supersedes, related, follow-up, stacked, or companion PRs in the body (and in PR comments when pointing reviewers elsewhere).
- On existing PRs, run `gh pr edit` (or REST `PATCH /pulls/{number}`) to replace bare `#NNNN` with linked form.

## No sensitive data in PR title, body, or comments

**Never include host or credential details** in PR titles, descriptions, update comments, commit messages visible on the PR, or any text posted on GitHub. This applies to `gh pr create`, `gh pr edit`, and `gh pr comment`.

### Never include

- Hostnames, cluster names, OpenShift routes, LoadBalancer DNS, IPs, or URLs that identify internal infrastructure
- Partially redacted hostnames (e.g. `...apps.my-cluster...`) — still identifiable; use a full placeholder instead
- Usernames, passwords, API tokens, kubeconfig paths, `.env` values, or secret excerpts from logs
- Customer or lab naming patterns that map to real environments

### Use placeholders instead

```text
ssl://kafka-kafka-tls-bootstrap-<openshift-route-host>:443/bootstrap: Connection setup timed out
Connection refused to <postgres-service>:5432
Failed on cluster <cluster-name>
Jenkins job <job-name> build <build-number>
```

Keep enough context (port, protocol, error type, test ID) without naming real hosts or accounts.

### Rules

- Sanitize log excerpts before pasting into PR text — generic error + port/protocol is usually enough
- Some repos run CodeRabbit **No-Sensitive-Data-In-Logs** pre-merge; failing blocks merge until the PR description is redacted
- When a PR fails that check, `gh pr edit` (or REST `PATCH /pulls/{number}`) to redact, then comment `@coderabbitai review`
- Same rules apply to PR update comments — do not paste raw CI logs with cluster routes or credentials

## Pre-push verification (mandatory — do not skip)

**Run these checks before every `git commit` and `git push` on a PR branch.** Skipping them causes avoidable `gofmt` / `format` / Sonar fix-up commits (see PR #2623: import order in `source_validation.go` slipped through because only integration tests were run, not `gofmt -l` on the amended commit).

**Gate:** do not run `git push` until all steps below pass. Report blockers to the user; do not push and hope CI catches it.

### CodeRabbit review comments (check first)

**Before any new commit on an open PR**, read CodeRabbit feedback and address actionable items in that commit — do not stack unrelated fixes on top of open CR change requests.

```bash
PR=2623
REPO=stolostron/multicluster-global-hub

# Inline review comments (file + line)
gh api "repos/${REPO}/pulls/${PR}/comments" \
  --jq '.[] | select(.user.login | test("coderabbit"; "i")) | {path, line, body: .body[0:300]}'

# PR conversation comments (summary, pre-merge checks, nitpicks)
gh api "repos/${REPO}/issues/${PR}/comments" \
  --jq '.[] | select(.user.login | test("coderabbit"; "i")) | {created_at, body: .body[0:300]}'

# Optional: only comments newer than the last pushed commit
LAST=$(git log -1 --format=%ct origin/$(git branch --show-current) 2>/dev/null || git log -1 --format=%ct)
gh api "repos/${REPO}/pulls/${PR}/comments" \
  --jq --argjson t "$LAST" '.[] | select(.user.login | test("coderabbit"; "i") and (.created_at | fromdateiso8601 > $t)) | {path, line, body: .body[0:300]}'
```

| Feedback type | Action |
|---------------|--------|
| Bug / security / correctness | Fix in the next commit before pushing |
| Style / maintainability (valid) | Fix when low-cost; batch with the planned change |
| Pre-merge check failure (e.g. No-Sensitive-Data-In-Logs) | Redact PR body via `gh pr edit`, then `@coderabbitai review` |
| Disagree or out of scope | Reply on the thread with rationale; do **not** silently ignore |

After pushing fixes for CR feedback, request a fresh review when the PR has new commits:

```bash
gh pr comment "$PR" --repo "$REPO" --body "@coderabbitai review"
```

### Changed Go files (entire PR branch, not just unstaged)

Check **all `.go` files changed on the branch vs merge-base** — not only `git diff --name-only` (unstaged). After `git commit --amend`, working tree can be clean while the commit still fails `gofmt`.

```bash
cd repos/multicluster-global-hub   # or the target repo
BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main)
CHANGED=$(git diff --name-only "${BASE}"..HEAD -- '*.go')

# 1. gofmt — matches ci/prow/gofmt (import order, struct alignment)
if [ -n "$CHANGED" ]; then
  gofmt -l $CHANGED | grep . && echo "FAIL: run gofmt -w on files above" && exit 1
fi

# 2. strict-fmt — matches GitHub Actions format job (gci + gofumpt)
#    If vendor is out of sync locally, run gci/gofumpt on $CHANGED only:
#    gci write -s standard -s default -s "prefix(github.com/stolostron/multicluster-global-hub)" $CHANGED
#    gofumpt -w $CHANGED
#    Or: make strict-fmt   (requires synced vendor)
make strict-fmt 2>/dev/null || { gofmt -l $CHANGED | grep . && exit 1; }

# 3. unit tests for touched packages
go test -mod=mod ./agent/pkg/spec/... -count=1
```

Common `gofmt` misses when adding imports by hand:
- `k8s.io/api/*` before `k8s.io/apimachinery/*` (e.g. `corev1` before `apierrors`)
- struct literal field alignment in test table entries

### SonarCloud new-code issues

Before committing, check open issues on the PR leak period:

`https://sonarcloud.io/project/issues?id=open-cluster-management_hub-of-hubs&pullRequest=<PR_NUMBER>&issueStatuses=OPEN,CONFIRMED&sinceLeakPeriod=true`

```bash
curl -s "https://sonarcloud.io/api/issues/search?componentKeys=open-cluster-management_hub-of-hubs&pullRequest=<PR>&issueStatuses=OPEN,CONFIRMED&sinceLeakPeriod=true&ps=50" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('open:', d.get('total',0)); [print(i['rule'], i.get('component','').split(':')[-1], i.get('line')) for i in d.get('issues',[])]"
```

| Rule | Typical fix |
|------|-------------|
| `go:S103` | Split lines >120 chars |
| `go:S104` | Split oversized test files; avoid inserting at top of huge files (shifts line numbers) |
| `go:S134` | Reduce nested control flow in tests |
| Coverage gate | Add unit tests for new branches |

### Rules

- **Check CodeRabbit comments before committing** — address actionable feedback in the same commit when possible.
- Do **not** push until `gofmt -l` is clean on **all branch-changed** `.go` files (`${BASE}..HEAD`), including after `--amend`.
- Run `make strict-fmt` (or `gci` + `gofumpt` on changed files) when the repo has a `strict-fmt` target — the GitHub `format` job uses both.
- After push, check `gofmt`, `format`, `test-unit`, `sonarcloud`, and `test-integration` on the PR before reporting success.
- Prefer new focused `*_test.go` files over growing legacy 1500+ line test files.

## PR comments after every push

**Always add a PR comment for changes.** After pushing any commit to a GitHub PR branch, post a comment on that PR summarizing what changed and why — before moving on, even if the user did not ask for it.

### How to comment

Use `gh pr comment <PR_NUMBER> --repo <owner/repo> --body "..."` immediately after each successful `git push`.

### Comment template

```markdown
**Update: <short title of what changed>**

- <bullet describing the change>
- <bullet describing why / what it fixes>
```

### Example (#2490 — format lint fix)

```bash
gh pr comment 2490 --repo stolostron/multicluster-global-hub --body "**Update: fix errcheck in version_clusterclaim test**

- Restored checked \`fmt.Fprintf\` calls in \`version_clusterclaim_test.go\` (cherry-pick from #2488 had dropped error handling)
- Fixes failing \`format\` job (golangci-lint errcheck)"
```

### Rules

- Always include the PR number and repo in the `gh pr comment` call.
- Keep the body concise (3–5 lines).
- **Describe only what changed and why.** Do **not** add:
  - Local verification claims (`Verified locally…`, `opm serve --cache-only` passes, test matrix you ran)
  - CI predictions or timing (`CI should pass`, `CI should re-run`, `build should succeed in 10 min`)
  - Next-step speculation (`re-run on <sha>`, `grab the EC log if…`, `test with …`)
  - Obvious process/meta notes reviewers already know (`force-push will require fresh /lgtm`, `branch protection dismisses stale reviews`, `CI will re-run on the new commit`, commit SHAs as filler) — mention those to the user in chat if needed, not on the PR
  - Hostnames, cluster names, routes, IPs, usernames, passwords, tokens, or other sensitive data (see **No sensitive data in PR title, body, or comments** above)
- Post the comment **after** the push succeeds, **before** reporting back to the user or starting the next task.
- Applies to all push types: CI fixes, rebase, new commits, force-push after DCO amend.

## Jira issue creation (ACM)

When creating ACM issues via API, read and follow **`skills/jira-create/SKILL.md`**.

**Always set** (use context-appropriate values; do not leave blank):

| Field | Typical default |
|-------|-----------------|
| Component(s) | `QE` or `Global Hub` |
| Activity Type | `Product / Portfolio Work` |
| Severity | `Important` |
| Priority | `Critical` |

Set `JIRA_EMAIL` in `.env` to your Atlassian account email (e.g. `you@redhat.com`). A one-character typo breaks API create/comment.

## Network / VPN errors

**Flag VPN issues immediately.** If a `gh`, `curl`, or any network command fails with a connection error (e.g. `error connecting to api.github.com`, `Forbidden`, timeout), stop and tell the user right away:

> "This looks like a VPN/network issue — please connect to VPN and I'll retry."

Do **not** silently retry, launch long-running subagents, or wait until timing out. One failed attempt is enough to diagnose the issue.

### Rules

- On the first network failure, surface it to the user in plain language before doing anything else.
- After the user confirms VPN is up, re-run the same command with `required_permissions: ["all"]` if the sandbox was also blocking it.
- Never spend more than one attempt on a command that fails with a clear connectivity error.

## Slack messages and escalations

**Never draft or ask the user to post a Slack message unless the root cause is confirmed.**

Slack messages to teams (CI, infra, security, QE, etc.) are hard to retract and create noise. A wrong escalation (e.g. "please rotate the token" when the token is fine) wastes other teams' time and misframes the issue.

### Rules

- **Verify before escalating.** Before suggesting a Slack message blaming a specific root cause (expired secret, bad token, infra issue, missing permission, etc.), confirm it programmatically first:
  - For SonarCloud 403 / quality gate: query `sonarcloud.io/api/qualitygates/project_status` before assuming a token problem.
  - For CI failures: read the actual log output, not just the summary status.
  - For any "bad credential" error: attempt an authenticated API call and check the response body.
- **Surface uncertainty to the user, not to the external team.** If the cause is unclear, tell the user "I'm not certain yet — let me check X before we escalate" rather than drafting a message based on the first visible error.
- **Draft a Slack message only when:** the cause is confirmed, the right audience is identified, and the message accurately describes the problem with evidence (log link, API response, etc.).
- **If the user asks you to draft a Slack message and you are not confident the framing is correct**, say so explicitly and offer to verify the root cause first.

### Retrospective example (Jun 2026)

A `403 Forbidden` and `jq null` in a SonarCloud post-submit log led to a Slack escalation asking the CI team to rotate `acm-sonarcloud-token`. The token was fine — the real issue was three S8545 vulnerability findings driving a Security Rating C that failed the quality gate. Querying `sonarcloud.io/api/qualitygates/project_status` upfront would have revealed the actual cause in seconds and avoided the incorrect escalation.

## GH release repo script fixes — always push to GitLab

**Whenever you update a script on the gh release project, always push the fix to https://gitlab.cee.redhat.com/vbirsan/acm-global-hub-release**

Local edits alone are not enough. Commit (DCO) and `git push pipeline <branch>` before reporting the fix. Full scope and workflow: **`skills/gitlab-gh-release-pipeline/SKILL.md`**.

## GitLab pipeline fixes — merge before "rerun"

**Do not say a pipeline fix is ready until it is on the branch the user will run** (usually `main` on `vbirsan/acm-global-hub-release`).

Side-branch-only fixes (`vbirsan`, `brew-fix-for-pipeline`, etc.) are invisible when the user reruns on `main`. Always:

1. Merge/fast-forward the fix into `main`
2. `git push pipeline main`
3. Verify failed job `ref` + `sha` match the fix commit
4. Tell the user the **branch name and commit SHA** when asking them to rerun

Full workflow, GitLab job verification, and Jira coupling: **`skills/gitlab-gh-release-pipeline/SKILL.md`**

## Related

- GitLab GH release pipeline (branch discipline, job verification): `skills/gitlab-gh-release-pipeline/SKILL.md`
- Jira create hygiene: `skills/jira-create/SKILL.md`
- Cursor rule: `.cursor/rules/github-pr-comment-on-update.mdc` (always applied in this repo)
