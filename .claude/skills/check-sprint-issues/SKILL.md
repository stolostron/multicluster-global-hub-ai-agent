---
name: check-sprint-issues
description: Check Global Hub issues in current sprint for missing required fields and labels. Use to audit sprint issues before sprint end.
user-invocable: true
---

# Check Sprint Issues

Queries all Global Hub issues in the current sprint and identifies those missing required fields or labels.

## When to Use This Skill

- User says "check sprint issues" or "audit sprint"
- Before sprint end to ensure all issues are properly configured
- User asks about missing fields on sprint issues

## Current Sprint Calculation

- Format: `GH Sprint X` (e.g., "GH Sprint 1")
- GH Sprint 1 ends on 2026-04-01
- Each sprint is 3 weeks
- Auto-calculated based on current date

## Required Fields (All Issues)

1. **Activity Type** - must be set
2. **Story Points** - must be set (1/2/3/5/8)
3. **Priority** - must be set
4. **Severity** - must be set
5. **Affect Version** - must be set
6. **Fix Version** - must be set

## Required Labels (Stories Only)

1. **Engineering Status**: `Eng-Status:Green`
2. **QE Applicability**: `QE-Required` OR `QE-NotApplicable` (case-insensitive, only one is required)
3. **QE Confidence**: `QE-Confidence:Green` (only if `QE-Required` exists)
4. **Documentation Status**: `doc-required` OR `doc-not-required`
5. **Sprint Label**: `Sprint1`, `Sprint2`, etc.

**Note**: QE label checking is case-insensitive. Any of `QE-Required`, `qe-required`, `QE-REQUIRED` will be recognized.

## Instructions

When this skill is invoked:

1. **Run the Check Script**:
   ```bash
   ~/.claude/skills/check-sprint-issues/check-sprint-issues.sh
   ```

2. **Optional: Specify Sprint**:
   ```bash
   SPRINT=2 ~/.claude/skills/check-sprint-issues/check-sprint-issues.sh
   ```

## Output

The script outputs:
- Total issues found in sprint
- Issues missing each required field
- Stories missing required labels
- Summary with issue links

## Prerequisites

- `JIRA_TOKEN` environment variable must be set
- `JIRA_USER` environment variable must be set

## Examples

### Example 1: Check Current Sprint
```bash
~/.claude/skills/check-sprint-issues/check-sprint-issues.sh
```

### Example 2: Check Specific Sprint
```bash
SPRINT=2 ~/.claude/skills/check-sprint-issues/check-sprint-issues.sh
```
