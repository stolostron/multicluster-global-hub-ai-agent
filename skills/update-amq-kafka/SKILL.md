---
name: update-amq-kafka
description: Automated AMQ Streams and Kafka version update workflow for Multicluster Global Hub. Checks current versions, discovers latest available from RedHat operators catalog (stable channel), creates PR with updates, monitors CI checks, and transitions Jira task to Review state. Use when upgrading AMQ Streams operator or Kafka versions in Global Hub.
---

# Update AMQ Streams and Kafka Version

## Workflow Instructions

Execute the following steps in order to update AMQ Streams and Kafka versions in Multicluster Global Hub:

### Step 1: Check Current Versions

Read the current versions from the Global Hub codebase:

**File**: `repos/multicluster-global-hub/operator/pkg/controllers/transporter/protocol/strimzi_transporter.go`

Extract these constants:
- `DefaultAMQChannel` (line ~59) - Example: `"amq-streams-3.1.x"`
- `DefaultAMQKafkaVersion` (line ~70) - Example: `"4.1.0"`

Store these values as:
- `CURRENT_CHANNEL` - the version part (e.g., `3.1.x`)
- `CURRENT_KAFKA_VERSION` - the full version (e.g., `4.1.0`)

### Step 2: Discover Available Versions from Catalog

**Prerequisites**: Access to an OpenShift cluster with RedHat operators catalog.

Query the catalog using `oc` CLI:

```bash
oc get packagemanifest amq-streams -n openshift-marketplace -o json
```

From the output:
1. List all channels under `.status.channels[]`
2. Filter for channels matching pattern `amq-streams-*.x` or `stable`
3. Sort channels by semantic version
4. Select the latest channel (highest version)
5. Extract `currentCSV` from that channel
6. Map the channel version to Kafka version:
   - Pattern: `amq-streams-{major}.{minor}.x` → Kafka `{major+1}.{minor}.0`
   - Example: `amq-streams-3.2.x` → Kafka `4.2.0`

Store these values as:
- `AVAILABLE_CHANNEL` - the latest channel version (e.g., `3.2.x`)
- `AVAILABLE_KAFKA_VERSION` - the corresponding Kafka version (e.g., `4.2.0`)

**Version Mapping Table** (for reference):
- `amq-streams-3.1.x` → Kafka `4.1.0`
- `amq-streams-3.2.x` → Kafka `4.2.0`
- `amq-streams-3.3.x` → Kafka `4.3.0`
- `amq-streams-3.4.x` → Kafka `4.4.0`

### Step 3: Compare Versions

Compare current vs available versions using semantic versioning:

If `AVAILABLE_CHANNEL > CURRENT_CHANNEL` OR `AVAILABLE_KAFKA_VERSION > CURRENT_KAFKA_VERSION`:
- **Update Available**: Proceed to Step 4
- Display: "Update available: amq-streams-{CURRENT_CHANNEL} → amq-streams-{AVAILABLE_CHANNEL}, Kafka {CURRENT_KAFKA_VERSION} → {AVAILABLE_KAFKA_VERSION}"

Otherwise:
- **No Update Needed**: Stop workflow
- Display: "Already on latest versions. No update required."

### Step 4: Update Source Code

Update the file: `repos/multicluster-global-hub/operator/pkg/controllers/transporter/protocol/strimzi_transporter.go`

**Changes**:
1. Update line ~59:
   - FROM: `DefaultAMQChannel        = "amq-streams-{CURRENT_CHANNEL}"`
   - TO: `DefaultAMQChannel        = "amq-streams-{AVAILABLE_CHANNEL}"`

2. Update line ~70:
   - FROM: `DefaultAMQKafkaVersion         = "{CURRENT_KAFKA_VERSION}"`
   - TO: `DefaultAMQKafkaVersion         = "{AVAILABLE_KAFKA_VERSION}"`

**Verification**: Read the file back to confirm changes are correct.

### Step 5: Create Git Commit

Navigate to: `repos/multicluster-global-hub/`

Execute git commands:

1. **Create new branch**:
   ```bash
   git checkout -b update-amq-streams-{AVAILABLE_CHANNEL}-kafka-{AVAILABLE_KAFKA_VERSION}
   ```
   (Replace dots with dashes in branch name)

2. **Stage changes**:
   ```bash
   git add operator/pkg/controllers/transporter/protocol/strimzi_transporter.go
   ```

3. **Create commit with sign-off**:
   ```bash
   git commit -s -m "Update AMQ Streams to amq-streams-{AVAILABLE_CHANNEL} and Kafka to {AVAILABLE_KAFKA_VERSION}

   - Update DefaultAMQChannel from amq-streams-{CURRENT_CHANNEL} to amq-streams-{AVAILABLE_CHANNEL}
   - Update DefaultAMQKafkaVersion from {CURRENT_KAFKA_VERSION} to {AVAILABLE_KAFKA_VERSION}

   This update aligns with the latest stable release from RedHat operators catalog.

   Related: {JIRA_TASK}

   Signed-off-by: {GIT_USER} <{GIT_EMAIL}>
   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
   ```

**Notes**:
- Replace `{JIRA_TASK}` with the actual Jira task ID if provided
- Git will automatically add sign-off with configured user

### Step 6: Push Branch and Create Pull Request

1. **Push branch**:
   ```bash
   git push -u origin update-amq-streams-{AVAILABLE_CHANNEL}-kafka-{AVAILABLE_KAFKA_VERSION}
   ```

2. **Create PR using gh CLI**:
   ```bash
   gh pr create --title "Update AMQ Streams to amq-streams-{AVAILABLE_CHANNEL} and Kafka to {AVAILABLE_KAFKA_VERSION}" --body "$(cat <<'EOF'
   ## Summary

   - Update AMQ Streams operator channel from `amq-streams-{CURRENT_CHANNEL}` to `amq-streams-{AVAILABLE_CHANNEL}`
   - Update Kafka version from `{CURRENT_KAFKA_VERSION}` to `{AVAILABLE_KAFKA_VERSION}`

   ## Version Details

   | Component | Current | New |
   |-----------|---------|-----|
   | AMQ Streams Operator | amq-streams-{CURRENT_CHANNEL} | amq-streams-{AVAILABLE_CHANNEL} |
   | Kafka | {CURRENT_KAFKA_VERSION} | {AVAILABLE_KAFKA_VERSION} |

   ## Changes

   - Updated `DefaultAMQChannel` in `strimzi_transporter.go`
   - Updated `DefaultAMQKafkaVersion` in `strimzi_transporter.go`

   ## Testing

   - All existing tests should pass
   - No breaking changes expected (backward compatible update)

   ## Related Issues

   - Jira: {JIRA_TASK}

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

3. **Capture PR URL** from the output and store it for later steps.

### Step 7: Monitor CI Checks

Wait for all CI checks to complete:

1. **Initial wait**: 60 seconds for checks to register

2. **Poll check status** every 30 seconds:
   ```bash
   gh pr checks {PR_NUMBER} --json name,status,conclusion
   ```

3. **Display status** for each check:
   - ✓ = completed successfully
   - ⏳ = in progress or queued
   - ✗ = failed

4. **Check completion conditions**:
   - **SUCCESS**: All checks have `status: completed` and `conclusion: success`
   - **FAILURE**: Any check has `conclusion: failure`
   - **TIMEOUT**: Checks not completed within 30 minutes

5. **Continue to Step 8** only if all checks pass successfully.

**Example Status Display**:
```
Monitoring PR checks...
✓ build - success
✓ unit-tests-operator - success
✓ unit-tests-manager - success
✓ unit-tests-agent - success
⏳ e2e-tests - in_progress
⏳ integration-tests - queued

Waiting for checks to complete... (2 pending)
```

### Step 8: Update Jira Task

**Prerequisites**: Jira task ID must be provided by user.

If Jira task ID is provided:

1. **Add PR link as comment**:
   ```bash
   jira issue comment add {JIRA_TASK} "PR created for AMQ Streams and Kafka version update:
   {PR_URL}

   Version Changes:
   - AMQ Streams: amq-streams-{CURRENT_CHANNEL} → amq-streams-{AVAILABLE_CHANNEL}
   - Kafka: {CURRENT_KAFKA_VERSION} → {AVAILABLE_KAFKA_VERSION}

   All CI checks have passed. Ready for review."
   ```

2. **Transition task to Review state**:
   ```bash
   jira issue move {JIRA_TASK} "Review"
   ```

3. **Verify transition**:
   - Confirm task is now in "Review" status
   - Display success message

If Jira integration fails:
- Log warning but don't fail the workflow
- Instruct user to manually update Jira task

### Step 9: Final Summary

Display completion summary:

```
✓ AMQ Streams and Kafka Update Workflow Completed!

Version Updates:
- AMQ Streams: amq-streams-{CURRENT_CHANNEL} → amq-streams-{AVAILABLE_CHANNEL}
- Kafka: {CURRENT_KAFKA_VERSION} → {AVAILABLE_KAFKA_VERSION}

Pull Request: {PR_URL}
Status: All CI checks passed

Jira Task: {JIRA_TASK}
Status: Moved to Review

Next Steps:
1. Review the PR: {PR_URL}
2. Address any review comments
3. Merge when approved
```

## Error Handling

### No Updates Available

If Step 3 determines no updates are available:
```
ℹ Current versions:
  - AMQ Streams: amq-streams-{CURRENT_CHANNEL}
  - Kafka: {CURRENT_KAFKA_VERSION}

ℹ Latest available: Same versions

✓ Already on latest versions. No update required.
```

### Catalog Connection Failure

If Step 2 fails to connect to catalog:
```
✗ Cannot access catalog source 'redhat-operators' in namespace 'openshift-marketplace'

Please ensure:
1. KUBECONFIG points to a cluster with RedHat operators catalog
2. You have permissions to read CatalogSource and PackageManifest resources

Try: oc get catalogsource -n openshift-marketplace
```

### CI Checks Failed

If Step 7 detects failed checks:
```
✗ CI checks failed!

Failed checks:
- e2e-tests: failure
  Details: {CHECK_DETAILS_URL}

PR: {PR_URL}

Manual intervention required. Please:
1. Review the failure logs
2. Fix the issues
3. Push updates to the PR branch
4. CI will re-run automatically
```

### Jira Update Failed

If Step 8 fails:
```
⚠ Warning: Failed to update Jira task {JIRA_TASK}
Error: {ERROR_MESSAGE}

PR created successfully: {PR_URL}

Please manually:
1. Open Jira task: {JIRA_TASK_URL}
2. Add comment with PR link
3. Move task to Review state
```

## User Interaction Points

The workflow will ask for user input at these points:

1. **Before starting**: Confirm user wants to proceed with update
2. **Before creating PR**: Show summary of changes and ask for confirmation
3. **Jira task ID**: Ask if user wants to link a Jira task (optional)
4. **After PR creation**: Inform user that monitoring has started

## Prerequisites

Before starting this workflow, ensure:

1. **Tools installed**:
   - `oc` (OpenShift CLI)
   - `gh` (GitHub CLI, authenticated)
   - `git` (Git CLI)
   - `jq` (JSON processor)
   - `jira` (Jira CLI, authenticated - optional)

2. **Access configured**:
   - `KUBECONFIG` points to cluster with RedHat operators catalog
   - GitHub authentication via `gh auth login`
   - Jira authentication via `jira init` (if using Jira)
   - Write access to `stolostron/multicluster-global-hub` repository

3. **Repository cloned**:
   - Global Hub repository at: `repos/multicluster-global-hub/`
   - On main branch with latest changes

## Configuration

### Environment Variables

Optional environment variables to customize behavior:

- `CATALOG_NAMESPACE`: CatalogSource namespace (default: `openshift-marketplace`)
- `CATALOG_SOURCE`: CatalogSource name (default: `redhat-operators`)
- `OPERATOR_PACKAGE`: Operator package name (default: `amq-streams`)

### Verification Commands

Use these commands to verify prerequisites:

```bash
# Check OpenShift connection
oc get catalogsource redhat-operators -n openshift-marketplace

# Check GitHub authentication
gh auth status

# Check repository
ls repos/multicluster-global-hub/

# Check Jira (optional)
jira issue list --assignee $(jira me)
```

## Usage Examples

### Interactive Usage (Recommended)

Start the workflow and Claude will guide you through:
```
User: /update-amq-kafka
Claude: I'll check for AMQ Streams and Kafka updates. Do you have a KUBECONFIG set for a cluster with the RedHat operators catalog?
```

### With Jira Task

```
User: /update-amq-kafka with jira task ACM-12345
Claude: I'll update AMQ Streams/Kafka and link to Jira task ACM-12345. Checking current versions...
```

### Check Only (No Changes)

```
User: Check if there are AMQ Streams updates available but don't make changes
Claude: I'll check for available updates without modifying code. Querying catalog...
```

## Best Practices

1. **Run weekly checks**: Regularly check for updates to stay current
2. **Test environment first**: Test updates in non-production before GA
3. **Review release notes**: Check AMQ Streams release notes for breaking changes
4. **Coordinate with team**: Inform team before creating update PRs
5. **Monitor CI carefully**: Watch for unexpected test failures
6. **Link Jira tasks**: Always link updates to tracking tasks

## Troubleshooting

### "Package not found"

Verify package name:
```bash
oc get packagemanifest -n openshift-marketplace | grep -i kafka
```

### "Failed to create PR"

Check GitHub permissions:
```bash
gh repo view stolostron/multicluster-global-hub
```

### "CI timeout"

CI checks may take longer than 30 minutes for large test suites. You can:
- Monitor manually via PR URL
- Re-run the workflow after CI completes

## Version Compatibility

Supported version ranges:
- **AMQ Streams**: 2.8.x - 3.4.x
- **Kafka**: 3.8.x - 4.4.x
- **Global Hub**: 1.6.x - 1.8.x

Always verify compatibility with Global Hub requirements before updating.
