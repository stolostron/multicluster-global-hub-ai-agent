# Repository Instructions

## Scope

- This repository is an automation/skills repository, not the Multicluster Global Hub Go source tree. The product repositories live under `repos/` as Git submodules.
- The main executable application is the Python CVE service in `workflows/cve-service/`; its entrypoints are `run.py` and `python3 -m src.main`.
- Keep project-specific repository, component, release, and branch routing in `workflows/cve-service/config/repo_mapping.json`; do not hardcode a mapping in code or instructions.

## Setup And Verification

- Initialize dependencies before working with product repositories or the `acm-workflows` tools: `git submodule update --init --recursive`.
- Set up the CVE service from `workflows/cve-service/` with `./setup.sh`, or install dependencies directly with `pip3 install -r requirements.txt`.
- Create `workflows/cve-service/config/.env` from `.env.example` and fill required JIRA, GitHub, and Gemini settings. `src/config.py` loads this file automatically and `Config.validate()` requires all seven core credentials/settings.
- Run the service from `workflows/cve-service/` with `python3 run.py` or `python3 -m src.main`; it performs an immediate cycle, then polls on `POLL_INTERVAL_SECONDS` (default 300).
- Run focused checks from `workflows/cve-service/`: `python3 tests/test_workflow.py`, `python3 tests/test_gemini_repo_selection.py`, or `python3 tests/test_accurate_analysis.py`. These are live integration-style scripts, not isolated pytest tests: they validate credentials and may call JIRA, Gemini, CVE sources, GitHub, and `/tmp/workspace`.
- The Docker service is built/run from `workflows/cve-service/` with `docker-compose up -d`; it mounts SSH credentials and `.env`, so do not use it with untrusted changes.

## Service Workflow

- `src/main.py` resolves a target repository, runs Gemini analysis in two phases (repository selection, then analysis with local repository context), applies a generated fix, creates/tracks a PR, and closes the linked JIRA issue after merge.
- `config/repo_mapping.json` maps Global Hub components to `stolostron/multicluster-global-hub`, `stolostron/glo-grafana`, or `stolostron/postgres_exporter`, then maps product versions to each repository's branch.
- Generated CVE summaries under `workflows/cve-service/src/cve_summaries/` are ignored output. Do not treat them as source or commit them unless explicitly requested.
- The service clones target repositories into `WORKSPACE_DIR` (default `/tmp/workspace`) and uses SSH URLs; Git identity and GitHub SSH access must be configured for end-to-end runs.

## Credentials And External Systems

- For JIRA, GitHub, Jenkins, Konflux, GitLab, Slack, or Gemini access, source `workflows/cve-service/config/.env` as documented in `.cursor/rules/external-resources-env.mdc`; never print, commit, or echo its values.
- Use the relevant skill before external operations: `skills/fix-cve-pr/SKILL.md` for CVEs, `skills/jira-create/SKILL.md` for ACM issue creation, `skills/jenkins-e2e-polarion/SKILL.md` for Jenkins/E2E, `skills/konflux-gh-catalog-stage-release/SKILL.md` for Konflux catalog releases, and `skills/gitlab-gh-release-pipeline/SKILL.md` for release-pipeline script changes.

## Git And PR Safety

- All code changes to product repositories go through a PR; use DCO sign-off (`git commit -s`) and follow `skills/agent-config/SKILL.md`.
- For `stolostron/multicluster-global-hub` and `stolostron/postgres_exporter`, changes normally target `main`; release branches are fast-forwarded from `main`. Check `repo_branch_policy` and run `scripts/check-ffwd-push.sh` before any release-branch push.
- After every push to a GitHub PR branch, post a concise update with `gh pr comment <PR> --repo <owner/repo> ...`, as required by `.cursor/rules/github-pr-comment-on-update.mdc`.
- Never put tokens, credentials, internal hosts/routes, cluster names, or raw sensitive logs in commits, PR text, or comments.
- Changes to `repos/` are submodule pointer changes in this repository; commit the pointer here only after the nested repository change is committed/pushed through its own workflow.

## Repository Ownership

- `workflows/cve-service/src/` contains service orchestration and integrations; `workflows/cve-service/tests/` contains executable checks; `workflows/cve-service/config/` contains runtime configuration and routing.
- `skills/` contains reusable operational workflows. Prefer updating the relevant skill rather than duplicating its detailed procedure in this file.
- `.github/workflows/update-submodules.yml` updates tracked submodules daily or manually and opens an automated PR when pointers change; `.github/workflows/labels.yml` labels PRs opened by automation bots.
