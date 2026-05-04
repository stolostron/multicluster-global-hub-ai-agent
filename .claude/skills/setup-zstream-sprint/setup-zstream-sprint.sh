#!/usr/bin/env bash
# Setup Z-Stream sprint by finding epics, adding work items, and assigning to team members
# Usage: ./setup-zstream-sprint.sh or SPRINT=2 ./setup-zstream-sprint.sh
# Requires bash 4.0+ for associative arrays

set -euo pipefail

# Check bash version
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: This script requires bash 4.0 or higher"
    echo "Current version: $BASH_VERSION"
    echo ""
    echo "On macOS, install bash via Homebrew:"
    echo "  brew install bash"
    echo ""
    echo "Then run with:"
    echo "  /opt/homebrew/bin/bash $0"
    exit 1
fi

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m'
CYAN='\033[0;36m' YELLOW='\033[1;33m' NC='\033[0m' BOLD='\033[1m'

# Jira config
JIRA_BASE_URL="${JIRA_BASE_URL:-https://redhat.atlassian.net}"
JIRA_TOKEN="${JIRA_TOKEN:-${JIRA_API_TOKEN:-}}"
JIRA_USER="${JIRA_USER:-}"

# Config
QE_ASSIGNEE="${QE_ASSIGNEE:-Yaheng Liu}"
DEV_ASSIGNEE="${DEV_ASSIGNEE:-ChunLin Yang}"
QE_STORY_POINTS="${QE_STORY_POINTS:-1}"
DRY_RUN="${DRY_RUN:-false}"

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

# Find user account ID
find_user_id() {
    local user_name="$1"
    jira_request "GET" "/rest/api/3/user/search?query=$(echo "$user_name" | jq -sRr @uri)" || {
        echo -e "${RED}Failed to search for user: $user_name${NC}" >&2
        return 1
    }

    if [[ "$RESPONSE_CODE" != "200" ]]; then
        echo -e "${RED}Failed to find user: $user_name (HTTP $RESPONSE_CODE)${NC}" >&2
        return 1
    fi

    local user_id=$(echo "$RESPONSE_BODY" | jq -r '.[0].accountId // empty')
    if [[ -z "$user_id" ]]; then
        echo -e "${RED}User not found: $user_name${NC}" >&2
        return 1
    fi

    echo "$user_id"
}

# Get sprint ID
get_sprint_id() {
    local sprint_name="$1"

    # Try to get sprint info from an existing issue
    jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "component = \"Global Hub\" AND Sprint = \"${sprint_name}\"" | jq -sRr @uri)&fields=customfield_10020&maxResults=1" || {
        echo -e "${RED}Failed to query sprint${NC}" >&2
        return 1
    }

    if [[ "$RESPONSE_CODE" == "200" ]]; then
        local sprint_id=$(echo "$RESPONSE_BODY" | jq -r '.issues[0].fields.customfield_10020[0].id // empty')

        if [[ -n "$sprint_id" ]]; then
            echo "$sprint_id"
            return 0
        fi
    fi

    # Try to find board and sprint
    jira_request "GET" "/rest/agile/1.0/board?name=Global%20Hub" || {
        echo -e "${RED}Failed to find board${NC}" >&2
        return 1
    }

    local board_id=$(echo "$RESPONSE_BODY" | jq -r '.values[0].id // empty')
    if [[ -z "$board_id" ]]; then
        echo -e "${RED}Global Hub board not found${NC}" >&2
        return 1
    fi

    jira_request "GET" "/rest/agile/1.0/board/${board_id}/sprint?state=active,future" || {
        echo -e "${RED}Failed to query sprints${NC}" >&2
        return 1
    }

    local sprint_id=$(echo "$RESPONSE_BODY" | jq -r --arg name "$sprint_name" '.values[] | select(.name == $name) | .id')
    if [[ -z "$sprint_id" ]]; then
        echo -e "${RED}Sprint not found: $sprint_name${NC}" >&2
        echo -e "${YELLOW}Available sprints:${NC}" >&2
        echo "$RESPONSE_BODY" | jq -r '.values[] | "  - \(.name) (ID: \(.id), State: \(.state))"' >&2
        return 1
    fi

    echo "$sprint_id"
}

require_env JIRA_TOKEN || exit 1
require_env JIRA_USER || exit 1

# Calculate or use provided sprint
SPRINT="${SPRINT:-$(calculate_sprint)}"
SPRINT_NAME="GH Sprint ${SPRINT}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Setup Z-Stream Sprint - ${SPRINT_NAME}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}⚠️  DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

# Step 1: Find all Z-Stream epics
echo -e "${YELLOW}Step 1: Finding Z-Stream epics...${NC}"
JQL='issuetype = Epic AND summary ~ "Global Hub" AND summary ~ "Z-Stream" AND status in (New, "In Progress")'

jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "$JQL" | jq -sRr @uri)&fields=key,summary,status,fixVersions&maxResults=100" || {
    echo -e "${RED}Failed to fetch epics${NC}"
    exit 1
}

if [[ "$RESPONSE_CODE" != "200" ]]; then
    echo -e "${RED}Failed to fetch epics (HTTP $RESPONSE_CODE)${NC}"
    exit 1
fi

EPICS=$(echo "$RESPONSE_BODY" | jq -c '.issues[]')
EPIC_COUNT=$(echo "$RESPONSE_BODY" | jq -r '.issues | length')

if [[ "$EPIC_COUNT" == "0" || -z "$EPIC_COUNT" ]]; then
    echo -e "${YELLOW}No active Z-Stream epics found${NC}"
    exit 0
fi

echo -e "${GREEN}Found $EPIC_COUNT Z-Stream epics${NC}"
echo ""

# Extract epic keys and store fix versions
QE_EPIC_KEYS=()
RELEASE_EPIC_KEYS=()
declare -A EPIC_FIX_VERSIONS  # Associative array to store epic fix versions as JSON

while IFS= read -r epic; do
    [[ -z "$epic" ]] && continue

    KEY=$(echo "$epic" | jq -r '.key // empty')
    SUMMARY=$(echo "$epic" | jq -r '.fields.summary // empty')
    STATUS=$(echo "$epic" | jq -r '.fields.status.name // empty')
    FIX_VERSIONS=$(echo "$epic" | jq -c '.fields.fixVersions // []')

    if [[ -z "$KEY" || -z "$SUMMARY" ]]; then
        echo -e "${YELLOW}  Warning: Skipping epic with missing data${NC}"
        continue
    fi

    # Store fix versions for this epic
    EPIC_FIX_VERSIONS["$KEY"]="$FIX_VERSIONS"

    VERSION_COUNT=$(echo "$FIX_VERSIONS" | jq 'length')
    VERSION_NAMES=$(echo "$FIX_VERSIONS" | jq -r '.[].name' | paste -sd ',' -)

    if [[ "$VERSION_COUNT" -gt 0 ]]; then
        echo "  [$STATUS] $KEY - $SUMMARY (Fix Versions: $VERSION_NAMES)"
    else
        echo "  [$STATUS] $KEY - $SUMMARY (No fix versions)"
    fi

    if [[ "$SUMMARY" == *"QE Epic"* ]]; then
        QE_EPIC_KEYS+=("$KEY")
    else
        RELEASE_EPIC_KEYS+=("$KEY")
    fi
done <<< "$EPICS"

# Validate we have at least one valid epic
if [[ ${#QE_EPIC_KEYS[@]} -eq 0 && ${#RELEASE_EPIC_KEYS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No valid Z-Stream epics found${NC}"
    exit 0
fi

echo ""

# Step 2: Get all child work items
echo -e "${YELLOW}Step 2: Finding child work items...${NC}"

ALL_EPIC_KEYS=("${QE_EPIC_KEYS[@]+"${QE_EPIC_KEYS[@]}"}" "${RELEASE_EPIC_KEYS[@]+"${RELEASE_EPIC_KEYS[@]}"}")

if [[ ${#ALL_EPIC_KEYS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No epic keys to query${NC}"
    exit 0
fi

EPIC_LIST=$(IFS=,; echo "${ALL_EPIC_KEYS[*]}")

JQL="parent in ($EPIC_LIST) AND issuetype in (Story,Task)"

jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "$JQL" | jq -sRr @uri)&fields=key,summary,issuetype,status,parent,assignee&maxResults=200" || {
    echo -e "${RED}Failed to fetch child items${NC}"
    exit 1
}

if [[ "$RESPONSE_CODE" != "200" ]]; then
    echo -e "${RED}Failed to fetch child items (HTTP $RESPONSE_CODE)${NC}"
    exit 1
fi

CHILD_ITEMS=$(echo "$RESPONSE_BODY" | jq -c '.issues[]')
CHILD_COUNT=$(echo "$CHILD_ITEMS" | wc -l | tr -d ' ')

echo -e "${GREEN}Found $CHILD_COUNT child work items${NC}"
echo ""

# Categorize work items and track which need version updates
QE_TASK_KEYS=()
DEV_STORY_KEYS=()
UNASSIGNED_STORY_KEYS=()
declare -A STORY_PARENT_EPIC  # Map story key to parent epic key
declare -A TASK_PARENT_EPIC   # Map task key to parent epic key

while IFS= read -r item; do
    KEY=$(echo "$item" | jq -r '.key')
    TYPE=$(echo "$item" | jq -r '.fields.issuetype.name')
    PARENT=$(echo "$item" | jq -r '.fields.parent.key')
    ASSIGNEE=$(echo "$item" | jq -r '.fields.assignee.displayName // "Unassigned"')

    # Check if parent is a QE epic
    if [[ " ${QE_EPIC_KEYS[@]+"${QE_EPIC_KEYS[@]}"} " =~ " ${PARENT} " ]]; then
        if [[ "$TYPE" == "Task" || "$TYPE" == "任务" ]]; then
            QE_TASK_KEYS+=("$KEY")
            TASK_PARENT_EPIC["$KEY"]="$PARENT"  # Store parent epic for version sync
        fi
    elif [[ " ${RELEASE_EPIC_KEYS[@]+"${RELEASE_EPIC_KEYS[@]}"} " =~ " ${PARENT} " ]]; then
        if [[ "$TYPE" == "Story" ]]; then
            DEV_STORY_KEYS+=("$KEY")
            STORY_PARENT_EPIC["$KEY"]="$PARENT"  # Store parent epic for version sync
            if [[ "$ASSIGNEE" == "Unassigned" ]]; then
                UNASSIGNED_STORY_KEYS+=("$KEY")
            fi
        fi
    fi
done <<< "$CHILD_ITEMS"

echo "  QE Tasks: ${#QE_TASK_KEYS[@]}"
echo "  Dev Stories: ${#DEV_STORY_KEYS[@]} (${#UNASSIGNED_STORY_KEYS[@]} unassigned)"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN: Would add ${CHILD_COUNT} items to ${SPRINT_NAME}${NC}"
    echo -e "${YELLOW}DRY RUN: Would assign ${#QE_EPIC_KEYS[@]} QE epics to ${QE_ASSIGNEE}${NC}"
    echo -e "${YELLOW}DRY RUN: Would assign ${#QE_TASK_KEYS[@]} QE tasks to ${QE_ASSIGNEE}${NC}"
    echo -e "${YELLOW}DRY RUN: Would assign ${#UNASSIGNED_STORY_KEYS[@]} dev stories to ${DEV_ASSIGNEE}${NC}"
    echo -e "${YELLOW}DRY RUN: Would sync versions for ${#DEV_STORY_KEYS[@]} dev stories from their parent epics${NC}"
    exit 0
fi

# Get sprint ID
echo -e "${YELLOW}Step 3: Getting sprint ID...${NC}"
SPRINT_ID=$(get_sprint_id "$SPRINT_NAME")
echo -e "${GREEN}Sprint ID: $SPRINT_ID${NC}"
echo ""

# Get user IDs
echo -e "${YELLOW}Step 4: Finding user accounts...${NC}"
QE_USER_ID=$(find_user_id "$QE_ASSIGNEE")
echo -e "${GREEN}QE Assignee: $QE_ASSIGNEE (ID: $QE_USER_ID)${NC}"

DEV_USER_ID=$(find_user_id "$DEV_ASSIGNEE")
echo -e "${GREEN}Dev Assignee: $DEV_ASSIGNEE (ID: $DEV_USER_ID)${NC}"
echo ""

# Step 5: Add all items to sprint
echo -e "${YELLOW}Step 5: Adding work items to sprint...${NC}"

ALL_ITEM_KEYS=()
while IFS= read -r item; do
    KEY=$(echo "$item" | jq -r '.key')
    ALL_ITEM_KEYS+=("$KEY")
done <<< "$CHILD_ITEMS"

SPRINT_SUCCESS=0
SPRINT_SKIP=0
SPRINT_FAIL=0

for KEY in "${ALL_ITEM_KEYS[@]+"${ALL_ITEM_KEYS[@]}"}"; do
    # Check current sprint
    jira_request "GET" "/rest/api/3/issue/${KEY}?fields=customfield_10020" || continue

    if [[ "$RESPONSE_CODE" == "200" ]]; then
        CURRENT_SPRINT=$(echo "$RESPONSE_BODY" | jq -r '.fields.customfield_10020[0].name // empty')

        if [[ "$CURRENT_SPRINT" == "$SPRINT_NAME" ]]; then
            SPRINT_SKIP=$((SPRINT_SKIP + 1))
            continue
        fi
    fi

    # Add to sprint
    jira_request "POST" "/rest/agile/1.0/sprint/${SPRINT_ID}/issue" "{\"issues\": [\"${KEY}\"]}" || {
        SPRINT_FAIL=$((SPRINT_FAIL + 1))
        continue
    }

    if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
        SPRINT_SUCCESS=$((SPRINT_SUCCESS + 1))
    else
        SPRINT_FAIL=$((SPRINT_FAIL + 1))
    fi

    sleep 0.3
done

echo -e "${GREEN}  ✅ Added: $SPRINT_SUCCESS${NC}"
echo -e "${CYAN}  ℹ️  Already in sprint: $SPRINT_SKIP${NC}"
[[ $SPRINT_FAIL -gt 0 ]] && echo -e "${RED}  ❌ Failed: $SPRINT_FAIL${NC}"
echo ""

# Step 6: Assign QE epics
echo -e "${YELLOW}Step 6: Assigning QE epics to ${QE_ASSIGNEE}...${NC}"

QE_EPIC_SUCCESS=0
QE_EPIC_FAIL=0

for KEY in "${QE_EPIC_KEYS[@]+"${QE_EPIC_KEYS[@]}"}"; do
    jira_request "PUT" "/rest/api/3/issue/${KEY}/assignee" "{\"accountId\": \"${QE_USER_ID}\"}" || {
        QE_EPIC_FAIL=$((QE_EPIC_FAIL + 1))
        continue
    }

    if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
        QE_EPIC_SUCCESS=$((QE_EPIC_SUCCESS + 1))
    else
        QE_EPIC_FAIL=$((QE_EPIC_FAIL + 1))
    fi

    sleep 0.3
done

echo -e "${GREEN}  ✅ Assigned: $QE_EPIC_SUCCESS${NC}"
[[ $QE_EPIC_FAIL -gt 0 ]] && echo -e "${RED}  ❌ Failed: $QE_EPIC_FAIL${NC}"
echo ""

# Step 7: Assign QE tasks, set story points, and sync versions
echo -e "${YELLOW}Step 7: Assigning QE tasks, setting story points, and syncing versions...${NC}"

QE_TASK_ASSIGN_SUCCESS=0
QE_TASK_POINTS_SUCCESS=0
QE_TASK_VERSION_SUCCESS=0
QE_TASK_VERSION_SKIP=0
QE_TASK_FAIL=0

for KEY in "${QE_TASK_KEYS[@]+"${QE_TASK_KEYS[@]}"}"; do
    PARENT_EPIC="${TASK_PARENT_EPIC[$KEY]}"

    # Assign task
    jira_request "PUT" "/rest/api/3/issue/${KEY}/assignee" "{\"accountId\": \"${QE_USER_ID}\"}" || {
        QE_TASK_FAIL=$((QE_TASK_FAIL + 1))
        continue
    }

    if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
        QE_TASK_ASSIGN_SUCCESS=$((QE_TASK_ASSIGN_SUCCESS + 1))
    else
        QE_TASK_FAIL=$((QE_TASK_FAIL + 1))
        continue
    fi

    # Get epic fix versions
    EPIC_FIX_VERSIONS_JSON="${EPIC_FIX_VERSIONS[$PARENT_EPIC]}"

    # Set story points and versions in one request
    if [[ -n "$EPIC_FIX_VERSIONS_JSON" && "$EPIC_FIX_VERSIONS_JSON" != "[]" ]]; then
        # Include story points, affect versions, and fix versions (both set to epic's fix version)
        UPDATE_PAYLOAD=$(jq -n \
            --argjson fixVersions "$EPIC_FIX_VERSIONS_JSON" \
            --argjson points "$QE_STORY_POINTS" \
            '{fields: {customfield_10028: $points, versions: $fixVersions, fixVersions: $fixVersions}}')

        jira_request "PUT" "/rest/api/3/issue/${KEY}" "$UPDATE_PAYLOAD" || {
            continue
        }

        if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
            QE_TASK_POINTS_SUCCESS=$((QE_TASK_POINTS_SUCCESS + 1))
            QE_TASK_VERSION_SUCCESS=$((QE_TASK_VERSION_SUCCESS + 1))
        fi
    else
        # Only set story points, no versions
        jira_request "PUT" "/rest/api/3/issue/${KEY}" "{\"fields\": {\"customfield_10028\": ${QE_STORY_POINTS}}}" || {
            continue
        }

        if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
            QE_TASK_POINTS_SUCCESS=$((QE_TASK_POINTS_SUCCESS + 1))
            QE_TASK_VERSION_SKIP=$((QE_TASK_VERSION_SKIP + 1))
        fi
    fi

    sleep 0.3
done

echo -e "${GREEN}  ✅ Assigned: $QE_TASK_ASSIGN_SUCCESS${NC}"
echo -e "${GREEN}  ✅ Story points set: $QE_TASK_POINTS_SUCCESS${NC}"
echo -e "${GREEN}  ✅ Versions synced: $QE_TASK_VERSION_SUCCESS${NC}"
[[ $QE_TASK_VERSION_SKIP -gt 0 ]] && echo -e "${CYAN}  ℹ️  Versions skipped (no epic versions): $QE_TASK_VERSION_SKIP${NC}"
[[ $QE_TASK_FAIL -gt 0 ]] && echo -e "${RED}  ❌ Failed: $QE_TASK_FAIL${NC}"
echo ""

# Step 8: Assign unassigned dev stories
echo -e "${YELLOW}Step 8: Assigning dev stories to ${DEV_ASSIGNEE}...${NC}"

DEV_STORY_SUCCESS=0
DEV_STORY_FAIL=0

for KEY in "${UNASSIGNED_STORY_KEYS[@]+"${UNASSIGNED_STORY_KEYS[@]}"}"; do
    jira_request "PUT" "/rest/api/3/issue/${KEY}/assignee" "{\"accountId\": \"${DEV_USER_ID}\"}" || {
        DEV_STORY_FAIL=$((DEV_STORY_FAIL + 1))
        continue
    }

    if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
        DEV_STORY_SUCCESS=$((DEV_STORY_SUCCESS + 1))
    else
        DEV_STORY_FAIL=$((DEV_STORY_FAIL + 1))
    fi

    sleep 0.3
done

echo -e "${GREEN}  ✅ Assigned: $DEV_STORY_SUCCESS${NC}"
[[ $DEV_STORY_FAIL -gt 0 ]] && echo -e "${RED}  ❌ Failed: $DEV_STORY_FAIL${NC}"
echo ""

# Step 9: Sync versions from parent epics to stories
echo -e "${YELLOW}Step 9: Syncing versions from parent epics to stories...${NC}"

VERSION_SUCCESS=0
VERSION_SKIP=0
VERSION_FAIL=0

for STORY_KEY in "${DEV_STORY_KEYS[@]+"${DEV_STORY_KEYS[@]}"}"; do
    PARENT_EPIC="${STORY_PARENT_EPIC[$STORY_KEY]}"

    # Get epic fix versions
    EPIC_FIX_VERSIONS_JSON="${EPIC_FIX_VERSIONS[$PARENT_EPIC]}"

    if [[ -z "$EPIC_FIX_VERSIONS_JSON" || "$EPIC_FIX_VERSIONS_JSON" == "[]" ]]; then
        VERSION_SKIP=$((VERSION_SKIP + 1))
        continue
    fi

    # Update story with both affect version (versions) and fix version (fixVersions)
    # Both set to the same as epic's fix version
    UPDATE_PAYLOAD=$(jq -n \
        --argjson fixVersions "$EPIC_FIX_VERSIONS_JSON" \
        '{fields: {versions: $fixVersions, fixVersions: $fixVersions}}')

    jira_request "PUT" "/rest/api/3/issue/${STORY_KEY}" "$UPDATE_PAYLOAD" || {
        VERSION_FAIL=$((VERSION_FAIL + 1))
        continue
    }

    if [[ "$RESPONSE_CODE" == "204" || "$RESPONSE_CODE" == "200" ]]; then
        VERSION_NAMES=$(echo "$EPIC_FIX_VERSIONS_JSON" | jq -r '.[].name' | paste -sd ',' -)
        echo "  ✅ $STORY_KEY - Set versions to: $VERSION_NAMES"
        VERSION_SUCCESS=$((VERSION_SUCCESS + 1))
    else
        echo "  ❌ $STORY_KEY - Failed to update versions"
        VERSION_FAIL=$((VERSION_FAIL + 1))
    fi

    sleep 0.3
done

echo ""
echo -e "${GREEN}  ✅ Versions synced: $VERSION_SUCCESS${NC}"
[[ $VERSION_SKIP -gt 0 ]] && echo -e "${CYAN}  ℹ️  Skipped (no versions): $VERSION_SKIP${NC}"
[[ $VERSION_FAIL -gt 0 ]] && echo -e "${RED}  ❌ Failed: $VERSION_FAIL${NC}"
echo ""

# Final summary
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Sprint: ${SPRINT_NAME} (ID: ${SPRINT_ID})"
echo -e "Z-Stream Epics: ${EPIC_COUNT} (${#QE_EPIC_KEYS[@]} QE, ${#RELEASE_EPIC_KEYS[@]} Release)"
echo -e "Work Items: ${CHILD_COUNT} (${#QE_TASK_KEYS[@]} QE tasks, ${#DEV_STORY_KEYS[@]} dev stories)"
echo ""
echo -e "${GREEN}✅ Operations Completed:${NC}"
echo -e "  • Sprint assignments: $SPRINT_SUCCESS added, $SPRINT_SKIP already in sprint"
echo -e "  • QE epics assigned: $QE_EPIC_SUCCESS"
echo -e "  • QE tasks assigned: $QE_TASK_ASSIGN_SUCCESS (with ${QE_STORY_POINTS} story points)"
echo -e "  • QE task versions synced: $QE_TASK_VERSION_SUCCESS (affect & fix versions from parent epic)"
echo -e "  • Dev stories assigned: $DEV_STORY_SUCCESS"
echo -e "  • Dev story versions synced: $VERSION_SUCCESS (affect & fix versions from parent epic)"
echo ""
