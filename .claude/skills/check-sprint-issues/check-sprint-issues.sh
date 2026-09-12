#!/bin/bash
# Check Global Hub sprint issues for missing required fields and labels
# Usage: ./check-sprint-issues.sh or SPRINT=2 ./check-sprint-issues.sh

set -euo pipefail

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m'
CYAN='\033[0;36m' YELLOW='\033[1;33m' NC='\033[0m' BOLD='\033[1m'

# Jira config
JIRA_BASE_URL="${JIRA_BASE_URL:-https://redhat.atlassian.net}"
JIRA_TOKEN="${JIRA_TOKEN:-${JIRA_API_TOKEN:-}}"
JIRA_USER="${JIRA_USER:-}"

# Validate required env var
require_env() {
    [[ -z "${!1:-}" ]] && echo -e "${RED}Error: $1 is required${NC}" && return 1 || return 0
}

# Jira HTTP request - sets RESPONSE_BODY and RESPONSE_CODE
jira_request() {
    local method="$1" endpoint="$2" payload="${3:-}"
    local max_retries=5 retry_delay=5
    local args=(-s -w "\n%{http_code}" -X "$method"
        -u "${JIRA_USER}:${JIRA_TOKEN}"
        -H "Content-Type: application/json"
        "${JIRA_BASE_URL}${endpoint}")
    [[ -n "$payload" ]] && args+=(-d "$payload")

    for attempt in $(seq 1 $max_retries); do
        local resp
        resp=$(curl "${args[@]}" 2>&1)
        RESPONSE_CODE=$(echo "$resp" | tail -1)
        RESPONSE_BODY=$(echo "$resp" | sed '$d')

        if [ "$RESPONSE_CODE" != "429" ]; then
            return 0
        fi
        echo "  Rate limited (429), retrying in ${retry_delay}s (attempt ${attempt}/${max_retries})..." >&2
        sleep "$retry_delay"
        retry_delay=$((retry_delay * 2))
    done
}

# Calculate current sprint number
# GH Sprint 1 ends on 2026-04-01, each sprint is 3 weeks
calculate_sprint() {
    local sprint1_end="2026-04-01"
    local sprint1_end_ts
    local now_ts
    local three_weeks=$((21 * 24 * 60 * 60))

    # macOS date
    if date -j -f "%Y-%m-%d" "$sprint1_end" "+%s" &>/dev/null; then
        sprint1_end_ts=$(date -j -f "%Y-%m-%d" "$sprint1_end" "+%s")
    else
        # Linux date
        sprint1_end_ts=$(date -d "$sprint1_end" "+%s")
    fi
    now_ts=$(date "+%s")

    if [[ $now_ts -le $sprint1_end_ts ]]; then
        echo "1"
    else
        local diff=$((now_ts - sprint1_end_ts))
        local sprints_passed=$(( (diff / three_weeks) + 1 ))
        echo "$((sprints_passed + 1))"
    fi
}

require_env JIRA_TOKEN || exit 1
require_env JIRA_USER || exit 1

# Calculate or use provided sprint
SPRINT="${SPRINT:-$(calculate_sprint)}"
SPRINT_NAME="GH Sprint ${SPRINT}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Check Sprint Issues - ${SPRINT_NAME}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Query all Global Hub issues in the current sprint
# Sprint field format: "GH Sprint 1"
JQL="component = \"Global Hub\" AND Sprint = \"${SPRINT_NAME}\" ORDER BY key ASC"

echo -e "${YELLOW}Querying issues...${NC}"
echo -e "  JQL: ${JQL}"
echo ""

# Fetch issues with all required fields
# Custom fields for Red Hat Jira:
# - customfield_10028: Story Points
# - customfield_10464: Activity Type
FIELDS="key,summary,issuetype,status,priority,labels,versions,fixVersions,customfield_10028,customfield_10464,issuelinks"

jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "$JQL" | jq -sRr @uri)&fields=${FIELDS}&maxResults=200" || {
    echo -e "${RED}Failed to fetch issues${NC}"
    exit 1
}

if [[ "$RESPONSE_CODE" != "200" ]]; then
    echo -e "${RED}Failed to fetch issues (HTTP $RESPONSE_CODE):${NC}"
    echo "$RESPONSE_BODY" | jq . 2>/dev/null
    exit 1
fi

TOTAL=$(echo "$RESPONSE_BODY" | jq '.total')
echo -e "${GREEN}Found ${TOTAL} issues in ${SPRINT_NAME}${NC}"
echo ""

if [[ "$TOTAL" == "0" ]]; then
    echo -e "${YELLOW}No issues found in this sprint.${NC}"
    exit 0
fi

# Arrays to track issues with problems
declare -a MISSING_ACTIVITY_TYPE=()
declare -a MISSING_STORY_POINTS=()
declare -a MISSING_PRIORITY=()
declare -a MISSING_VERSIONS=()
declare -a MISSING_FIX_VERSIONS=()
declare -a MISSING_ENG_STATUS=()
declare -a MISSING_QE_LABEL=()
declare -a MISSING_QE_CONFIDENCE=()
declare -a MISSING_DOC_LABEL=()
declare -a MISSING_SPRINT_LABEL=()

# Process each issue
echo -e "${YELLOW}Checking issues for missing fields...${NC}"
echo ""

echo "$RESPONSE_BODY" | jq -c '.issues[]' | while read -r issue; do
    KEY=$(echo "$issue" | jq -r '.key')
    SUMMARY=$(echo "$issue" | jq -r '.fields.summary')
    ISSUE_TYPE=$(echo "$issue" | jq -r '.fields.issuetype.name')
    PRIORITY=$(echo "$issue" | jq -r '.fields.priority.name // empty')
    LABELS=$(echo "$issue" | jq -r '.fields.labels // []')
    VERSIONS=$(echo "$issue" | jq -r '.fields.versions // []')
    FIX_VERSIONS=$(echo "$issue" | jq -r '.fields.fixVersions // []')
    STORY_POINTS=$(echo "$issue" | jq -r '.fields.customfield_10028 // empty')
    ACTIVITY_TYPE=$(echo "$issue" | jq -r '.fields.customfield_10464.value // empty')

    PROBLEMS=()

    # Check if this is a CVE issue
    IS_CVE=false
    if [[ "$SUMMARY" == *"CVE"* ]]; then
        IS_CVE=true
    fi

    # Check required fields for all issues
    if [[ -z "$ACTIVITY_TYPE" ]]; then
        PROBLEMS+=("Activity Type")
    fi

    # Check Story Points (skip for CVE issues and non-QE tasks)
    SHOULD_CHECK_STORY_POINTS=true
    if [[ "$IS_CVE" == "true" ]]; then
        SHOULD_CHECK_STORY_POINTS=false
    elif [[ "$ISSUE_TYPE" == "Task" || "$ISSUE_TYPE" == "任务" || "$ISSUE_TYPE" == "Sub-task" || "$ISSUE_TYPE" == "子任务" ]]; then
        # Only check story points for QE tasks (title contains [QE])
        if [[ "$SUMMARY" != *"[QE"* ]]; then
            SHOULD_CHECK_STORY_POINTS=false
        fi
    fi

    if [[ "$SHOULD_CHECK_STORY_POINTS" == "true" && -z "$STORY_POINTS" ]]; then
        PROBLEMS+=("Story Points")
    fi

    if [[ -z "$PRIORITY" || "$PRIORITY" == "null" ]]; then
        PROBLEMS+=("Priority")
    fi

    VERSIONS_COUNT=$(echo "$VERSIONS" | jq 'length')
    if [[ "$VERSIONS_COUNT" == "0" ]]; then
        PROBLEMS+=("Affect Version")
    fi

    # Check Fix Version (skip for CVE issues)
    FIX_VERSIONS_COUNT=$(echo "$FIX_VERSIONS" | jq 'length')
    if [[ "$FIX_VERSIONS_COUNT" == "0" && "$IS_CVE" == "false" ]]; then
        PROBLEMS+=("Fix Version")
    fi

    # Check labels for Stories only
    if [[ "$ISSUE_TYPE" == "Story" ]]; then
        # Check Eng-Status:Green
        HAS_ENG_STATUS=$(echo "$LABELS" | jq 'any(startswith("Eng-Status:"))')
        if [[ "$HAS_ENG_STATUS" != "true" ]]; then
            PROBLEMS+=("Eng-Status label")
        fi

        # Check QE labels (case-insensitive)
        HAS_QE_REQUIRED=$(echo "$LABELS" | jq 'any(test("^QE-Required$"; "i"))')
        HAS_QE_NA=$(echo "$LABELS" | jq 'any(test("^QE-NotApplicable$"; "i"))')
        if [[ "$HAS_QE_REQUIRED" != "true" && "$HAS_QE_NA" != "true" ]]; then
            PROBLEMS+=("QE label (QE-Required or QE-NotApplicable)")
        fi

        # Check QE-Confidence if QE-Required
        if [[ "$HAS_QE_REQUIRED" == "true" ]]; then
            HAS_QE_CONFIDENCE=$(echo "$LABELS" | jq 'any(startswith("QE-Confidence:"))')
            if [[ "$HAS_QE_CONFIDENCE" != "true" ]]; then
                PROBLEMS+=("QE-Confidence label")
            fi

            # If QE-Required, check for linked QE task
            ISSUE_LINKS=$(echo "$issue" | jq -r '.fields.issuelinks // []')
            # Look for linked issues with [QE] in summary or via Test relationship
            QE_TASK_KEYS=$(echo "$ISSUE_LINKS" | jq -r '[.[] |
                select(
                    (.inwardIssue.fields.summary // "" | test("\\[QE\\]"; "i")) or
                    (.outwardIssue.fields.summary // "" | test("\\[QE\\]"; "i")) or
                    (.type.name == "Test")
                ) |
                (.inwardIssue.key // .outwardIssue.key)
            ] | unique | .[]')

            if [[ -z "$QE_TASK_KEYS" ]]; then
                PROBLEMS+=("QE Task (QE-Required but no [QE] task linked)")
            else
                # Check if QE tasks are in the same sprint
                for QE_TASK_KEY in $QE_TASK_KEYS; do
                    # Fetch QE task sprint info
                    QE_RESP=$(curl -s -w "\n%{http_code}" -X GET \
                        -u "${JIRA_USER}:${JIRA_TOKEN}" \
                        -H "Content-Type: application/json" \
                        "${JIRA_BASE_URL}/rest/api/3/issue/${QE_TASK_KEY}?fields=customfield_10020")
                    QE_CODE=$(echo "$QE_RESP" | tail -1)
                    QE_BODY=$(echo "$QE_RESP" | sed '$d')

                    if [[ "$QE_CODE" == "200" ]]; then
                        QE_SPRINT=$(echo "$QE_BODY" | jq -r '.fields.customfield_10020 // [] | .[0].name // empty')
                        if [[ -z "$QE_SPRINT" ]]; then
                            PROBLEMS+=("QE Task ${QE_TASK_KEY} not in any sprint")
                        elif [[ "$QE_SPRINT" != "$SPRINT_NAME" ]]; then
                            PROBLEMS+=("QE Task ${QE_TASK_KEY} in wrong sprint: ${QE_SPRINT}")
                        fi
                    fi
                done
            fi
        fi

        # Check doc labels
        HAS_DOC_REQUIRED=$(echo "$LABELS" | jq 'any(. == "doc-required")')
        HAS_DOC_NOT=$(echo "$LABELS" | jq 'any(. == "doc-not-required")')
        if [[ "$HAS_DOC_REQUIRED" != "true" && "$HAS_DOC_NOT" != "true" ]]; then
            PROBLEMS+=("doc label (doc-required or doc-not-required)")
        fi

        # If doc-required, check for linked doc task
        if [[ "$HAS_DOC_REQUIRED" == "true" ]]; then
            ISSUE_LINKS=$(echo "$issue" | jq -r '.fields.issuelinks // []')
            # Look for linked issues with [Doc] in summary
            HAS_DOC_TASK=$(echo "$ISSUE_LINKS" | jq '[.[] |
                select(
                    (.inwardIssue.fields.summary // "" | test("\\[Doc\\]"; "i")) or
                    (.outwardIssue.fields.summary // "" | test("\\[Doc\\]"; "i"))
                )
            ] | length > 0')
            if [[ "$HAS_DOC_TASK" != "true" ]]; then
                PROBLEMS+=("Doc Task (doc-required but no [Doc] task linked)")
            fi
        fi

        # Check Sprint label
        HAS_SPRINT=$(echo "$LABELS" | jq 'any(startswith("Sprint"))')
        if [[ "$HAS_SPRINT" != "true" ]]; then
            PROBLEMS+=("Sprint label")
        fi
    fi

    # Output if there are problems
    if [[ ${#PROBLEMS[@]} -gt 0 ]]; then
        echo -e "${RED}${KEY}${NC}: ${SUMMARY:0:60}..."
        echo -e "  Type: ${ISSUE_TYPE}"
        echo -e "  ${YELLOW}Missing:${NC} ${PROBLEMS[*]}"
        echo -e "  Link: ${JIRA_BASE_URL}/browse/${KEY}"
        echo ""
    fi
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Sprint: ${SPRINT_NAME}"
echo -e "Total Issues: ${TOTAL}"
echo ""
echo -e "${CYAN}Tip:${NC} Use the update-jira-story skill to fix issues:"
echo -e "  /update-jira-story ACM-XXXXX"
echo ""
