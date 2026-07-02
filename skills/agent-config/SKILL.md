---
name: agent-config
description: Agent workflow defaults for GitHub PR work and GitLab GH release pipeline handoffs — DCO sign-off, no sensitive data in PR text, PR comments after push, merge pipeline fixes to the run branch (main) before telling the user to rerun. Use when creating or updating PRs, fixing acm-global-hub-release GitLab jobs, pushing fixes, babysitting CI, retesting, or when the user asks about agent config or PR conventions.
---

# Agent Config

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

Use the user's full name in `Signed-off-by` (e.g. `Valentina Birsan <vbirsan@redhat.com>`), not a shortened first name.

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

### Title format

```
<ACM-KEY>: <short PR summary>
```

Example: `ACM-19479: Add NetworkPolicy support for multicluster-global-hub`

### Description format

Add at the top of the PR body (before technical details):

```markdown
Fixes: [ACM-19479](https://redhat.atlassian.net/browse/ACM-19479)
```

For multiple keys:

```markdown
Fixes: [ACM-12345](https://redhat.atlassian.net/browse/ACM-12345), [ACM-67890](https://redhat.atlassian.net/browse/ACM-67890)
```

Link pattern: `https://redhat.atlassian.net/browse/<KEY>`

### Rules

- If the work references a Jira key (from the original PR, commit message, or user), put it in **both** title and description.
- Use `Fixes:` or `Related:` with markdown links — same pattern as CVE PRs, but **without** pasting Jira body text unless the user provides it.
- When updating an existing PR that has a Jira, run `gh pr edit` to add the key to title/body if missing.

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
