---
name: manage-jira-issues
description: Comprehensive Jira issue management for Global Hub - set fields, update stories, add QE tasks to sprint. Supports Story, Bug, Spike, Task, CVE issues.
user-invocable: true
---

# Manage Jira Issues

Comprehensive Jira issue management combining multiple operations:
1. **Set fields** on individual issues (Story, Bug, Spike, Task, CVE)
2. **Update stories** with auto-calculated story points and sprint
3. **Add QE tasks to sprint** for all stories in current sprint

## When to Use This Skill

### Mode 1: Update Individual Issue
- User provides a Jira link like `https://redhat.atlassian.net/browse/ACM-XXXXX`
- User says "update ACM-XXXXX" or "fix ACM-XXXXX" or "set fields on ACM-XXXXX"

### Mode 2: Add QE Tasks to Sprint
- User says "add qe tasks to sprint"
- User wants to sync QE tasks with story sprints
- Before sprint planning to ensure QE tasks are included

### Mode 3: Check Sprint Issues
- User says "check sprint issues"
- User wants to audit all issues in current sprint for missing fields

## Issue Type Rules

### Story
- Activity Type: "Product / Portfolio Work"
- Story Points: Auto-calculated from task count in description (or manual override)
  - 1-2 tasks = 1 point
  - 3-4 tasks = 2 points
  - 5-6 tasks = 3 points
  - 7-9 tasks = 5 points
  - 10+ tasks = 8 points
- Priority: Major
- Severity: Moderate
- Versions: Global Hub 1.8.0
- Labels: Auto-calculated Sprint, Eng-Status:Green, QE/doc labels
- **Preserves existing story points** if already set

### Bug
- Activity Type: "Quality / Stability / Reliability"
- Story Points: 2 (default, only if not set)
- Priority: Major
- Severity: Moderate
- Versions: Global Hub 1.8.0

### Task
- **QE Task** (title contains `[QE]`):
  - Activity Type: "Quality / Stability / Reliability"
  - Story Points: 2 (default, only if not set)
  - Priority: Major
  - Severity: Moderate
  - Versions: Global Hub 1.8.0
- **Other Tasks**:
  - Activity Type: "Product / Portfolio Work"
  - **Story Points: NOT set** (non-QE tasks don't need story points)
  - Priority: Major
  - Severity: Moderate
  - Versions: Global Hub 1.8.0

### Spike
- Activity Type: "Product / Portfolio Work"
- Story Points: 3 (default, only if not set)
- Priority: Major
- Severity: Moderate
- Versions: Global Hub 1.8.0

### CVE Issue
- Activity Type: "Quality / Stability / Reliability"
- **Story Points: NOT set** (CVE issues don't need story points)
- Priority: Major
- Severity: Moderate
- **Fix Version: NOT set** (CVE issues are special)

## Auto-Calculated Fields

### Sprint Label
- GH Sprint 1 ends on 2026-04-01
- Each sprint is 3 weeks
- Auto-calculated based on current date
- Format: `GH Sprint X` (e.g., "GH Sprint 1")

### Story Points (Stories Only)
**Preserves existing points** - If a story already has story points, they are preserved unless explicitly overridden.

Only auto-calculates when story has no points, based on task count in description.

### QE Labels (Stories Only)
**Preserves existing QE labels** - If a story already has either `QE-Required` or `QE-NotApplicable` (case-insensitive), the existing label is preserved.

Only sets QE label when neither exists:
- Default: `QE-NotApplicable`
- Override: Set `QE_APPLICABLE=Required` to add `QE-Required` and `QE-Confidence:Green`

**Note**: QE label checking is case-insensitive. Any of `QE-Required`, `qe-required`, `QE-REQUIRED` will be recognized and preserved.

## Instructions

When this skill is invoked:

### Mode 1: Update Individual Issue

```bash
ISSUE_KEY=ACM-XXXXX ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

**Optional Overrides**:
```bash
ISSUE_KEY=ACM-XXXXX \
STORY_POINTS=5 \
SPRINT=2 \
QE_APPLICABLE=Required \
DOC_REQUIRED=required \
~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Mode 2: Add QE Tasks to Sprint

```bash
MODE=add-qe-tasks ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

**Optional Parameters**:
```bash
MODE=add-qe-tasks SPRINT=2 ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

**Dry Run** (list without updating):
```bash
MODE=add-qe-tasks DRY_RUN=true ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Mode 3: Check Sprint Issues

```bash
MODE=check-sprint ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

**Optional Parameters**:
```bash
MODE=check-sprint SPRINT=2 ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| MODE | No | update | Mode: "update", "add-qe-tasks", or "check-sprint" |
| ISSUE_KEY | Yes (mode=update) | - | Jira issue key (e.g., ACM-31479) |
| STORY_POINTS | No | Auto | Override story points (1/2/3/5/8) |
| SPRINT | No | Auto | Sprint number (1, 2, 3, etc.) |
| QE_APPLICABLE | No | NotApplicable | "Required" or "NotApplicable" (Stories only) |
| DOC_REQUIRED | No | not-required | "required" or "not-required" (Stories only) |
| FIX_VERSION | No | Global Hub 1.8.0 | Fix version name |
| AFFECT_VERSION | No | Global Hub 1.8.0 | Affect version name |
| DRY_RUN | No | false | Set to "true" for dry run (add-qe-tasks mode only) |

## Examples

### Example 1: Simple Issue Update
User says: "update ACM-31479"
```bash
ISSUE_KEY=ACM-31479 ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 2: Story with Custom Story Points
User says: "update ACM-31479, 5 story points"
```bash
ISSUE_KEY=ACM-31479 STORY_POINTS=5 ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 3: Story with QE Required
User says: "update ACM-31480, needs QE"
```bash
ISSUE_KEY=ACM-31480 QE_APPLICABLE=Required ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 4: Add QE Tasks to Current Sprint
User says: "add qe tasks to sprint"
```bash
MODE=add-qe-tasks ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 5: Add QE Tasks - Dry Run
User says: "show me which QE tasks would be added"
```bash
MODE=add-qe-tasks DRY_RUN=true ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 6: Check All Sprint Issues
User says: "check sprint issues for missing fields"
```bash
MODE=check-sprint ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

### Example 7: Bug Update
User says: "fix ACM-31481" (where ACM-31481 is a Bug)
```bash
ISSUE_KEY=ACM-31481 ~/.claude/skills/manage-jira-issues/manage-jira-issues.sh
```

## Prerequisites

- `JIRA_TOKEN` environment variable must be set
- `JIRA_USER` environment variable must be set

## Key Behavior

- **Preserves existing values**: Only sets fields that are empty/missing
- **Issue type detection**: Automatically detects issue type and applies appropriate rules
- **CVE detection**: Checks if summary contains "CVE" to identify CVE issues
- **QE Task detection**: Checks if task title contains "[QE]" to identify QE-related tasks
- **Smart Story Points**: Only sets story points for bugs, spikes, stories, and QE tasks (NOT for CVE issues or non-QE tasks)
- **Doc Task Auto-Creation**: When `DOC_REQUIRED=required` is set for stories, automatically creates and links doc tasks if not already present

## Doc Task Auto-Creation (Stories Only)

When `DOC_REQUIRED=required` is set for a Story:

1. **Checks** if a doc task (with `[Doc]` in title) is already linked to the story
2. **If not found**, creates a new doc task:
   - Title: `[Doc] <Story Title>`
   - Assigned to: Story owner
   - Labels: `doc-task`
   - Components: Same as story
3. **Links** the doc task to the story
4. **Sets** required fields on the doc task

## Error Handling

- **Missing JIRA_TOKEN**: Prompt user to set the token
- **Invalid story points**: Must be 1, 2, 3, 5, or 8
- **No tasks in description** (stories): Defaults to 3 story points
- **Rate limiting**: Automatic retry with exponential backoff (up to 5 attempts)
- **Field update failures**: Falls back gracefully, retrying without problematic fields

## What This Replaces

This skill consolidates three previous skills:
1. `update-jira-story` - Now Mode 1 with issue type Story
2. `set-issue-fields` - Now Mode 1 with any issue type
3. `add-qe-tasks-to-sprint` - Now Mode 2
