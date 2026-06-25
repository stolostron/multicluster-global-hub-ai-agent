# Claude Code Configuration for Multicluster Global Hub Agent

This directory contains Claude Code configuration and skills for the Multicluster Global Hub ecosystem.

## Directory Structure

```
.claude/
├── skills/
│   └── acm-workflows/          # Git submodule linking to ACM workflows and Jira tools
├── settings.local.json          # Local Claude Code settings
└── README.md                    # This file

skills/                          # Top-level, tool-agnostic skill directory
├── fix-cve-pr/                  # CVE PR fix workflow (works with Cursor and Claude Code)
└── update-amq-kafka/            # AMQ/Kafka version update workflow
```

## Skills

### Jira Tools (via acm-workflows submodule)

The jira-tools plugin is included via git submodule from [stolostron/acm-workflows](https://github.com/stolostron/acm-workflows).

**Available Skills:**
- `/jira-tools:regression-test-plan` - Generate comprehensive regression test plans
- `/jira-tools:acm-reg-test` - Automate ACM regression testing via Jenkins
- `/jira-tools:jira-breakdown` - Break down Jira Epics into child tasks
- `/jira-tools:release-plan` - Analyze release planning documents and generate Jira tickets
- `/jira-tools:zstream-test-plan` - Generate zStream test plans from Jira bugs
- `/jira-tools:gdoc-downloader` - Download Google Docs and Sheets
- `/jira-tools:test-plan-generator` - Generate comprehensive test plans
- `/jira-tools:jira-analyzer` - Analyze Jira issues for complexity and risk

**Agent:**
- `jira-administrator` - Specialized AI agent for Jira CRUD operations and ACM workflows

For full documentation, see: `.claude/skills/acm-workflows/Claude/plugins/jira-tools/README.md`

## Git Submodules

This repository uses git submodules to link external skills and repositories:

### Update submodules
```bash
# Initialize submodules (first time)
git submodule update --init --recursive

# Update all submodules to latest
git submodule update --remote --recursive

# Update specific submodule
git submodule update --remote .claude/skills/acm-workflows
```

### Clone this repo with submodules
```bash
git clone --recurse-submodules https://github.com/stolostron/multicluster-global-hub-agent
```

## Requirements for Jira Tools

**CLI Tools:**
- `jira` - Jira CLI (required)
- `jq` - JSON processor (required)
- `gh` - GitHub CLI (optional)

**MCP Servers:**
- Jenkins MCP server (for regression testing)

See the [jira-tools PLUGIN.md](.claude/skills/acm-workflows/Claude/plugins/jira-tools/PLUGIN.md) for detailed requirements and setup.
