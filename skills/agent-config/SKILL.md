---
name: agent-config
description: Agent workflow defaults for GitHub PR work — always DCO sign-off on commits and comment on PRs after pushing updates. Use when creating or updating PRs, pushing fixes to PR branches, babysitting CI, retesting, or when the user asks about agent config or PR conventions.
---

# Agent Config

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

## PR comments after every push

**Always add a PR comment for changes.** After pushing any commit to a GitHub PR branch, post a comment on that PR summarizing what changed and why — before moving on, even if the user did not ask for it.

### How to comment

Use `gh pr comment <PR_NUMBER> --repo <owner/repo> --body "..."` immediately after each successful `git push`.

### Comment template

```markdown
**Update: <short title of what changed>**

- <bullet describing the change>
- <bullet describing why / what it fixes>

CI should now pass / next step: <what to expect next>.
```

### Example (#2490 — format lint fix)

```bash
gh pr comment 2490 --repo stolostron/multicluster-global-hub --body "**Update: fix errcheck in version_clusterclaim test**

- Restored checked \`fmt.Fprintf\` calls in \`version_clusterclaim_test.go\` (cherry-pick from #2488 had dropped error handling)
- Fixes failing \`format\` job (golangci-lint errcheck)

CI should re-run on \`1eb5a705\`."
```

### Rules

- Always include the PR number and repo in the `gh pr comment` call.
- Keep the body concise (3–6 lines).
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

## Related

- Jira create hygiene: `skills/jira-create/SKILL.md`
- Cursor rule: `.cursor/rules/github-pr-comment-on-update.mdc` (always applied in this repo)
