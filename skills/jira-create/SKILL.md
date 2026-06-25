---
name: jira-create
description: Create or update ACM Jira issues via API with required hygiene fields (Component Global Hub, Assignee, Activity Type, Severity, Priority). Use when creating sub-tasks, QE tasks, linking issues, or when the user asks about Jira API tokens, ACM issue fields, or release-management component alerts.
---

# ACM Jira — create / update issues

## Credentials

Load from `workflows/cve-service/config/.env`:

```bash
set -a
source <workspace-root>/workflows/cve-service/config/.env
set +a
```

**Email must match Atlassian account exactly** (set in `.env` as `JIRA_EMAIL=you@redhat.com`). A one-character typo authenticates read-only — create/comment fail.

Use **classic API token** (or scoped with `read:jira-work` + `write:jira-work`).

## Required fields on every ACM issue created

**Always set all of the following.** Values below are the usual defaults for Global Hub / QE / release work — pick context-appropriate options when the issue is not release/QE work, but **never leave these empty**.

| Field | API key | Default (GH / QE / release work) | Notes |
|-------|---------|----------------------------------|-------|
| **Component(s)** | `components` | **`Global Hub`** (always) | Required for ACM Release Management hygiene — **never use `QE` or leave unset** |
| **Assignee** | `assignee` | **`JIRA_EMAIL`** from `.env` | Initial owner is always the authenticated user (you) |
| **Activity Type** | `customfield_10464` | `Product / Portfolio Work` | Other options: Quality / Stability / Reliability, Security & Compliance, … |
| **Severity** | `customfield_10840` | `Important` | Other options: Critical, Moderate, Low, Informational |
| **Priority** | `priority` | `Critical` | Other options: Blocker, Major, Normal, Minor |

Also set when applicable:

| Field | API key | Example |
|-------|---------|---------|
| Fix version | `fixVersions` | `Global Hub 5.0.0` |
| Parent | `parent` | Sub-task parent story key |
| Affects version | `versions` | Prior GA stream if z-stream QE |

### Component (required)

Always set **Global Hub** — ID `33693`:

```json
"components": [{"id": "33693"}]
```

### Assignee (required)

Set the initial owner to the authenticated user — use `JIRA_EMAIL` from `.env`:

```json
"assignee": {"name": "you@redhat.com"}
```

In shell scripts, pass `"${JIRA_EMAIL}"` so the issue is assigned to you on create.

### Activity Type option

```json
"customfield_10464": {"value": "Product / Portfolio Work"}
```

### Severity option

```json
"customfield_10840": {"value": "Important"}
```

### Priority

```json
"priority": {"name": "Critical"}
```

## Create sub-task example

```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" -X POST "${JIRA_URL}/rest/api/3/issue" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "ACM"},
      "summary": "QE: example sub-task",
      "issuetype": {"name": "Sub-task"},
      "parent": {"key": "ACM-30971"},
      "components": [{"id": "33693"}],
      "assignee": {"name": "'"${JIRA_EMAIL}"'"},
      "fixVersions": [{"id": "106812"}],
      "priority": {"name": "Critical"},
      "customfield_10464": {"value": "Product / Portfolio Work"},
      "customfield_10840": {"value": "Important"},
      "description": {"type": "doc", "version": 1, "content": [
        {"type": "paragraph", "content": [{"type": "text", "text": "Description here."}]}
      ]}
    }
  }'
```

## Jira description — embed content, never link private repo docs

**Never link to `pre-release/*.md` (or other paths in private/local release repos) when creating or updating Jira issues.** Those files are not accessible to all QE and engineering stakeholders.

| Do | Don't |
|----|-------|
| Paste Polarion cases, automation scope, Jenkins params, and checklists **into the Jira Description** (ADF) | `pre-release/ACM-32494-polarion-test-outline.md` |
| Link public artifacts: GitHub PRs (`stolostron/*`), Jira keys, Polarion run URLs | private local release-repo paths |
| Link product-repo docs on GitHub when merged (e.g. `ai-doc/NETWORKPOLICY.md` on `multicluster-global-hub`) | “See attached outline in release repo” |

**Workflow:** draft in `pre-release/` locally if helpful → **copy the substance into Jira** → treat **Jira Description as canonical** for assignees.

**Comments:** same rule — no `pre-release/` links; embed summaries or use public URLs only.

## Post-create checklist

After every create or metadata update:

1. Confirm **Component** is `Global Hub` (UI or `GET /rest/api/3/issue/<KEY>?fields=components`).
2. Confirm **Assignee** is you (`fields=assignee`).
3. Confirm **Activity Type**, **Severity**, **Priority** are set.
4. Link related issues (`Related`, `Duplicate`, etc.) — link type name is `Related`, not `Relates`.
5. Sub-tasks: verify `parent` is the intended story (not epic-only Task).

## Issue link types (ACM)

| Name | Use |
|------|-----|
| `Related` | relates to doc / sibling work |
| `Duplicate` | orphan task → canonical sub-task |

## Verify permissions before bulk create

```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/mypermissions?projectKey=ACM&permissions=CREATE_ISSUES,ADD_COMMENTS"
```

Expect `CREATE_ISSUES: true` and `ADD_COMMENTS: true`.

## Reference

- QE task script with same defaults: `pre-release/05-create-qe-task.sh` (in your release repo)
- Polarion sub-task template: `pre-release/ACM-30971-polarion-jira.txt` (in your release repo)
