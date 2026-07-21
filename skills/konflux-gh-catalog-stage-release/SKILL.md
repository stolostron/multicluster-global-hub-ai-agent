---
name: konflux-gh-catalog-stage-release
description: Konflux stage catalog/bundle release workflow for Multicluster Global Hub z-stream RCs. Use when helping with GH catalog stage publish, verify-conforma failures, catalog-bundle gate, stage-publish-catalog-* releases, EC checks on multicluster-global-hub-operator-catalog, or rc7/rcN catalog troubleshooting in acm-multicluster-glo-tenant.
---

# Konflux GH catalog stage release

Run Global Hub z-stream RC stage releases in Konflux (`acm-multicluster-glo-tenant`).

Repo scripts and docs live in `chunlin-acm-global-hub-release`:
- `pre-release/catalog-bundle-stage-gate.md`
- `lib/verify-catalog-bundle-gate.sh`
- `lib/create-konflux-release.sh`, `release/03-release-bundle.sh`, `release/04-release-catalog.sh`
- `lib/retry-catalog-release-staggered.sh`, `lib/common.sh` (`delete_release_before_recreate`)

Konflux context (typical): `acm-multicluster-glo-tenant/<konflux-api-host>:6443/<username>` (from `oc config current-context`)

Catalog repo: `stolostron/multicluster-global-hub-operator-catalog` (branch `release-X.Y`).

> **CRITICAL — never use a fork PR for catalog repo changes.**
> Konflux's `git-clone` task fetches by commit SHA from the PR's source URL.
> If the source is a fork (e.g. `birsanv/multicluster-global-hub-operator-catalog`),
> the clone fails with "repository not found". Always push directly to `upstream/release-X.Y`
> (the `stolostron` remote):
> ```bash
> git push upstream release-1.8   # not: git push origin ...
> ```

## Mandatory takeaway

Takeaway for next RC: per OCP variant, wait for EC green/neutral on GitHub before running catalog stage — on-push green alone isn’t enough for 418.

**On-push success ≠ ready for stage catalog publish.** Each OCP component has a separate GitHub check:

| Check | Meaning |
|-------|---------|
| `…-on-push` | Catalog image built (IIB index in quay) |
| `global-hub-catalog-4-XX-enterprise-contract-…` | Conforma/EC on build attestation — **must not be `failure`** before stage release |

Stage `verify-conforma` re-reads the catalog build attestation. If EC failed (e.g. `fbc-target-index-pruning-check`), stage release fails even when on-push is green.

`neutral` EC (warnings only) is OK — same as passing 419–422 runs.

## Release order (do not skip)

```
1. Merge CVE/fix PRs + catalog MintMaker bundle nudge on release-X.Y
2. stage-publish bundle RC  (03-release-bundle.sh) — wait Released=True
3. Wait for on-push catalog builds on all OCP variants (418–422 for 1.8)
4. Verify EC green/neutral per OCP on GitHub (see below)
5. ./lib/verify-catalog-bundle-gate.sh vX.Y.Z
6. stage-publish catalog RC per OCP (04-release-catalog.sh or Release CR)
7. Record iib: tags → Jenkins CATALOG_IMAGE
```

**Catalog before bundle** → OLM `BundleUnpackFailed` / `manifest unknown`.  
**Stage release before EC clean** → `verify-conforma` / `test.no_failed_tests` / `fbc-target-index-pruning-check`.

## Pre-stage checklist (per OCP variant)

For each OCP compact version (e.g. 418, 419, …):

```
- [ ] Latest push snapshot exists for release-catalog-{ocp}-globalhub-{line}
- [ ] GitHub on-push check: conclusion success
- [ ] GitHub EC check (global-hub-catalog-4-XX-enterprise-contract): NOT failure
- [ ] Bundle stage release shasum matches catalog-template-current.json
- [ ] Pin snapshot on Release CR if latest push is configs-only (#516) but EC-clean snapshot exists
```

## Verify EC on GitHub (automate this)

Given catalog commit SHA (from snapshot annotation or branch HEAD):

```bash
COMMIT=<sha>   # e.g. from snapshot pac.test.appstudio.openshift.io/sha
OCP=418        # compact version

gh api "repos/stolostron/multicluster-global-hub-operator-catalog/commits/${COMMIT}/check-runs?per_page=30" \
  --jq '.check_runs[] | select(.name | contains("'"${OCP}"'")) | {name, conclusion, status}'
```

Block catalog stage if any matching check has `conclusion: failure`.

Trigger fresh catalog rebuild when EC failed on an older snapshot:

```bash
oc annotate component multicluster-global-hub-operator-catalog-v418-globalhub-1-8 \
  -n acm-multicluster-glo-tenant \
  build.appstudio.openshift.io/request=build --overwrite
```

Wait for new on-push + EC on the **new** commit before stage release.

## Retry failed stage catalog release

1. Identify bad snapshot (EC failure on GitHub for that commit).
2. Use a snapshot whose commit has EC **neutral** or **success** (may differ from latest push title).
3. `delete_release_before_recreate` — wait **300s** (not only 120s) after real conforma failure to avoid stale `managed-*` reuse.
4. Create Release CR with **pinned** snapshot; do not blindly pick latest push if gate flags configs-only snapshot.

```bash
RELEASE=stage-publish-catalog-418-glo-180-release-rc7
SNAP=release-catalog-418-globalhub-1-8-20260603-214513-000
PLAN=catalog-418-publish-stage-globalhub-1-8
# delete, cooldown, oc create Release ...
```

## Failure triage

| Symptom | Likely cause | Owner |
|---------|--------------|-------|
| `verify-conforma` + `fbc-target-index-pruning-check` | EC failed on catalog **build**; on-push still green | **You** — rebuild, wait EC clean, retry stage |
| Instant fail (&lt;1s), same `managed-*` run | Stale managed PipelineRun reuse | **You** — delete release, wait 5+ min, recreate |
| `BundleUnpackFailed` on cluster | Catalog references bundle digest not on stage | **You** — bundle stage first, rebuild catalog |
| EC failure on one OCP only, same commit passes others | OCP-specific FBC index / pruning check | **You** first (rebuild after bundle stage); releng if opaque |

Do **not** escalate to releng until: EC check reviewed on GitHub, rebuild attempted, stage retried with EC-clean snapshot.

## Known 1.8 rc7 lesson (418)

- Snapshot `…174507-000` (#506 bundle): on-push green, **EC failure** → stage catalog failed 4×.
- Snapshot `…214513-000` (#516 configs, post–bundle-stage): EC **neutral** → stage catalog **Released=True**, `iib:1155542`.
- 419–422 passed earlier with #506 snapshots because their EC was neutral, not because 418 was special-cased by releng.

## Known 5.0 EC lesson — fbc-target-index-pruning-check (Jun 2026)

All 4.18–4.21 EC checks showed `failure` (645 success, 15 warning, **5 failure**) while 4.22 was `neutral`.

**How to read the verify log:**
The 5 violations are all `test.no_failed_tests` with `Term: fbc-target-index-pruning-check`.  
This means the **build pipeline task** `fbc-target-index-pruning-check` itself failed; EC just surfaces the stored result.

**What the task checks:**  
It renders the live production OCP operator index (`registry.redhat.io/redhat/redhat-operator-index:vX.XX`) and verifies your FBC doesn't drop channels or entries already present there.

**Root causes found (applied together):**

1. **`filter_catalog.py` was clearing the entire catalog** (wrong approach). The correct 1.8-style is to **only remove the `olm.package` entry** and keep all `olm.channel` / `olm.bundle` entries — they must stay so the pruning check passes.

2. **Configs submodule was stale** — missing bundles recently added to the production index via "surgical pruning" PRs on `main` (`v1.5.5`, `v1.6.3` from PRs #523/#525/#527).

3. **A new z-stream was published to prod** (v1.7.1) but not yet in the `configs` submodule. The production OCP index gained `v1.7.1` in `release-1.7`; our FBC only had `v1.7.0` → pruning violation. Fix: bump configs submodule to a SHA that includes v1.7.1 (PR #530 branch `791fe08a`).

4.22 always passed because its base `catalog.json` is **empty** — nothing to prune.

**Fix pattern for future new release lines:**
```bash
# 1. Check what's missing in configs vs current main HEAD
#    Look for bundles present in main that are absent in pinned SHA
# 2. Check open MintMaker "Update catalogs for all OCP versions" PRs on main
#    Those PRs add newly published z-stream bundles
# 3. Bump configs submodule to the MintMaker PR branch SHA (don't wait for merge)
git -C configs fetch origin <PR_BRANCH_SHA>
git -C configs checkout <PR_BRANCH_SHA>
git add configs && git commit -m "fix: bump configs submodule to include vX.Y.Z for EC pruning check"
```

**Note:** 1.8 builds escape this because their `fbc-target-index-pruning-check` ran at build time (before the new z-stream was in the prod index). EC uses the stored result — so 1.8 EC stays neutral even after the prod index updates.

## TODO tomorrow (Jun 11 2026) — first full 5.0 stage test run

Run the default stage test for 5.0: **bundle stage + catalog stage**, both using the same date timestamp in the name (not `rc`).

```bash
DATE=$(date +%Y%m%d)   # e.g. 20260611

# 1. Bundle stage release
create-konflux-release.sh "$DATE" --stage --versions 5-0 --release bundle --release-type RHBA --epic <EPIC>

# 2. Catalog stage releases (script now auto-defaults to date when no tag given)
create-konflux-release.sh --stage --versions 5-0 --release catalog --release-type RHBA
# → names: stage-publish-catalog-4XX-glo-50-release-20260611
```

Or pass `$DATE` explicitly so bundle and catalog share the exact same suffix:
```bash
create-konflux-release.sh "$DATE" --stage --versions 5-0 --release catalog --release-type RHBA
```

**Before running:** confirm EC neutral on latest `release-5.0` push snapshots (commit `f072a7d` or newer).

---

## Post-1.8 GA TODO (review week of ~Jun 16 2026)

After 1.8 GA is shipped, review these catalog housekeeping items:

1. **Open MintMaker PRs** on `stolostron/multicluster-global-hub-operator-catalog` — check for
   pending nudge PRs that accumulated during the RC cycle and need merging or closing.
2. **`release-1.8` branch cleanup** — verify submodule pointer and any stale commits after GA prod release.
3. **5.0 catalog `glo-50-rc1` naming** — `stage-publish-catalog-4XX-glo-50-release-rc1` exists with the old
   naming from Jun 10. Prod will use the new scripts generating `glo-50-release-<date>` — confirm the naming
   convention is applied consistently once 5.0 prod release runs.
4. **`glo-180` naming fix is script-only** — the release scripts now generate `glo-50` correctly for 5.0, but
   double-check that the ReleasePlan names in Konflux also don't embed "180" anywhere confusing.

## GH 5.1 onboarding (when ACM 5.1 is planned)

Global Hub and ACM go in pairs — ACM 5.1 requires a **Global Hub 5.1** release line. Nothing exists yet in
Konflux or the catalog repo. When the time comes, the full onboarding checklist is:

1. **Main repo** — create `release-5.1` branch in `stolostron/multicluster-global-hub`; bump bundle version to `v1.9.0` (or whatever the next bundle version is).
2. **Catalog repo** — create `release-5.1` branch in `stolostron/multicluster-global-hub-operator-catalog`; copy and update Tekton pipelines from `release-5.0` (`.tekton/*-globalhub-5-1-*.yaml`), update CEL expressions, update `catalog-template-current.json` with new bundle ref.
3. **Konflux applications** — create `release-globalhub-5-1` and `release-catalog-4XX-globalhub-5-1` applications.
4. **Release Plans** — create `stage/prod-publish-globalhub-5-1` and `catalog-4XX-publish-stage/prod-globalhub-5-1` ReleasePlans (follow the 5.0 runbook in `pre-release/GH-5.0-konflux-release-plan-runbook.md`).
5. **Release scripts** — `create-konflux-release.sh` already handles `MAJOR≥5` correctly (OCP range 418–422, slug `glo-51`). No script changes needed.
6. **EC lesson** — before first stage release, ensure `configs` submodule on `release-5.1` is up to date with `main` HEAD (includes all published z-streams). MintMaker will handle ongoing updates but the initial branch may be stale.
7. **Bundle operator catalog** — check if `multicluster-global-hub-operator-bundle-globalhub-5-1` component needs onboarding in Konflux (separate from catalog).

---

## After catalog stage succeeds

```bash
oc get release stage-publish-catalog-418-glo-180-release-rc7 -n acm-multicluster-glo-tenant \
  -o jsonpath='{.status.artifacts.index_image.v4.18.index_image}{"\n"}'
```

Confirm all OCP variants `Released=True` before re-running GitLab/Jenkins stage pipeline.
