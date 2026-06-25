#!/usr/bin/env bash
# Railcheck: block direct pushes to release-* when repo uses main → release ffwd.
#
# Usage (agent / manual):
#   scripts/check-ffwd-push.sh --repo stolostron/multicluster-global-hub --branch release-5.0
#   scripts/check-ffwd-push.sh --repo stolostron/multicluster-global-hub --ref refs/heads/release-5.0
#
# Usage (git pre-push hook — reads refs from stdin):
#   scripts/check-ffwd-push.sh --hook
#
# Escape hatch (human override only):
#   FFWD_ALLOW_DIRECT=1 git push ...
#
# Policy file (optional override):
#   FFWD_POLICY_FILE=/path/to/repo_mapping.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/ffwd-policy.json" ]]; then
  DEFAULT_POLICY="${SCRIPT_DIR}/ffwd-policy.json"
elif [[ -f "${SCRIPT_DIR}/../workflows/cve-service/config/repo_mapping.json" ]]; then
  DEFAULT_POLICY="${SCRIPT_DIR}/../workflows/cve-service/config/repo_mapping.json"
else
  DEFAULT_POLICY=""
fi
POLICY_FILE="${FFWD_POLICY_FILE:-$DEFAULT_POLICY}"

usage() {
  cat <<'EOF'
Usage:
  check-ffwd-push.sh --repo OWNER/REPO --branch BRANCH
  check-ffwd-push.sh --repo OWNER/REPO --ref refs/heads/BRANCH
  check-ffwd-push.sh --hook

Exit 0 = push allowed. Exit 1 = blocked (ffwd repo, direct release push).
EOF
}

branch_from_ref() {
  local ref="$1"
  ref="${ref#refs/heads/}"
  ref="${ref#refs/tags/}"
  printf '%s' "$ref"
}

is_release_branch() {
  [[ "$1" =~ ^release- ]]
}

is_allowed_sync_branch() {
  # Merge/sync PR branches targeting release-* are OK
  [[ "$1" =~ ^(sync/|merge/|chore/sync-|fix/sync-) ]]
}

ffwd_enabled_for_repo() {
  local repo="$1"
  if [[ ! -f "$POLICY_FILE" ]]; then
    case "$repo" in
      stolostron/multicluster-global-hub|stolostron/postgres_exporter)
        return 0
        ;;
    esac
    return 1
  fi
  python3 - "$repo" "$POLICY_FILE" <<'PY'
import json, sys
repo, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
policy = data.get("repo_branch_policy", {}).get(repo, {})
sys.exit(0 if policy.get("ffwd_from_main") else 1)
PY
}

dev_branch_for_repo() {
  local repo="$1"
  if [[ ! -f "$POLICY_FILE" ]]; then
    echo "main"
    return
  fi
  python3 - "$repo" "$POLICY_FILE" <<'PY'
import json, sys
repo, path = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
policy = data.get("repo_branch_policy", {}).get(repo, {})
print(policy.get("dev_branch", "main"))
PY
}

detect_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    echo ""
    return
  fi
  if [[ "$url" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    echo "${BASH_REMATCH[1]%.git}"
  elif [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
  fi
}

check_push() {
  local repo="$1"
  local branch="$2"
  local local_branch="${3:-}"

  if ! is_release_branch "$branch"; then
    return 0
  fi

  if ! ffwd_enabled_for_repo "$repo"; then
    return 0
  fi

  if [[ "${FFWD_ALLOW_DIRECT:-}" == "1" ]]; then
    echo "⚠️  FFWD_ALLOW_DIRECT=1 — allowing direct push to ${branch} (override)."
    return 0
  fi

  if [[ -n "$local_branch" ]] && is_allowed_sync_branch "$local_branch"; then
    return 0
  fi

  local dev
  dev="$(dev_branch_for_repo "$repo")"
  cat <<EOF
🚫 FFWD railcheck blocked push to ${repo}:${branch}

This repo uses ${dev} → release-* fast-forward (OpenShift CI post-submit).
Do NOT push new commits directly to release branches.

Instead:
  1. Open a PR targeting ${dev} with your changes
  2. After merge, CI fast-forwards ${branch}
  3. If ffwd is already broken, open a merge PR: ${dev} → ${branch}
     (example: https://github.com/${repo}/compare/${dev}...${branch})

Release-only exceptions (CPE labels, etc.) still go via PR to ${branch}, not direct push.

To override intentionally: FFWD_ALLOW_DIRECT=1 git push ...
EOF
  return 1
}

HOOK_MODE=0
REPO=""
BRANCH=""
REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook) HOOK_MODE=1; shift ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$HOOK_MODE" == "1" ]]; then
  REPO="${REPO:-$(detect_repo)}"
  if [[ -z "$REPO" ]]; then
    exit 0
  fi
  local_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  failed=0
  while read -r _local_ref _local_sha remote_ref _remote_sha; do
    [[ -z "${remote_ref:-}" ]] && continue
    branch="$(branch_from_ref "$remote_ref")"
    if ! check_push "$REPO" "$branch" "$local_branch"; then
      failed=1
    fi
  done
  exit "$failed"
fi

if [[ -z "$REPO" ]]; then
  echo "error: --repo required (or use --hook from a git repo)" >&2
  exit 2
fi

if [[ -n "$REF" ]]; then
  BRANCH="$(branch_from_ref "$REF")"
fi

if [[ -z "$BRANCH" ]]; then
  echo "error: --branch or --ref required" >&2
  exit 2
fi

local_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
check_push "$REPO" "$BRANCH" "$local_branch"
