---
name: bump-go-zstream
description: >-
  Bump Go to 1.26.3 on a Global Hub z-stream release line (1.3–1.8).
  Updates multicluster-global-hub, postgres_exporter, glo-grafana, and openshift/release
  Prow builder config. Includes SonarCloud workflow fixes (pinned action SHAs, go tool directive).
  Use when bumping Go on a GH z-stream branch (e.g. "bump go 1.26.3 on 1.4 branch") after 1.7.2 pattern is done.
---

# Bump Go 1.26.3 — Global Hub Z-Stream

Repeatable workflow modeled on GH 1.7.2 (release-2.16) PRs:

| Repo | GH version → branch | Reference PR |
|------|---------------------|--------------|
| stolostron/multicluster-global-hub | 1.4 → `release-2.13`, 1.5 → `release-2.14`, 1.6 → `release-2.15`, 1.7 → `release-2.16`, 1.8 → `release-2.17` | [#2581](https://github.com/stolostron/multicluster-global-hub/pull/2581) |
| stolostron/postgres_exporter | same ACM branch as hub | [#227](https://github.com/stolostron/postgres_exporter/pull/227) |
| stolostron/glo-grafana | 1.4 → `release-1.4`, 1.5 → `release-1.5`, … | [#313](https://github.com/stolostron/glo-grafana/pull/313) (1.7; 1.4 is smaller) |
| openshift/release | `stolostron-multicluster-global-hub-release-2.XX.yaml` | [#81274](https://github.com/openshift/release/pull/81274) |

Branch map: `workflows/cve-service/config/repo_mapping.json` → `repo_version_to_branch`.

## Phase 1 — multicluster-global-hub

Target branch: `release-2.XX` for GH `1.Y`.

1. **`go.mod`**: `go 1.26.3` + `tool` block for `gci` and `gofumpt`.
2. **Konflux/Prow Dockerfiles**: `rhel_9_1.25` → `rhel_9_1.26` in `*/Containerfile.*`; `go1.25-linux` → `go1.26-linux` in `*/Dockerfile`.
3. **`test/script/util.sh`**: `GO_VERSION=go1.26.3`.
4. **`.github/workflows/go.yml`**:
   - `actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7`
   - `actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16 # v6` with `go-version: '1.26'`
   - Replace separate `go install gci/gofumpt` with `go install tool` ([#2589](https://github.com/stolostron/multicluster-global-hub/pull/2589))
   - Pin third-party actions to full SHAs ([#2582](https://github.com/stolostron/multicluster-global-hub/pull/2582), [#2584](https://github.com/stolostron/multicluster-global-hub/pull/2584))
   - On branches with `golangci-lint` job: pin `golangci/golangci-lint-action@ba0d7d2ec06a0ea1cb5fa41b2e4a3ab91d21278a # v9` + `install-mode: goinstall`
5. **`.github/workflows/e2e.yml`**: `GO_VERSION: '1.26'` + pinned checkout/setup-go SHAs.
6. **Tool deps in go.sum** (do **not** run full `go mod tidy` on old release branches):

```bash
GOTOOLCHAIN=go1.26.3 go get -tool github.com/daixiang0/gci@v0.14.0 mvdan.cc/gofumpt@v0.7.0
```

## Phase 2 — postgres_exporter

Branch: same `release-2.XX` as hub for that GH version.

- `go.mod`: `go 1.26.3`
- `Containerfile.konflux`: `rhel_9_1.26`
- `.promu.yml`: `version: 1.26` (if present)
- `GOTOOLCHAIN=go1.26.3 go mod tidy` (safe on this small module)

## Phase 3 — glo-grafana

Branch: `release-1.Y` (not the ACM `release-2.XX` branch).

**1.4 / older lines** (no `.citools/`): only bump:

- `go.mod` → `go 1.26.3`
- `Containerfile.konflux` → `rhel_9_1.26`
- `Dockerfile.ocp` → `go1.26-linux` (if present)

**1.7+ lines**: follow [#313](https://github.com/stolostron/glo-grafana/pull/313) — also update `.citools/src/*/go.mod`, workspace `go.mod` files, **`go.work`**, bump root `golang.org/x/net` (v0.55.0) and `golang.org/x/crypto` (v0.52.0), add matching **`.trivyignore`** workspace false-positive entries, then `go work sync`.

## Phase 4 — openshift/release

File: `ci-operator/config/stolostron/multicluster-global-hub/stolostron-multicluster-global-hub-release-2.XX.yaml`

- `build_root.image_stream_tag.tag`: `go1.25-linux` → `go1.26-linux`
- If `base_images` has `stolostron_builder_go1.25-linux`, rename to `go1.26-linux` (see [#81274](https://github.com/openshift/release/pull/81274))

**Do not** run `make update` unless the user asks — config-only one-line changes are enough for builder bump.

After merge of hub go.mod PR, rehearse sonarcloud on the release PR:

```
/pj-rehearse pull-ci-stolostron-multicluster-global-hub-release-2.XX-sonarcloud
/pj-rehearse ack
```

## PR checklist

- [ ] Hub PR → `release-2.XX` (SonarCloud + format job green)
- [ ] postgres_exporter PR → `release-2.XX`
- [ ] glo-grafana PR → `release-1.Y`
- [ ] openshift/release PR → `main` (companion to hub; rehearse sonarcloud)
- [ ] DCO sign-off on every commit (`skills/agent-config/SKILL.md`)
- [ ] PR comment after each push (`.cursor/rules/github-pr-comment-on-update.mdc`)

## Branch naming

```
acm-go1.26-multicluster-global-hub-1.Y
acm-go1.26-postgres-exporter-1.Y
acm-go1.26-glo-grafana-1.Y
acm-go1.26-multicluster-global-hub-1.Y   # openshift/release
```

## Z-stream lines (Go 1.26.3 bump)

| GH | Hub branch | Status |
|----|------------|--------|
| 1.8 | release-2.17 | [#2605](https://github.com/stolostron/multicluster-global-hub/pull/2605) + postgres [#231](https://github.com/stolostron/postgres_exporter/pull/231) + grafana [#319](https://github.com/stolostron/glo-grafana/pull/319) + release [#81357](https://github.com/openshift/release/pull/81357) |
| 1.7 | release-2.16 | done (1.7.2 — [#2581](https://github.com/stolostron/multicluster-global-hub/pull/2581), [#81274](https://github.com/openshift/release/pull/81274)) |
| 1.6 | release-2.15 | [#2604](https://github.com/stolostron/multicluster-global-hub/pull/2604) + postgres [#230](https://github.com/stolostron/postgres_exporter/pull/230) + grafana [#318](https://github.com/stolostron/glo-grafana/pull/318) + release [#81356](https://github.com/openshift/release/pull/81356) |
| 1.5 | release-2.14 | [#2603](https://github.com/stolostron/multicluster-global-hub/pull/2603) + postgres [#229](https://github.com/stolostron/postgres_exporter/pull/229) + grafana [#317](https://github.com/stolostron/glo-grafana/pull/317) + release [#81355](https://github.com/openshift/release/pull/81355) |
| 1.4 | release-2.13 | [#2602](https://github.com/stolostron/multicluster-global-hub/pull/2602) + postgres [#228](https://github.com/stolostron/postgres_exporter/pull/228) + grafana [#316](https://github.com/stolostron/glo-grafana/pull/316) + release [#81354](https://github.com/openshift/release/pull/81354) |
| 1.3 | release-2.12 | **EOL — skip** |
