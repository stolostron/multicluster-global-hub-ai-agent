---
name: jenkins-e2e-polarion
description: Run Global Hub Jenkins e2e pipeline manually and upload results to Polarion. Use when resuming a failed globalhub-main pipeline, triggering regionalhub-import, triggering globalhub-e2e, or uploading e2e results to Polarion.
---

# Global Hub Jenkins E2E → Polarion Workflow

Use this skill when:
- globalhub-main pipeline failed mid-way (e.g. ACM version wrong, GH install failed) and you need to resume
- Running regionalhub-import + globalhub-e2e manually
- Uploading e2e results to Polarion

---

## Key Jenkins Jobs

| Job | Purpose |
|-----|---------|
| `globalhub-main` | Orchestrates: create clusters → install GH → import regional hub → e2e |
| `globalhub-create` | Creates the hub OCP cluster + installs GH operator |
| `regionalhub-create` | Creates the regional hub OCP cluster + installs ACM |
| `globalhub-operator-install` | Manual GH install fix (when globalhub-create's GH install fails) |
| `regionalhub-import` | Imports regional hub as ManagedCluster into GH |
| `globalhub-e2e` | Runs e2e tests (`TEST_TAGS=e2e`, `GIT_BRANCH=release-2.17`) |
| `CI-Jobs/push_results_to_polarion` | Uploads junit XML from a previous e2e build to Polarion |
| `CI-Jobs/push_results_to_report_portal` | Uploads results to Report Portal (optional, before Polarion) |

Jenkins URL: `https://jenkins-csb-rhacm-tests.dno.corp.redhat.com`

---

## Credentials

All credentials are in `.env`. Shell quote all URLs with `[...]` to avoid bash glob expansion:

```bash
source workflows/cve-service/config/.env
export JENKINS_URL="https://jenkins-csb-rhacm-tests.dno.corp.redhat.com"
export PIPELINE="prod-release"
```

**CRITICAL**: Always escape `[` and `]` in curl `?tree=` query params, or use `\[` / `\]`:
```bash
# WRONG — bash glob expands [name]
curl ... "${JBASE}/api/json?tree=jobs[name]"

# CORRECT
curl ... "${JBASE}/api/json?tree=jobs\[name\]"
```

---

## Finding Build Numbers After a Failed Pipeline

When `globalhub-main #NNN` fails mid-way, extract child build numbers from its console:

```bash
curl -sk -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
  "${JBASE}/job/globalhub-main/NNN/consoleText" \
  | grep -E "(globalhub-create|regionalhub-create) #[0-9]+"
# Output: Starting building: globalhub-create #767
#         Starting building: regionalhub-create #797
```

The hub cluster name is encoded in its console URL:
`apps.vbirsan--gh-767.dev09.red-chesterfield.com` → `globalhub-create #767`

---

## Fetching Cluster Credentials

```bash
GH_BUILD=767
RH_BUILD=797
JBASE="https://jenkins-csb-rhacm-tests.dno.corp.redhat.com"

curl -fsk -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
  "${JBASE}/job/globalhub-create/${GH_BUILD}/artifact/-gh-${GH_BUILD}/output.json" \
  -o /tmp/gh${GH_BUILD}-output.json

curl -fsk -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
  "${JBASE}/job/regionalhub-create/${RH_BUILD}/artifact/-rh-${RH_BUILD}/output.json" \
  -o /tmp/rh${RH_BUILD}-output.json

HUB_API=$(python3 -c "import json; print(json.load(open('/tmp/gh${GH_BUILD}-output.json'))['API_URL'])")
HUB_PASS=$(python3 -c "import json; print(json.load(open('/tmp/gh${GH_BUILD}-output.json'))['PASSWORD'])")
RH_API=$(python3 -c "import json; print(json.load(open('/tmp/rh${RH_BUILD}-output.json'))['API_URL'])")
RH_PASS=$(python3 -c "import json; print(json.load(open('/tmp/rh${RH_BUILD}-output.json'))['PASSWORD'])")
```

---

## Validate Hub Before Import

```bash
oc login "$HUB_API" -u kubeadmin -p "$HUB_PASS" --insecure-skip-tls-verify=true

# MGH must be Running
oc get mcgh -n multicluster-global-hub \
  -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,REASON:.status.conditions[-1].reason'

# All pods healthy
oc get pods -n multicluster-global-hub --no-headers | grep -v Completed

# No regional hub imported yet (no ManagedClusters except local-cluster)
oc get managedcluster | grep -v local-cluster
```

---

## Trigger regionalhub-import

```bash
REPO_ROOT="/path/to/chunlin-acm-global-hub-release"

/opt/homebrew/bin/bash "${REPO_ROOT}/lib/trigger-jenkins-build.sh" \
  -j job/regionalhub-import \
  "HUB_CLUSTER_USER=kubeadmin" \
  "HUB_CLUSTER_PASSWORD=${HUB_PASS}" \
  "HUB_CLUSTER_API_URL=${HUB_API}" \
  "MANAGED_CLUSTER_USER=kubeadmin" \
  "MANAGED_CLUSTER_PASSWORD=${RH_PASS}" \
  "MANAGED_CLUSTER_API_URL=${RH_API}" \
  "GIT_BRANCH=release-2.17"
```

---

## Trigger globalhub-e2e

```bash
/opt/homebrew/bin/bash "${REPO_ROOT}/lib/trigger-jenkins-build.sh" \
  -j job/globalhub-e2e \
  "HUB_CLUSTER_USER=kubeadmin" \
  "HUB_CLUSTER_PASSWORD=${HUB_PASS}" \
  "HUB_CLUSTER_API_URL=${HUB_API}" \
  "MANAGED_CLUSTER_USER=kubeadmin" \
  "MANAGED_CLUSTER_PASSWORD=${RH_PASS}" \
  "MANAGED_CLUSTER_API_URL=${RH_API}" \
  "TEST_TAGS=e2e" \
  "GIT_BRANCH=release-2.17"
```

The e2e job archives junit results at: `results/result-{BUILD_NUMBER}.xml`

---

## Upload E2E Results to Polarion

Use `CI-Jobs/push_results_to_polarion` — **not** the standalone `upload-report-to-polarion` job (that one requires a Report Portal launch ID).

The job reads the junit XML directly from the upstream job's archived artifacts.

```bash
E2E_BUILD=1717           # globalhub-e2e build number with the results
GH_VER_UNDERSCORED=1_8_0 # e.g. 1_8_0 for GH 1.8.0 (underscores, no dots)
OCP_COMPACT=421          # e.g. 421 for OCP 4.21

/opt/homebrew/bin/bash "${REPO_ROOT}/lib/trigger-jenkins-build.sh" \
  -j "job/CI-Jobs/job/push_results_to_polarion" \
  "COMPONENT=HOH" \
  "UPSTREAM_JOB=globalhub-e2e" \
  "UPSTREAM_JOB_BUILD_NUMBER=${E2E_BUILD}" \
  "CLOUD_PROVIDER=regionalhub-ACMlatest-${OCP_COMPACT}-globalhub" \
  "OCP_VERSION=4.21" \
  "ACM_IMAGE=latest-2.17" \
  "TEST_TAGS=e2e" \
  "POLARION_TEST_PLAN_ID=Global_Hub_1_8_0" \
  "COMPONENT_POLARION_TEST_RUN_ID=GlobalHub_${GH_VER_UNDERSCORED}_e2e_${E2E_BUILD}" \
  "POLARION_ENDPOINT=https://polarion.engineering.redhat.com/polarion" \
  "POLARION_PROJECT_ID=RHACM4K" \
  "POLARION_USER=acm_machine" \
  "POLARION_PASSWORD=polarion" \
  "TEST_TYPE=regression" \
  "GIT_BRANCH=main"
```

> **CRITICAL**: `CLOUD_PROVIDER` must NOT contain dots — use `regionalhub-ACMlatest-421-globalhub` not `regionalhub-ACMlatest-421-globalhub-v1.8`. Polarion rejects test run IDs with `.` characters.
>
> Always set `COMPONENT_POLARION_TEST_RUN_ID` explicitly to a dot-free string. If left empty, the script auto-generates an ID that includes the artifact filename (e.g. `result-1717.xml`) which contains an invalid `.` character.

### POLARION_TEST_PLAN_ID format

`Global_Hub_{MAJOR}_{MINOR}_{PATCH}` — e.g.:
- GH 1.8.0 → `Global_Hub_1_8_0`
- GH 1.7.1 → `Global_Hub_1_7_1`

### CLOUD_PROVIDER format (from pipeline history)

`regionalhub-ACMlatest-{OCP_COMPACT}-globalhub-v{GH_VERSION}`  
e.g. `regionalhub-ACMlatest-421-globalhub-v1.8` (OCP 4.21, GH 1.8.x)

---

## Poll a Jenkins Build Until Done

```bash
BUILD_URL="https://jenkins-csb-rhacm-tests.dno.corp.redhat.com/job/globalhub-e2e/1717"
elapsed=0
while true; do
  resp=$(curl -sk --max-time 10 -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    "${BUILD_URL}/api/json?tree=result,building" 2>/dev/null)
  result=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('result') or 'BUILDING')" 2>/dev/null)
  building=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('building'))" 2>/dev/null)
  echo "  [${elapsed}s] $result"
  [[ "$building" == "False" ]] && break
  sleep 60; elapsed=$((elapsed+60))
done
```

---

## GIT_BRANCH per GH version

| GH Version | GIT_BRANCH |
|-----------|------------|
| 1.8.x | `release-2.17` |
| 1.7.x | `release-2.16` |
| 1.6.x | `release-2.15` |

---

## Typical Resume Flow

1. Find `globalhub-create #NNN` and `regionalhub-create #NNN` from failed `globalhub-main` console
2. Fetch `output.json` from both → extract `API_URL` + `PASSWORD`
3. `oc login` hub → validate MGH phase = `Running`, all pods healthy
4. Trigger `regionalhub-import` → wait SUCCESS
5. Trigger `globalhub-e2e` with `TEST_TAGS=e2e` → wait result
6. Trigger `CI-Jobs/push_results_to_polarion` with the e2e build number → wait SUCCESS
