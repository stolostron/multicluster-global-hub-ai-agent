# Update AMQ Streams and Kafka Version Skill

Automated workflow for updating AMQ Streams operator and Kafka versions in Multicluster Global Hub.

## Overview

This skill provides a complete workflow executed directly by Claude Code to:
1. Check current AMQ Streams and Kafka versions in the codebase
2. Discover latest available versions from RedHat operators catalog
3. Update source code if newer versions are available
4. Create signed commit and pull request
5. Monitor all CI checks
6. Update Jira task and transition to Review state

## Quick Start

### Interactive Usage

Simply invoke the skill and Claude will guide you through the process:

```
/update-amq-kafka
```

Claude will:
- Ask for confirmation before each major step
- Request Jira task ID (optional)
- Show progress updates
- Handle errors gracefully

### With Jira Integration

Link the update to a Jira task:

```
/update-amq-kafka with jira task ACM-12345
```

### Check Only Mode

Check for updates without making changes:

```
Check if AMQ Streams updates are available but don't make changes
```

## Prerequisites

### Required Tools

Ensure these tools are installed and configured:

```bash
# OpenShift CLI
oc version

# GitHub CLI (authenticated)
gh auth status

# Git
git --version

# JSON processor
jq --version

# Jira CLI (optional, for Jira integration)
jira version
```

### Required Access

1. **OpenShift Cluster**
   - Cluster with RedHat operators catalog
   - CatalogSource `redhat-operators` in `openshift-marketplace` namespace
   - Read permissions for CatalogSource and PackageManifest

   ```bash
   # Verify access
   export KUBECONFIG=~/.kube/config-your-cluster
   oc get catalogsource redhat-operators -n openshift-marketplace
   ```

2. **GitHub Repository**
   - Write access to `stolostron/multicluster-global-hub`
   - Branch creation permissions
   - PR creation permissions

   ```bash
   # Verify access
   gh repo view stolostron/multicluster-global-hub
   ```

3. **Jira** (Optional)
   - Access to your Jira project
   - Read/write permissions on issues
   - Transition permissions to Review state

   ```bash
   # Verify access
   jira issue list
   ```

### Repository Setup

The Global Hub repository should be cloned at:

```
repos/multicluster-global-hub/
```

Verify:
```bash
ls repos/multicluster-global-hub/operator/pkg/controllers/transporter/protocol/strimzi_transporter.go
```

## How It Works

### Step-by-Step Workflow

1. **Version Discovery**
   - Reads current versions from `strimzi_transporter.go`
   - Queries RedHat operators catalog via `oc` CLI
   - Parses available channels and maps to Kafka versions
   - Compares using semantic versioning

2. **Code Updates**
   - Updates `DefaultAMQChannel` constant
   - Updates `DefaultAMQKafkaVersion` constant
   - Preserves code formatting

3. **Git Operations**
   - Creates feature branch
   - Stages changes
   - Creates signed commit with detailed message
   - Pushes to remote

4. **PR Creation**
   - Creates PR with descriptive title
   - Includes version comparison table
   - Links to Jira task (if provided)
   - Auto-assigns reviewers

5. **CI Monitoring**
   - Waits for checks to start (60s)
   - Polls status every 30s
   - Displays real-time progress
   - Detects failures immediately

6. **Jira Integration**
   - Adds PR link as comment
   - Posts version change details
   - Transitions task to Review
   - Notifies assignee

### Version Mapping

The skill uses this mapping to determine Kafka versions:

| AMQ Streams Channel | Kafka Version | Global Hub |
|---------------------|---------------|------------|
| amq-streams-3.1.x   | 4.1.0        | 1.6.x, 1.7.x |
| amq-streams-3.2.x   | 4.2.0        | 1.7.x, 1.8.x |
| amq-streams-3.3.x   | 4.3.0        | 1.8.x, 1.9.x |
| amq-streams-3.4.x   | 4.4.0        | 1.9.x |

Pattern: `amq-streams-{major}.{minor}.x` → Kafka `{major+1}.{minor}.0`

## Environment Configuration

### Optional Environment Variables

```bash
# Catalog configuration
export CATALOG_NAMESPACE=openshift-marketplace  # Default
export CATALOG_SOURCE=redhat-operators          # Default
export OPERATOR_PACKAGE=amq-streams             # Default

# Cluster access
export KUBECONFIG=~/.kube/config-cluster
```

### Custom Catalog

To use a different catalog source:

```bash
export CATALOG_SOURCE=custom-operators
export CATALOG_NAMESPACE=custom-marketplace
```

## Usage Scenarios

### Weekly Update Check

Check for updates regularly:

```
Every Monday, check for AMQ Streams updates
```

Claude will set up a recurring check.

### Urgent Security Update

Fast-track a security update:

```
/update-amq-kafka
[Confirm immediately]
[Provide Jira security task ID]
```

### Test Environment Update

Update test environment first:

```
Update AMQ Streams in test environment first, then create PR for production
```

## Error Handling

The skill handles common errors gracefully:

### No Updates Available
```
ℹ Already on latest versions
  - AMQ Streams: amq-streams-3.2.x
  - Kafka: 4.2.0

No action needed.
```

### Catalog Connection Failure
```
✗ Cannot access catalog source

Ensure KUBECONFIG points to a cluster with RedHat operators catalog.
Try: oc get catalogsource -n openshift-marketplace
```

### CI Check Failure
```
✗ CI check failed: e2e-tests

PR: https://github.com/stolostron/multicluster-global-hub/pull/123

Review the failure and update the PR manually.
```

### Jira Update Failure
```
⚠ Failed to update Jira task ACM-12345

PR created: https://github.com/stolostron/multicluster-global-hub/pull/123

Please manually update Jira task.
```

## Best Practices

1. **Regular Checks**: Run weekly to stay aware of new versions
2. **Test First**: Always test in non-production environment
3. **Review Notes**: Check AMQ Streams release notes before updating
4. **Team Coordination**: Inform team before creating update PRs
5. **Monitor CI**: Don't skip CI monitoring for production updates
6. **Jira Tracking**: Always link to Jira tasks for audit trail
7. **Version Validation**: Verify compatibility with Global Hub matrix

## Troubleshooting

### Cannot Query Catalog

**Problem**: `oc` cannot connect to cluster

**Solution**:
```bash
# Check kubeconfig
echo $KUBECONFIG
oc cluster-info

# List available catalogs
oc get catalogsource -n openshift-marketplace
```

### GitHub Authentication Failed

**Problem**: `gh` CLI not authenticated

**Solution**:
```bash
gh auth login
gh auth status
```

### PR Creation Blocked

**Problem**: Cannot create PR due to permissions

**Solution**:
```bash
# Verify repository access
gh repo view stolostron/multicluster-global-hub

# Check current user
gh api user | jq '.login'
```

### Jira Transition Error

**Problem**: Cannot move task to Review

**Solution**:
```bash
# Check available transitions
jira issue transitions ACM-12345

# Try manual transition
jira issue move ACM-12345 "Review"
```

## Integration

This skill works with other workflows:

- **daily-jira-sync**: Track update tasks in daily sync
- **PR review workflows**: Standard PR review after creation
- **release planning**: Coordinate updates with release schedule

## Advanced Usage

### Force Specific Versions

While not recommended, you can manually update to specific versions by editing the file directly and creating a PR manually.

### Multiple Repository Updates

If updating multiple repositories:
1. Run skill for each repository
2. Coordinate PR merges
3. Update dependencies in sequence

### Automated Scheduling

Set up automated checks:

```
Set up a weekly check for AMQ Streams updates every Monday at 9am
```

Claude can configure recurring checks.

## Security Considerations

- **Token Storage**: GitHub and Jira tokens are handled by authenticated CLIs
- **Cluster Access**: Use minimal RBAC permissions for catalog queries
- **PR Reviews**: Always require human review before merging
- **Version Validation**: Only accept versions from trusted RedHat catalog

## Support

For issues:
1. Check prerequisites are met
2. Verify environment variables
3. Review error messages
4. Check tool versions
5. Consult Global Hub team

## References

- [AMQ Streams Documentation](https://access.redhat.com/documentation/en-us/red_hat_amq_streams)
- [Operator Lifecycle Manager](https://olm.operatorframework.io/)
- [Global Hub Repository](https://github.com/stolostron/multicluster-global-hub)
- [Strimzi Project](https://strimzi.io/)
