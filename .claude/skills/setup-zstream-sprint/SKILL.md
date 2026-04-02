---
name: setup-zstream-sprint
description: Setup Z-Stream sprint by finding all active Z-Stream epics, adding their child work items to sprint, and assigning to team members. Automates QE and Dev story/task assignment.
user-invocable: true
---

# Setup Z-Stream Sprint

Automatically sets up Z-Stream releases in the current sprint by:
1. Finding all active Z-Stream epics (QE Epic and Release)
2. Adding all child stories and tasks to the sprint
3. Assigning QE epics and tasks to QE team member
4. Setting story points for QE tasks
5. Assigning dev stories to dev team member

## When to Use This Skill

- User says "setup zstream sprint" or "prepare zstream sprint"
- At the start of a new sprint to add Z-Stream work items
- When new Z-Stream releases are created and need to be tracked

## What It Does

1. **Find Z-Stream Epics**: Queries all epics with status "New" or "In Progress" matching:
   - "Global Hub v1.x.x - Z-Stream QE Epic"
   - "Global Hub v1.x.x - Z-Stream Release"
   - Retrieves epic fix versions

2. **Get Child Work Items**: Retrieves all Story and Task items under these epics

3. **Add to Sprint**: Adds all work items to the specified sprint (or current sprint)

4. **Assign QE Work**:
   - Assigns QE epics to QE assignee (default: Yaheng Liu)
   - Assigns QE tasks to QE assignee
   - Sets story points to 1 for all QE tasks
   - Syncs QE task versions (affect & fix) from parent QE epic

5. **Assign Dev Work**:
   - Assigns unassigned dev stories to dev assignee (default: ChunLin Yang)

6. **Sync Story Versions**:
   - Sets dev story affect versions to match parent epic's fix versions
   - Sets dev story fix versions to match parent epic's fix versions
   - Ensures version consistency between epics and all child items (stories & tasks)

## Current Sprint Calculation

- Format: `GH Sprint X` (e.g., "GH Sprint 1")
- GH Sprint 1 ends on 2026-04-01
- Each sprint is 3 weeks
- Auto-calculated based on current date

## Instructions

When this skill is invoked:

1. **Run the Script**:
   ```bash
   ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
   ```

2. **Specify Sprint**:
   ```bash
   SPRINT=2 ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
   ```

3. **Custom Assignees**:
   ```bash
   QE_ASSIGNEE="Yaheng Liu" DEV_ASSIGNEE="ChunLin Yang" ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
   ```

4. **Dry Run Mode** (preview only):
   ```bash
   DRY_RUN=true ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
   ```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| SPRINT | No | Auto-calculated | Sprint number (1, 2, 3, etc.) |
| QE_ASSIGNEE | No | "Yaheng Liu" | Name of QE assignee for epics and tasks |
| DEV_ASSIGNEE | No | "ChunLin Yang" | Name of dev assignee for stories |
| QE_STORY_POINTS | No | 1 | Story points to set for QE tasks |
| DRY_RUN | No | false | Set to "true" to preview without making changes |

## Output

- Lists all Z-Stream epics found (New/In Progress) with their fix versions
- Shows all child work items (stories and tasks)
- Reports sprint assignment results
- Shows QE epic/task assignment results with version sync status
- Shows dev story assignment results
- Shows version sync results for both QE tasks and dev stories (synced from epic's fix version)
- Summary of all operations

## Prerequisites

- `JIRA_TOKEN` environment variable must be set
- `JIRA_USER` environment variable must be set

## Examples

### Example 1: Setup for Current Sprint
```bash
~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
```

### Example 2: Setup for Specific Sprint
```bash
SPRINT=2 ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
```

### Example 3: Dry Run (Preview Only)
```bash
DRY_RUN=true ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
```

### Example 4: Custom Assignees
```bash
QE_ASSIGNEE="John Doe" DEV_ASSIGNEE="Jane Smith" ~/.claude/skills/setup-zstream-sprint/setup-zstream-sprint.sh
```

## Notes

- Only processes epics with status "New" or "In Progress"
- Skips items already in the target sprint
- Only assigns stories that are currently unassigned
- QE tasks are identified as child tasks of QE epics
- Dev stories are identified as child stories of Release epics
- **Version Sync**: 
  - Both affect version and fix version of child items are set to match the parent epic's **fix version**
  - Applies to both QE tasks (from QE epics) and dev stories (from Release epics)
  - Items without parent epic fix versions will be skipped for version sync
  - For QE tasks, version sync happens together with story points assignment for efficiency
