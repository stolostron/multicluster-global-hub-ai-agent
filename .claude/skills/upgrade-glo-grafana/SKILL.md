---
name: upgrade-glo-grafana
description: Upgrade glo-grafana repository by syncing latest code from stolostron/grafana upstream, cherry-picking Global Hub specific commits (including the base commit), squashing into a single commit, and creating a PR. Use when upgrading Grafana version for Global Hub or syncing with upstream grafana changes.
---

# Upgrade glo-grafana Repository

## Overview

This skill upgrades the `stolostron/glo-grafana` repository by:
1. Syncing latest code from `stolostron/grafana` upstream branch
2. Cherry-picking Global Hub specific commits (including the base commit) on top of the synced code
3. Squashing all cherry-picked commits into a single commit: "Re-apply Global Hub specific commits on top"
4. Creating a PR to the target release branch

## Workflow Instructions

Execute the following steps in order to upgrade glo-grafana:

### Step 1: Initialize and Prepare Repository

Navigate to the glo-grafana submodule and ensure it's initialized:

```bash
cd /root/go/src/github.com/stolostron/multicluster-global-hub-ai-agent
git submodule update --init repos/glo-grafana
cd repos/glo-grafana
```

### Step 2: Gather Information from User

Ask the user for the following information:

1. **Upstream branch**: The branch from `stolostron/grafana` to sync from (e.g., `release-2.17`)
2. **Base commit**: The FIRST Global Hub specific commit hash - this commit AND all commits after it will be cherry-picked (e.g., `8b094630b98f95eb92a85098a19b769e34aa8a77`)
3. **Target branch**: The branch in glo-grafana to create PR against (e.g., `release-1.8`)

Store these values as:
- `UPSTREAM_BRANCH` - e.g., `release-2.17`
- `BASE_COMMIT` - e.g., `8b094630b98f95eb92a85098a19b769e34aa8a77`
- `TARGET_BRANCH` - e.g., `release-1.8`

### Step 3: Identify Commits to Cherry-pick

List all commits starting from and including the base commit:

```bash
# List commits from base commit to HEAD (inclusive)
git log --oneline {BASE_COMMIT}^..HEAD
```

**IMPORTANT**: The base commit itself must be included in the cherry-pick list. The commits to cherry-pick are:
- `{BASE_COMMIT}` (the base commit - must be included!)
- All commits after `{BASE_COMMIT}` up to HEAD

Store the list of commit hashes in order (oldest first) as `COMMITS_TO_CHERRY_PICK`.

Display the commits to the user and ask for confirmation before proceeding.

### Step 4: Add Upstream Remote and Fetch

Add the stolostron/grafana repository as upstream remote and fetch the target branch:

```bash
git remote add upstream https://github.com/stolostron/grafana.git 2>/dev/null || echo "Remote exists"
git fetch upstream {UPSTREAM_BRANCH}
```

### Step 5: Create New Branch from Upstream

Create a new branch based on the upstream code:

```bash
git checkout -b upgrade-to-grafana-{UPSTREAM_BRANCH} upstream/{UPSTREAM_BRANCH}
```

Store the new branch name as `NEW_BRANCH` (e.g., `upgrade-to-grafana-2.17`).

### Step 6: Cherry-pick Global Hub Commits

Cherry-pick each commit in order from oldest to newest, **starting with the base commit**:

```bash
git cherry-pick {BASE_COMMIT}
git cherry-pick {NEXT_COMMIT}
# ... continue for all commits
```

**Conflict Resolution Guidelines**:

1. **Delete conflicts** (file deleted in cherry-pick but modified in HEAD):
   - If the original intent was to delete the file, use `git rm {file}` then `git cherry-pick --continue`
   - Common for workflow files being removed (e.g., `.github/workflows/*.yml`)

2. **Content conflicts in go.mod**:
   - Keep the newer Go version from upstream (e.g., `go 1.25.7`)
   - Keep the CVE fix (replace directive) from the cherry-picked commit:
     ```
     // Override containerd to fix CVE-2024-25621 (local privilege escalation)
     replace github.com/containerd/containerd => github.com/containerd/containerd v1.7.29
     ```
   - Use `git add go.mod` then `git cherry-pick --continue`

3. **Content conflicts in other go.mod/go.sum files**:
   - For `.citools/src/cog/go.mod`, `pkg/codegen/go.mod`, `pkg/plugins/codegen/go.mod`:
   - Accept upstream version: `git checkout --ours {file}`
   - Then `git add {file}`

4. **Rename conflicts** (file renamed differently in both branches):
   - Common for `.tekton/` files
   - Keep BOTH sets of files:
     - Upstream ACM files (e.g., `grafana-acm-217-*.yaml`)
     - Global Hub files (e.g., `glo-grafana-globalhub-1-8-*.yaml`)
   - Use `git checkout --theirs {glo-grafana-file}` to get the Global Hub version
   - Add all: `git add .tekton/`

5. **Containerfile.konflux conflicts**:
   - Use Global Hub version: `git checkout --theirs Containerfile.konflux`

6. **Dockerfile.ocp conflicts**:
   - Keep upstream version: `git checkout --ours Dockerfile.ocp`

After each conflict resolution, continue with:
```bash
git cherry-pick --continue --no-edit
```

### Step 7: Squash All Commits into One

After all cherry-picks are complete, squash all Global Hub commits into a single commit:

```bash
# Reset to upstream base, keeping all changes staged
git reset --soft upstream/{UPSTREAM_BRANCH}

# Create single commit
git commit -s -m "Re-apply Global Hub specific commits on top

This commit applies all Global Hub specific changes on top of
stolostron/grafana {UPSTREAM_BRANCH} (Grafana {GRAFANA_VERSION}):

- Apply Global Hub Konflux config and CVE fixes
- Remove failing upstream Grafana workflows
- Upgrade golang and use common-base.yaml
- Update glo-grafana for {TARGET_BRANCH}

Signed-off-by: {GIT_USER} <{GIT_EMAIL}>
Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Step 8: Verify Final Commit

Verify the commit history shows exactly one Global Hub commit on top of upstream:

```bash
git log --oneline -5
```

Expected output:
```
{NEW_HASH} Re-apply Global Hub specific commits on top
{UPSTREAM_HASH} Merge pull request #XXX from ...
...
```

### Step 9: Configure Remote for Push

Check if user has push access to stolostron/glo-grafana:

```bash
git remote set-url origin git@github.com:stolostron/glo-grafana.git
git push -u origin {NEW_BRANCH}
```

If permission denied, use user's fork:

```bash
# Get GitHub username
gh auth status

# Add user's fork as remote
git remote add myfork git@github.com:{USERNAME}/glo-grafana.git
git push -u myfork {NEW_BRANCH}
```

### Step 10: Create Pull Request

Create a PR to the target branch:

```bash
gh pr create --repo stolostron/glo-grafana --base {TARGET_BRANCH} --head {USERNAME}:{NEW_BRANCH} --title "Upgrade glo-grafana to Grafana {GRAFANA_VERSION} (stolostron/grafana {UPSTREAM_BRANCH})" --body "$(cat <<'EOF'
## Summary
- Sync latest code from https://github.com/stolostron/grafana {UPSTREAM_BRANCH} branch (Grafana {GRAFANA_VERSION})
- Re-apply Global Hub specific commits on top of the synced code

## Changes
This upgrade brings the latest Grafana improvements including:
- All upstream Grafana improvements and bug fixes
- CVE fixes included in stolostron/grafana {UPSTREAM_BRANCH}
- Retains Global Hub specific configurations:
  - Konflux pipelines for release-1.8
  - Containerfile.konflux
  - stolostron-patches for auth proxy header forwarding
  - CVE fixes (containerd, glob, node-forge)

## Test plan
- [ ] Verify Konflux build pipeline works correctly
- [ ] Test Grafana deployment in Global Hub environment
- [ ] Verify datasource proxy authentication works

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

### Step 11: Final Summary

Display completion summary:

```
✓ glo-grafana Upgrade Workflow Completed!

Upstream Sync:
- Source: stolostron/grafana {UPSTREAM_BRANCH}
- Grafana Version: {GRAFANA_VERSION}

Final Commit: {COMMIT_HASH} - "Re-apply Global Hub specific commits on top"

Pull Request: {PR_URL}
Target Branch: {TARGET_BRANCH}

Next Steps:
1. Review the PR: {PR_URL}
2. Wait for CI checks to pass
3. Address any review comments
4. Merge when approved
```

## Error Handling

### Remote Already Exists

If upstream remote already exists:
```bash
git remote set-url upstream https://github.com/stolostron/grafana.git
```

### Cherry-pick Fails Completely

If a cherry-pick cannot be resolved:
```bash
git cherry-pick --abort
```
Then analyze the commit manually and consider creating a new commit with the same changes.

### Branch Already Exists

If the new branch already exists:
```bash
git branch -D upgrade-to-grafana-{UPSTREAM_BRANCH}
git checkout -b upgrade-to-grafana-{UPSTREAM_BRANCH} upstream/{UPSTREAM_BRANCH}
```

### Push Permission Denied

If user cannot push to stolostron/glo-grafana:
1. Check if user has a fork: `gh repo list {USERNAME} --json name | grep glo-grafana`
2. If no fork exists: `gh repo fork stolostron/glo-grafana --clone=false`
3. Add fork as remote and push there

### Need to Update PR After Fixes

If you need to fix issues and update the PR:
```bash
# Make fixes
git add -A
git commit --amend --no-edit
git push myfork {NEW_BRANCH} --force
```

## Prerequisites

Before starting this workflow, ensure:

1. **Tools installed**:
   - `git` (Git CLI)
   - `gh` (GitHub CLI, authenticated)

2. **Access configured**:
   - GitHub authentication via `gh auth login`
   - SSH keys configured for GitHub
   - Fork of `stolostron/glo-grafana` (if no direct push access)

3. **Repository prepared**:
   - glo-grafana submodule initialized
   - Working directory clean (no uncommitted changes)

## Usage Examples

### Standard Upgrade

```
User: /upgrade-glo-grafana
Claude: I'll help you upgrade glo-grafana. Please provide:
1. Upstream branch from stolostron/grafana (e.g., release-2.17)
2. Base commit hash - the FIRST Global Hub specific commit (this commit will be included)
3. Target branch for the PR (e.g., release-1.8)
```

### With All Parameters

```
User: Upgrade glo-grafana from stolostron/grafana release-2.17, base commit is 8b094630b9, PR to release-1.8
Claude: I'll upgrade glo-grafana by syncing release-2.17 and cherry-picking commits starting from 8b094630b9...
```

## Version Mapping

Common version mappings between branches:

| stolostron/grafana | glo-grafana | Global Hub | Grafana |
|-------------------|-------------|------------|---------|
| release-2.15      | release-1.6 | v1.6.x     | v12.0.x |
| release-2.16      | release-1.7 | v1.7.x     | v12.2.x |
| release-2.17      | release-1.8 | v1.8.x     | v12.4.x |

## Key Files in Global Hub Commits

The base commit typically includes these Global Hub specific files:

1. **Konflux Configuration**:
   - `.tekton/glo-grafana-globalhub-*-pull-request.yaml`
   - `.tekton/glo-grafana-globalhub-*-push.yaml`
   - `Containerfile.konflux`
   - `renovate.json`

2. **Patches**:
   - `stolostron-patches/` - Auth proxy header forwarding patch

3. **CVE Fixes**:
   - `go.mod` - containerd replace directive
   - `package.json` / `yarn.lock` - glob, node-forge upgrades
   - `public/build/` - Updated build artifacts

4. **Removed Workflows**:
   - Various `.github/workflows/*.yml` files that fail in glo-grafana context

## Best Practices

1. **Include base commit**: The base commit contains critical Global Hub config - don't skip it!
2. **Squash to single commit**: Final PR should have exactly one commit: "Re-apply Global Hub specific commits on top"
3. **Preserve CVE fixes**: Always keep security patches (go.mod replace directives, package.json upgrades)
4. **Keep both tekton files**: ACM and Global Hub use different Konflux pipelines - keep both
5. **Use correct Containerfile**: glo-grafana uses `Containerfile.konflux`, not `Containerfile.operator`
6. **Verify YAML syntax**: After resolving tekton file conflicts, ensure no merge markers remain
