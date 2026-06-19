---
name: gitlab-gh-release-pipeline
description: >-
  Global Hub GitLab release pipeline (vbirsan/acm-global-hub-release). Use when
  fixing validate-release or trigger-jenkins scripts, telling the user to rerun
  a pipeline, debugging failed GitLab jobs, or changing Jira param parsing in
  chunlin-acm-global-hub-release. Enforces merge-to-run-branch before handoff.
---

# GitLab GH Release Pipeline

Repo: `chunlin-acm-global-hub-release` (local) → `vbirsan/acm-global-hub-release` (GitLab).  
Default remote for pushes: `pipeline` (`git@gitlab.cee.redhat.com:vbirsan/acm-global-hub-release.git`).

Users trigger pipelines from the GitLab UI **Run pipeline** dialog. The selected **branch/ref** is what CI checks out — not whatever branch you edited locally unless that ref is pushed and selected.

## Rule: fix must be on the run branch before "rerun"

**Never tell the user a pipeline fix is ready until the fix commit is on the branch they will run.**

Default run branch: **`main`** on `vbirsan/acm-global-hub-release`. Users almost always rerun on `main`, not a side branch.

### After changing pipeline scripts (`release/`, `lib/`, `.gitlab-ci.yml`)

1. Commit on a working branch if needed.
2. **Merge or fast-forward into `main`** on the `pipeline` remote.
3. **Push `pipeline main`** (or whichever branch the user will select).
4. **Verify** the pushed SHA (see below).
5. Only then say "rerun the pipeline" — and **name the branch and commit**.

```bash
cd /path/to/chunlin-acm-global-hub-release
git fetch pipeline
git checkout main
git merge <fix-branch>   # or commit directly on main
git push pipeline main
git log -1 --oneline pipeline/main
```

### Anti-pattern (repeat failure mode)

| What happened | Result |
|---------------|--------|
| Fix pushed only to `vbirsan` (or other side branch) | User reruns on `main` → old scripts → same error |
| Jira table updated, parse whitelist not on `main` | New Jira rows ignored in validate job |
| Agent says "fixed, rerun" without merge/push | User wastes another pipeline run |

Example: job [54610948](https://gitlab.cee.redhat.com/vbirsan/acm-global-hub-release/-/jobs/54610948) ran `ref: main`, `sha: ef4a057` while fix was `810209c` on `vbirsan` only.

## Verify a failed job used the right code

Load credentials from `workflows/cve-service/config/.env` (`GITLAB_TOKEN`).

```bash
set -a && source <workspace>/workflows/cve-service/config/.env && set +a

JOB_ID=54610948
curl -ksS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.cee.redhat.com/api/v4/projects/vbirsan%2Facm-global-hub-release/jobs/${JOB_ID}" \
  | python3 -c "
import sys, json
j = json.load(sys.stdin)
c = j.get('commit') or {}
print('status:', j.get('status'))
print('ref:', j.get('ref'))
print('sha:', (c.get('id') or '')[:12])
print('title:', c.get('title'))
"
```

Compare `ref` and `sha` to the fix commit. Mismatch → merge/push to run branch first; do not blame Jira or Jenkins.

### Validate job: confirm Jira params were parsed

Sibling validate job is usually `jenkins-<task-slug>` or `validate-<task-slug>` in the same pipeline. Grep its trace for parsed keys:

```bash
curl -ksS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.cee.redhat.com/api/v4/projects/vbirsan%2Facm-global-hub-release/jobs/<VALIDATE_JOB_ID>/trace" \
  | grep -E "Parameter Set|OCP_|CATALOG"
```

If a new Jira key is missing from output, either Jira was not updated or **the running branch lacks the whitelist change** in `lib/common.sh` (`JENKINS_PARAM_KEYS`).

## Handoff message template

When telling the user to rerun, always include:

```markdown
**Pipeline rerun**

- Branch: `main` (not a side branch unless you explicitly chose one)
- Fix commit: `<short-sha>` — `<subject line>`
- GitLab: Run pipeline → ref = `main` → same variables as before

If the job still fails, check job metadata: `ref` and `sha` must match the fix commit above.
```

If the user must run a side branch temporarily, say so explicitly: **"Select branch `vbirsan` in Run pipeline"** — never assume they will.

## Jira + pipeline coupling

Pipeline scripts read Jira at **runtime** from the QE task description table. Code and Jira must both be ready:

| Layer | Requirement |
|-------|-------------|
| GitLab `main` | `JENKINS_PARAM_KEYS` includes new keys; trigger logic handles them |
| Jira QE task | Table rows present with correct names/values |
| User rerun | GitLab ref = branch with code fix |

Updating Jira alone does not help if validate still runs old `parse-jira-params.sh` on `main`.

## Related

- Agent defaults (DCO, PR comments): `skills/agent-config/SKILL.md`
- Jenkins E2E params: `skills/jenkins-e2e-polarion/SKILL.md`
