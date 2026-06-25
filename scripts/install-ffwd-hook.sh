#!/usr/bin/env bash
# Install ffwd pre-push railcheck into the current git repo's .git/hooks.
#
# Usage:
#   cd /path/to/stolostron/multicluster-global-hub
#   /path/to/multicluster-global-hub-ai-agent/scripts/install-ffwd-hook.sh
#
# Optional:
#   FFWD_POLICY_FILE=...  — path to repo_mapping.json (defaults to ai-agent copy)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK_SRC="${SCRIPT_DIR}/hooks/pre-push-ffwd"
CHECK_SRC="${SCRIPT_DIR}/check-ffwd-push.sh"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

GIT_DIR="$(git rev-parse --git-dir)"
HOOKS_DIR="${GIT_DIR}/hooks"
mkdir -p "$HOOKS_DIR"

# Copy check script into hooks dir so hook works even if ai-agent path moves
cp "$CHECK_SRC" "${HOOKS_DIR}/check-ffwd-push.sh"
chmod +x "${HOOKS_DIR}/check-ffwd-push.sh"

POLICY="${FFWD_POLICY_FILE:-${AI_AGENT_ROOT}/workflows/cve-service/config/repo_mapping.json}"
if [[ -f "$POLICY" ]]; then
  cp "$POLICY" "${HOOKS_DIR}/ffwd-policy.json"
  echo "Installed policy: ${HOOKS_DIR}/ffwd-policy.json"
fi

# Chain existing pre-push hook (e.g. multicluster-global-hub release checklist)
if [[ -f "${HOOKS_DIR}/pre-push" ]] && [[ ! -f "${HOOKS_DIR}/pre-push.next" ]]; then
  if ! grep -q 'pre-push-ffwd' "${HOOKS_DIR}/pre-push" 2>/dev/null; then
    mv "${HOOKS_DIR}/pre-push" "${HOOKS_DIR}/pre-push.next"
    echo "Chained existing pre-push → pre-push.next"
  fi
fi

cat > "${HOOKS_DIR}/pre-push" <<EOF
#!/usr/bin/env bash
# FFWD railcheck (installed by multicluster-global-hub-ai-agent/scripts/install-ffwd-hook.sh)
HOOKS="\$(dirname "\$0")"
export FFWD_POLICY_FILE="\${FFWD_POLICY_FILE:-\${HOOKS}/ffwd-policy.json}"
if ! "\${HOOKS}/check-ffwd-push.sh" --hook; then
  exit 1
fi
if [[ -x "\${HOOKS}/pre-push.next" ]]; then
  exec "\${HOOKS}/pre-push.next" "\$@"
fi
EOF
chmod +x "${HOOKS_DIR}/pre-push"

echo "✅ FFWD pre-push railcheck installed in ${HOOKS_DIR}"
echo "   Pushes to release-* on ffwd repos will be blocked unless using sync/merge branch or FFWD_ALLOW_DIRECT=1"
