#!/bin/bash
# Comprehensive Jira issue management for Global Hub
# Modes: update (individual issue), add-qe-tasks (add QE tasks to sprint), check-sprint (audit sprint issues)
# Usage:
#   ISSUE_KEY=ACM-31479 ./manage-jira-issues.sh
#   MODE=add-qe-tasks ./manage-jira-issues.sh
#   MODE=check-sprint ./manage-jira-issues.sh

set -euo pipefail

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m'
CYAN='\033[0;36m' YELLOW='\033[1;33m' NC='\033[0m' BOLD='\033[1m'

# Jira config
JIRA_BASE_URL="${JIRA_BASE_URL:-https://redhat.atlassian.net}"
JIRA_TOKEN="${JIRA_TOKEN:-${JIRA_API_TOKEN:-}}"
JIRA_USER="${JIRA_USER:-}"

# Parameters
MODE="${MODE:-update}"  # update, add-qe-tasks, check-sprint
ISSUE_KEY="${ISSUE_KEY:-}"
STORY_POINTS="${STORY_POINTS:-}"
SPRINT="${SPRINT:-}"
QE_APPLICABLE="${QE_APPLICABLE:-NotApplicable}"
DOC_REQUIRED="${DOC_REQUIRED:-not-required}"
FIX_VERSION="${FIX_VERSION:-Global Hub 1.8.0}"
AFFECT_VERSION="${AFFECT_VERSION:-Global Hub 1.8.0}"
PRIORITY="${PRIORITY:-Major}"
SEVERITY="${SEVERITY:-Moderate}"
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
calculate_sprint() {
    local sprint1_end="2026-04-01"
    local sprint1_end_ts
    local now_ts
    local three_weeks=$((21 * 24 * 60 * 60))

    if date -j -f "%Y-%m-%d" "$sprint1_end" "+%s" &>/dev/null; then
        sprint1_end_ts=$(date -j -f "%Y-%m-%d" "$sprint1_end" "+%s")
    else
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

# Calculate story points from task count (for stories)
calculate_story_points() {
    local task_count="$1"
    if [[ $task_count -le 2 ]]; then
        echo 1
    elif [[ $task_count -le 4 ]]; then
        echo 2
    elif [[ $task_count -le 6 ]]; then
        echo 3
    elif [[ $task_count -le 9 ]]; then
        echo 5
    else
        echo 8
    fi
}

# Extract task count from Jira ADF description
extract_task_count() {
    local description="$1"
    local count=0

    # Try to count taskItem elements (ADF format)
    count=$(echo "$description" | jq '[.. | objects | select(.type == "taskItem")] | length' 2>/dev/null || echo 0)

    # If no taskItems, try counting listItem elements
    if [[ "$count" == "0" ]]; then
        count=$(echo "$description" | jq '[.. | objects | select(.type == "listItem")] | length' 2>/dev/null || echo 0)
    fi

    # If still 0, try counting bullet points in text content
    if [[ "$count" == "0" ]]; then
        count=$(echo "$description" | jq -r '.. | strings' 2>/dev/null | grep -cE '^\s*[-*•]\s' || echo 0)
    fi

    echo "$count"
}

# Mode 1: Update individual issue
update_issue() {
    require_env ISSUE_KEY || { echo "Usage: ISSUE_KEY=ACM-31479 $0"; exit 1; }

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Update Issue - ${ISSUE_KEY}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Fetch the issue
    echo -e "${YELLOW}Fetching issue ${ISSUE_KEY}...${NC}"
    FIELDS="key,summary,issuetype,status,priority,labels,versions,fixVersions,customfield_10028,customfield_10464,description,assignee,issuelinks,project,components"
    jira_request "GET" "/rest/api/3/issue/${ISSUE_KEY}?fields=${FIELDS}" || {
        echo -e "${RED}Failed to fetch issue${NC}"
        exit 1
    }

    if [[ "$RESPONSE_CODE" != "200" ]]; then
        echo -e "${RED}Failed to fetch issue (HTTP $RESPONSE_CODE):${NC}"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null
        exit 1
    fi

    # Extract current values
    SUMMARY=$(echo "$RESPONSE_BODY" | jq -r '.fields.summary // ""')
    ISSUE_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.fields.issuetype.name // ""')
    CURRENT_PRIORITY=$(echo "$RESPONSE_BODY" | jq -r '.fields.priority.name // empty')
    CURRENT_LABELS=$(echo "$RESPONSE_BODY" | jq -r '.fields.labels // []')
    CURRENT_VERSIONS=$(echo "$RESPONSE_BODY" | jq -r '.fields.versions // []')
    CURRENT_FIX_VERSIONS=$(echo "$RESPONSE_BODY" | jq -r '.fields.fixVersions // []')
    CURRENT_STORY_POINTS=$(echo "$RESPONSE_BODY" | jq -r '.fields.customfield_10028 // empty')
    CURRENT_ACTIVITY_TYPE=$(echo "$RESPONSE_BODY" | jq -r '.fields.customfield_10464.value // empty')
    DESCRIPTION=$(echo "$RESPONSE_BODY" | jq '.fields.description // {}')
    STORY_ASSIGNEE=$(echo "$RESPONSE_BODY" | jq -r '.fields.assignee.accountId // empty')
    PROJECT_KEY=$(echo "$RESPONSE_BODY" | jq -r '.fields.project.key // "ACM"')
    COMPONENTS=$(echo "$RESPONSE_BODY" | jq -r '.fields.components // []')
    ISSUE_LINKS=$(echo "$RESPONSE_BODY" | jq -r '.fields.issuelinks // []')

    echo -e "  Summary: ${SUMMARY}"
    echo -e "  Type: ${ISSUE_TYPE}"
    echo ""

    # Check if this is a CVE issue
    IS_CVE=false
    if [[ "$SUMMARY" == *"CVE"* ]]; then
        IS_CVE=true
        echo -e "  ${CYAN}Detected: CVE issue${NC}"
    fi

    # Determine defaults and behavior based on issue type
    SHOULD_SET_STORY_POINTS=true
    IS_STORY=false

    case "$ISSUE_TYPE" in
        "Story")
            IS_STORY=true
            DEFAULT_ACTIVITY_TYPE="Product / Portfolio Work"
            DEFAULT_STORY_POINTS=""  # Will be calculated
            ;;
        "Bug")
            DEFAULT_ACTIVITY_TYPE="Quality / Stability / Reliability"
            DEFAULT_STORY_POINTS=2
            ;;
        "Task"|"Sub-task"|"任务"|"子任务")
            if [[ "$SUMMARY" == *"[QE"* ]]; then
                DEFAULT_ACTIVITY_TYPE="Quality / Stability / Reliability"
                DEFAULT_STORY_POINTS=2
            else
                DEFAULT_ACTIVITY_TYPE="Product / Portfolio Work"
                DEFAULT_STORY_POINTS=2
                SHOULD_SET_STORY_POINTS=false
            fi
            ;;
        "Spike")
            DEFAULT_ACTIVITY_TYPE="Product / Portfolio Work"
            DEFAULT_STORY_POINTS=3
            ;;
        *)
            DEFAULT_ACTIVITY_TYPE="Product / Portfolio Work"
            DEFAULT_STORY_POINTS=2
            ;;
    esac

    # Override with CVE-specific rules
    if [[ "$IS_CVE" == "true" ]]; then
        DEFAULT_ACTIVITY_TYPE="Quality / Stability / Reliability"
        DEFAULT_STORY_POINTS=2
        SHOULD_SET_STORY_POINTS=false
    fi

    # For stories, handle story-specific logic
    if [[ "$IS_STORY" == "true" ]]; then
        # Auto-calculate sprint if not provided
        if [[ -z "$SPRINT" ]]; then
            SPRINT=$(calculate_sprint)
            echo -e "  ${CYAN}Auto-calculated Sprint:${NC} ${SPRINT}"
        fi

        # Auto-calculate story points if not provided and not already set
        if [[ -z "$STORY_POINTS" && -z "$CURRENT_STORY_POINTS" ]]; then
            TASK_COUNT=$(extract_task_count "$DESCRIPTION")
            echo -e "  ${CYAN}Tasks found in description:${NC} ${TASK_COUNT}"

            if [[ "$TASK_COUNT" -gt 0 ]]; then
                STORY_POINTS=$(calculate_story_points "$TASK_COUNT")
                echo -e "  ${CYAN}Auto-calculated Story Points:${NC} ${STORY_POINTS}"
            else
                STORY_POINTS=3
                echo -e "  ${YELLOW}No tasks found, defaulting to:${NC} ${STORY_POINTS} story points"
            fi
        elif [[ -n "$CURRENT_STORY_POINTS" ]]; then
            echo -e "  ${GREEN}Preserving existing Story Points:${NC} ${CURRENT_STORY_POINTS}"
            STORY_POINTS="$CURRENT_STORY_POINTS"
            SHOULD_SET_STORY_POINTS=false
        fi

        # Validate story points
        if [[ -n "$STORY_POINTS" && ! "$STORY_POINTS" =~ ^(1|2|3|5|8)$ ]]; then
            echo -e "${RED}Error: STORY_POINTS must be 1, 2, 3, 5, or 8${NC}"
            exit 1
        fi

        ACTIVITY_TYPE="$DEFAULT_ACTIVITY_TYPE"
    else
        # For non-stories, use provided story points or default
        if [[ -z "$STORY_POINTS" ]]; then
            STORY_POINTS=$DEFAULT_STORY_POINTS
        fi
        ACTIVITY_TYPE="$DEFAULT_ACTIVITY_TYPE"
    fi

    echo -e "${BOLD}Current Values:${NC}"
    echo -e "  Priority: ${CURRENT_PRIORITY:-<not set>}"
    echo -e "  Story Points: ${CURRENT_STORY_POINTS:-<not set>}"
    echo -e "  Activity Type: ${CURRENT_ACTIVITY_TYPE:-<not set>}"
    echo -e "  Affect Version: $(echo "$CURRENT_VERSIONS" | jq -r '.[0].name // "<not set>"')"
    echo -e "  Fix Version: $(echo "$CURRENT_FIX_VERSIONS" | jq -r '.[0].name // "<not set>"')"
    echo ""

    # Build update payload
    PAYLOAD='{"fields":{}}'
    FIELDS_TO_UPDATE=()

    # Priority
    if [[ -z "$CURRENT_PRIORITY" || "$CURRENT_PRIORITY" == "null" ]]; then
        PAYLOAD=$(echo "$PAYLOAD" | jq '.fields.priority = {name: "Major"}')
        FIELDS_TO_UPDATE+=("Priority -> Major")
    fi

    # Story Points
    if [[ "$SHOULD_SET_STORY_POINTS" == "true" && -n "$STORY_POINTS" && ( -z "$CURRENT_STORY_POINTS" || "$CURRENT_STORY_POINTS" == "null" ) ]]; then
        PAYLOAD=$(echo "$PAYLOAD" | jq --argjson sp "$STORY_POINTS" '.fields.customfield_10028 = $sp')
        FIELDS_TO_UPDATE+=("Story Points -> ${STORY_POINTS}")
    fi

    # Activity Type
    if [[ -z "$CURRENT_ACTIVITY_TYPE" || "$CURRENT_ACTIVITY_TYPE" == "null" ]]; then
        PAYLOAD=$(echo "$PAYLOAD" | jq --arg at "$ACTIVITY_TYPE" '.fields.customfield_10464 = {value: $at}')
        FIELDS_TO_UPDATE+=("Activity Type -> ${ACTIVITY_TYPE}")
    fi

    # Affect Version
    VERSIONS_COUNT=$(echo "$CURRENT_VERSIONS" | jq 'length')
    if [[ "$VERSIONS_COUNT" == "0" ]]; then
        PAYLOAD=$(echo "$PAYLOAD" | jq --arg av "$AFFECT_VERSION" '.fields.versions = [{name: $av}]')
        FIELDS_TO_UPDATE+=("Affect Version -> ${AFFECT_VERSION}")
    fi

    # Fix Version (skip for CVE issues)
    FIX_VERSIONS_COUNT=$(echo "$CURRENT_FIX_VERSIONS" | jq 'length')
    if [[ "$FIX_VERSIONS_COUNT" == "0" && "$IS_CVE" == "false" ]]; then
        PAYLOAD=$(echo "$PAYLOAD" | jq --arg fv "$FIX_VERSION" '.fields.fixVersions = [{name: $fv}]')
        FIELDS_TO_UPDATE+=("Fix Version -> ${FIX_VERSION}")
    fi

    # For stories, handle labels
    if [[ "$IS_STORY" == "true" ]]; then
        # Build labels array
        LABELS=("Eng-Status:Green" "Sprint${SPRINT}")

        # Check for existing QE labels (case-insensitive)
        HAS_QE_REQUIRED=$(echo "$CURRENT_LABELS" | jq 'any(test("^QE-Required$"; "i"))')
        HAS_QE_NA=$(echo "$CURRENT_LABELS" | jq 'any(test("^QE-NotApplicable$"; "i"))')

        # Only set QE label if neither exists
        if [[ "$HAS_QE_REQUIRED" != "true" && "$HAS_QE_NA" != "true" ]]; then
            if [[ "$QE_APPLICABLE" == "Required" ]]; then
                LABELS+=("QE-Required" "QE-Confidence:Green")
            else
                LABELS+=("QE-NotApplicable")
            fi
        fi

        if [[ "$DOC_REQUIRED" == "required" ]]; then
            LABELS+=("doc-required")
        else
            LABELS+=("doc-not-required")
        fi

        # Filter out conflicting labels, but preserve existing QE-Required/QE-NotApplicable
        FILTERED_LABELS=$(echo "$CURRENT_LABELS" | jq -r '[.[] | select(
            (startswith("Eng-Status:") | not) and
            (test("^QE-(Required|NotApplicable)$"; "i") or (startswith("QE-") | not)) and
            (startswith("doc-") | not) and
            (startswith("Train-") | not) and
            (startswith("Sprint") | not)
        )]')

        # Merge filtered labels with new labels
        LABELS_JSON=$(echo "$FILTERED_LABELS" | jq --argjson new "$(printf '%s\n' "${LABELS[@]}" | jq -R . | jq -s .)" '. + $new | unique')

        PAYLOAD=$(echo "$PAYLOAD" | jq --argjson labels "$LABELS_JSON" '.fields.labels = $labels')
        FIELDS_TO_UPDATE+=("Labels -> ${LABELS[*]}")
    fi

    # Check if there's anything to update
    if [[ ${#FIELDS_TO_UPDATE[@]} -eq 0 ]]; then
        echo -e "${GREEN}All required fields are already set. No updates needed.${NC}"
        echo -e "  ${JIRA_BASE_URL}/browse/${ISSUE_KEY}"

        # For stories with doc-required, still check doc task
        if [[ "$IS_STORY" == "true" ]]; then
            handle_doc_task
        fi

        exit 0
    fi

    echo -e "${BOLD}Fields to Update:${NC}"
    for field in "${FIELDS_TO_UPDATE[@]}"; do
        echo -e "  - ${field}"
    done
    echo ""

    # Update the issue
    echo -e "${YELLOW}Updating issue...${NC}"
    jira_request "PUT" "/rest/api/3/issue/${ISSUE_KEY}" "$PAYLOAD" || {
        echo -e "${RED}Curl error${NC}"
        exit 1
    }

    if [[ "$RESPONSE_CODE" == "204" ]]; then
        echo -e "${GREEN}Successfully updated ${ISSUE_KEY}${NC}"
        echo -e "  ${JIRA_BASE_URL}/browse/${ISSUE_KEY}"
    else
        echo -e "${RED}Failed to update issue (HTTP $RESPONSE_CODE):${NC}"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"

        # Retry without Activity Type
        echo -e "${YELLOW}Retrying without Activity Type field...${NC}"
        PAYLOAD=$(echo "$PAYLOAD" | jq 'del(.fields.customfield_10464)')

        jira_request "PUT" "/rest/api/3/issue/${ISSUE_KEY}" "$PAYLOAD" || {
            echo -e "${RED}Curl error${NC}"
            exit 1
        }

        if [[ "$RESPONSE_CODE" == "204" ]]; then
            echo -e "${GREEN}Successfully updated ${ISSUE_KEY} (without Activity Type)${NC}"
            echo -e "${YELLOW}Note: Activity Type field may need to be set manually${NC}"
            echo -e "  ${JIRA_BASE_URL}/browse/${ISSUE_KEY}"
        else
            echo -e "${RED}Failed to update issue (HTTP $RESPONSE_CODE):${NC}"
            echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
            exit 1
        fi
    fi

    echo ""
    echo -e "${CYAN}Summary${NC}"
    echo -e "  Issue: ${JIRA_BASE_URL}/browse/${ISSUE_KEY}"
    echo -e "  Type: ${ISSUE_TYPE}"
    echo -e "  Updated Fields: ${#FIELDS_TO_UPDATE[@]}"
    echo ""

    # Handle doc task for stories
    if [[ "$IS_STORY" == "true" ]]; then
        handle_doc_task
    fi
}

# Handle doc task creation/checking for stories
handle_doc_task() {
    if [[ "$DOC_REQUIRED" != "required" ]]; then
        return
    fi

    echo -e "${YELLOW}Checking for linked doc task (doc-required is set)...${NC}"

    # Check if there's already a doc task linked
    HAS_DOC_TASK=false
    DOC_TASK_KEY=""

    # Look for linked issues with [Doc] in summary
    DOC_LINKS=$(echo "$ISSUE_LINKS" | jq -c '[.[] |
        select(
            (.inwardIssue.fields.summary // "" | test("\\[Doc\\]"; "i")) or
            (.outwardIssue.fields.summary // "" | test("\\[Doc\\]"; "i"))
        ) |
        {
            key: (.inwardIssue.key // .outwardIssue.key),
            summary: (.inwardIssue.fields.summary // .outwardIssue.fields.summary)
        }
    ]')

    DOC_LINK_COUNT=$(echo "$DOC_LINKS" | jq 'length')

    if [[ "$DOC_LINK_COUNT" -gt 0 ]]; then
        DOC_TASK_KEY=$(echo "$DOC_LINKS" | jq -r '.[0].key')
        echo -e "  ${GREEN}Doc task already linked: ${DOC_TASK_KEY}${NC}"
        HAS_DOC_TASK=true
    fi

    # If no doc task found, create one
    if [[ "$HAS_DOC_TASK" == "false" ]]; then
        echo -e "  ${YELLOW}No doc task found. Creating one...${NC}"

        DOC_TASK_TITLE="[Doc] ${SUMMARY}"

        DOC_DESC_ADF=$(jq -n --arg story "$ISSUE_KEY" \
            '{type:"doc",version:1,content:[
                {type:"paragraph",content:[{type:"text",text:"Documentation task for story "},
                    {type:"inlineCard",attrs:{url:("https://redhat.atlassian.net/browse/" + $story)}}
                ]}
            ]}')

        DOC_PAYLOAD=$(jq -n \
            --arg p "$PROJECT_KEY" \
            --arg s "$DOC_TASK_TITLE" \
            --argjson d "$DOC_DESC_ADF" \
            --argjson c "$COMPONENTS" \
            '{fields:{
                project:{key:$p},
                summary:$s,
                description:$d,
                issuetype:{name:"Task"},
                components:$c,
                labels:["doc-task"],
                security:{name:"Red Hat Employee"}
            }}')

        if [[ -n "$STORY_ASSIGNEE" ]]; then
            DOC_PAYLOAD=$(echo "$DOC_PAYLOAD" | jq --arg assignee "$STORY_ASSIGNEE" '.fields.assignee = {accountId: $assignee}')
        fi

        jira_request "POST" "/rest/api/3/issue" "$DOC_PAYLOAD" || {
            echo -e "  ${RED}Failed to create doc task${NC}"
            return
        }

        if [[ "$RESPONSE_CODE" == "201" ]]; then
            DOC_TASK_KEY=$(echo "$RESPONSE_BODY" | jq -r '.key')
            echo -e "  ${GREEN}Created doc task: ${DOC_TASK_KEY}${NC}"
            echo -e "  ${JIRA_BASE_URL}/browse/${DOC_TASK_KEY}"

            # Link doc task to story
            echo -e "  ${YELLOW}Linking doc task to story...${NC}"
            LINK_PAYLOAD=$(jq -n --arg inward "$ISSUE_KEY" --arg outward "$DOC_TASK_KEY" \
                '{type:{name:"Implements"},inwardIssue:{key:$inward},outwardIssue:{key:$outward}}')

            jira_request "POST" "/rest/api/3/issueLink" "$LINK_PAYLOAD" || true

            if [[ "$RESPONSE_CODE" == "201" ]]; then
                echo -e "  ${GREEN}Linked: ${DOC_TASK_KEY} implements ${ISSUE_KEY}${NC}"
            else
                LINK_PAYLOAD=$(jq -n --arg inward "$ISSUE_KEY" --arg outward "$DOC_TASK_KEY" \
                    '{type:{name:"Related"},inwardIssue:{key:$inward},outwardIssue:{key:$outward}}')
                jira_request "POST" "/rest/api/3/issueLink" "$LINK_PAYLOAD" || true
                if [[ "$RESPONSE_CODE" == "201" ]]; then
                    echo -e "  ${GREEN}Linked: ${DOC_TASK_KEY} relates to ${ISSUE_KEY}${NC}"
                else
                    echo -e "  ${YELLOW}Could not link issues (HTTP $RESPONSE_CODE)${NC}"
                fi
            fi

            # Recursively call update on doc task
            echo -e "  ${YELLOW}Setting required fields on doc task...${NC}"
            SAVED_ISSUE_KEY="$ISSUE_KEY"
            ISSUE_KEY="$DOC_TASK_KEY"
            update_issue
            ISSUE_KEY="$SAVED_ISSUE_KEY"
        else
            echo -e "  ${RED}Failed to create doc task (HTTP $RESPONSE_CODE):${NC}"
            echo "$RESPONSE_BODY" | jq . 2>/dev/null || echo "$RESPONSE_BODY"
        fi
    fi
}

# Mode 2: Add QE tasks to sprint
add_qe_tasks_to_sprint() {
    local sprint_num="${SPRINT:-$(calculate_sprint)}"
    local sprint_name="GH Sprint ${sprint_num}"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Add QE Tasks to Sprint - ${sprint_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
        echo ""
    fi

    # Get all stories in the sprint
    echo -e "${YELLOW}Step 1: Finding stories in ${sprint_name}...${NC}"
    STORY_JQL="component = \"Global Hub\" AND Sprint = \"${sprint_name}\" AND issuetype = Story ORDER BY key ASC"

    jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "$STORY_JQL" | jq -sRr @uri)&fields=key,summary,issuelinks&maxResults=100" || {
        echo -e "${RED}Failed to fetch stories${NC}"
        exit 1
    }

    if [[ "$RESPONSE_CODE" != "200" ]]; then
        echo -e "${RED}Failed to fetch stories (HTTP $RESPONSE_CODE):${NC}"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null
        exit 1
    fi

    STORY_COUNT=$(echo "$RESPONSE_BODY" | jq '.total')
    echo -e "${GREEN}Found ${STORY_COUNT} stories${NC}"
    echo ""

    if [[ "$STORY_COUNT" == "0" ]]; then
        echo -e "${YELLOW}No stories found in this sprint.${NC}"
        exit 0
    fi

    STORIES=$(echo "$RESPONSE_BODY" | jq -c '.issues[]')

    # Find linked QE tasks
    echo -e "${YELLOW}Step 2: Finding linked QE tasks...${NC}"
    echo ""

    rm -f /tmp/qe_tasks_to_add_$$.txt

    echo "$STORIES" | while read -r story; do
        STORY_KEY=$(echo "$story" | jq -r '.key')
        STORY_SUMMARY=$(echo "$story" | jq -r '.fields.summary')

        echo -e "${BOLD}${STORY_KEY}:${NC} ${STORY_SUMMARY:0:60}..."

        LINKS=$(echo "$story" | jq -r '.fields.issuelinks // []')

        QE_LINKS=$(echo "$LINKS" | jq -c '[.[] |
            select(
                (.inwardIssue.fields.summary // "" | test("\\[QE"; "i")) or
                (.outwardIssue.fields.summary // "" | test("\\[QE"; "i")) or
                (.type.name == "Test")
            ) |
            {
                key: (.inwardIssue.key // .outwardIssue.key),
                summary: (.inwardIssue.fields.summary // .outwardIssue.fields.summary),
                type: .type.name
            }
        ]')

        QE_COUNT=$(echo "$QE_LINKS" | jq 'length')

        if [[ "$QE_COUNT" == "0" ]]; then
            echo -e "  ${CYAN}No QE tasks linked${NC}"
        else
            echo "$QE_LINKS" | jq -c '.[]' | while read -r qe_task; do
                QE_KEY=$(echo "$qe_task" | jq -r '.key')
                QE_SUMMARY=$(echo "$qe_task" | jq -r '.summary')

                echo -e "  ${CYAN}Found:${NC} ${QE_KEY} - ${QE_SUMMARY:0:50}..."

                jira_request "GET" "/rest/api/3/issue/${QE_KEY}?fields=customfield_10020" || continue

                if [[ "$RESPONSE_CODE" != "200" ]]; then
                    echo -e "    ${YELLOW}Could not fetch ${QE_KEY}${NC}"
                    continue
                fi

                CURRENT_SPRINT=$(echo "$RESPONSE_BODY" | jq -r '.fields.customfield_10020 // [] | .[0].name // empty')

                if [[ -z "$CURRENT_SPRINT" ]]; then
                    echo -e "    ${YELLOW}Not in any sprint - will add to ${sprint_name}${NC}"
                    echo "$QE_KEY" >> /tmp/qe_tasks_to_add_$$.txt
                elif [[ "$CURRENT_SPRINT" == "$sprint_name" ]]; then
                    echo -e "    ${GREEN}Already in ${sprint_name}${NC}"
                else
                    echo -e "    ${CYAN}In different sprint: ${CURRENT_SPRINT}${NC}"
                fi
            done
        fi
        echo ""
    done

    # Add QE tasks to sprint
    echo -e "${YELLOW}Step 3: Adding QE tasks to sprint...${NC}"
    echo ""

    if [[ -f /tmp/qe_tasks_to_add_$$.txt ]]; then
        TASKS_TO_ADD=$(cat /tmp/qe_tasks_to_add_$$.txt | sort -u)
        TASK_COUNT=$(echo "$TASKS_TO_ADD" | wc -l | tr -d ' ')

        if [[ "$TASK_COUNT" -gt 0 ]]; then
            echo -e "${BOLD}QE Tasks to add to ${sprint_name}:${NC}"

            # Find sprint ID
            echo -e "${YELLOW}Looking up sprint ID for ${sprint_name}...${NC}"

            jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "Sprint = \"${sprint_name}\"" | jq -sRr @uri)&fields=customfield_10020&maxResults=1" || {
                echo -e "${RED}Failed to find sprint ID${NC}"
                rm -f /tmp/qe_tasks_to_add_$$.txt
                exit 1
            }

            SPRINT_ID=$(echo "$RESPONSE_BODY" | jq -r '.issues[0].fields.customfield_10020[0].id // empty')

            if [[ -z "$SPRINT_ID" ]]; then
                echo -e "${RED}Could not find sprint ID for ${sprint_name}${NC}"
                rm -f /tmp/qe_tasks_to_add_$$.txt
                exit 1
            fi

            echo -e "  Sprint ID: ${SPRINT_ID}"
            echo ""

            ADDED_COUNT=0
            FAILED_COUNT=0

            for QE_KEY in $TASKS_TO_ADD; do
                echo -e "  Adding ${QE_KEY} to ${sprint_name}..."

                if [[ "$DRY_RUN" == "true" ]]; then
                    echo -e "    ${CYAN}[DRY RUN] Would add to sprint${NC}"
                    ((ADDED_COUNT++))
                    continue
                fi

                PAYLOAD=$(jq -n --arg sprintId "$SPRINT_ID" '{fields: {customfield_10020: [($sprintId | tonumber)]}}')

                jira_request "PUT" "/rest/api/3/issue/${QE_KEY}" "$PAYLOAD" || {
                    echo -e "    ${RED}Failed to update${NC}"
                    ((FAILED_COUNT++))
                    continue
                }

                if [[ "$RESPONSE_CODE" == "204" ]]; then
                    echo -e "    ${GREEN}Added successfully${NC}"
                    ((ADDED_COUNT++))
                else
                    echo -e "    ${RED}Failed (HTTP $RESPONSE_CODE)${NC}"
                    ((FAILED_COUNT++))
                fi
            done

            echo ""
            echo -e "${GREEN}Added: ${ADDED_COUNT}${NC}"
            if [[ "$FAILED_COUNT" -gt 0 ]]; then
                echo -e "${RED}Failed: ${FAILED_COUNT}${NC}"
            fi
        fi

        rm -f /tmp/qe_tasks_to_add_$$.txt
    else
        echo -e "${GREEN}No QE tasks need to be added to the sprint.${NC}"
    fi

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Sprint: ${sprint_name}"
    echo -e "Stories checked: ${STORY_COUNT}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}Mode: DRY RUN (no changes made)${NC}"
    fi
    echo ""
}

# Mode 3: Check sprint issues for missing fields
check_sprint_issues() {
    local sprint_num="${SPRINT:-$(calculate_sprint)}"
    local sprint_name="GH Sprint ${sprint_num}"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Check Sprint Issues - ${sprint_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "${YELLOW}Fetching all issues in ${sprint_name}...${NC}"
    ISSUE_JQL="component = \"Global Hub\" AND Sprint = \"${sprint_name}\" ORDER BY key ASC"

    jira_request "GET" "/rest/api/3/search/jql?jql=$(echo "$ISSUE_JQL" | jq -sRr @uri)&fields=key,summary,issuetype,priority,customfield_10028,customfield_10464,versions,fixVersions&maxResults=100" || {
        echo -e "${RED}Failed to fetch issues${NC}"
        exit 1
    }

    if [[ "$RESPONSE_CODE" != "200" ]]; then
        echo -e "${RED}Failed to fetch issues (HTTP $RESPONSE_CODE):${NC}"
        echo "$RESPONSE_BODY" | jq . 2>/dev/null
        exit 1
    fi

    ISSUE_COUNT=$(echo "$RESPONSE_BODY" | jq '.total')
    echo -e "${GREEN}Found ${ISSUE_COUNT} issues${NC}"
    echo ""

    if [[ "$ISSUE_COUNT" == "0" ]]; then
        echo -e "${YELLOW}No issues found in this sprint.${NC}"
        exit 0
    fi

    ISSUES=$(echo "$RESPONSE_BODY" | jq -c '.issues[]')

    ISSUES_WITH_MISSING_FIELDS=()

    echo "$ISSUES" | while read -r issue; do
        KEY=$(echo "$issue" | jq -r '.key')
        SUMMARY=$(echo "$issue" | jq -r '.fields.summary // ""')
        TYPE=$(echo "$issue" | jq -r '.fields.issuetype.name // ""')
        PRIORITY=$(echo "$issue" | jq -r '.fields.priority.name // empty')
        STORY_POINTS=$(echo "$issue" | jq -r '.fields.customfield_10028 // empty')
        ACTIVITY=$(echo "$issue" | jq -r '.fields.customfield_10464.value // empty')
        VERSIONS=$(echo "$issue" | jq -r '.fields.versions // []')
        FIX_VERSIONS=$(echo "$issue" | jq -r '.fields.fixVersions // []')

        MISSING_FIELDS=()

        if [[ -z "$PRIORITY" ]]; then
            MISSING_FIELDS+=("Priority")
        fi

        if [[ -z "$ACTIVITY" ]]; then
            MISSING_FIELDS+=("Activity Type")
        fi

        VERSION_COUNT=$(echo "$VERSIONS" | jq 'length')
        if [[ "$VERSION_COUNT" == "0" ]]; then
            MISSING_FIELDS+=("Affect Version")
        fi

        FIX_VERSION_COUNT=$(echo "$FIX_VERSIONS" | jq 'length')
        IS_CVE=false
        if [[ "$SUMMARY" == *"CVE"* ]]; then
            IS_CVE=true
        fi

        if [[ "$FIX_VERSION_COUNT" == "0" && "$IS_CVE" == "false" ]]; then
            MISSING_FIELDS+=("Fix Version")
        fi

        # Check story points based on issue type
        if [[ "$TYPE" == "Story" || "$TYPE" == "Bug" || "$TYPE" == "Spike" ]]; then
            if [[ -z "$STORY_POINTS" ]]; then
                MISSING_FIELDS+=("Story Points")
            fi
        elif [[ "$TYPE" == "Task" || "$TYPE" == "Sub-task" ]]; then
            if [[ "$SUMMARY" == *"[QE"* && -z "$STORY_POINTS" ]]; then
                MISSING_FIELDS+=("Story Points")
            fi
        fi

        if [[ ${#MISSING_FIELDS[@]} -gt 0 ]]; then
            echo -e "${RED}${KEY}${NC} - ${TYPE} - ${SUMMARY:0:50}..."
            for field in "${MISSING_FIELDS[@]}"; do
                echo -e "  ${YELLOW}Missing: ${field}${NC}"
            done
            echo ""
        else
            echo -e "${GREEN}${KEY}${NC} - ${TYPE} - All required fields set"
        fi
    done

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Sprint: ${sprint_name}"
    echo -e "Total issues: ${ISSUE_COUNT}"
    echo ""
}

# Main
require_env JIRA_TOKEN || exit 1
require_env JIRA_USER || exit 1

case "$MODE" in
    "update")
        update_issue
        ;;
    "add-qe-tasks")
        add_qe_tasks_to_sprint
        ;;
    "check-sprint")
        check_sprint_issues
        ;;
    *)
        echo -e "${RED}Error: Invalid MODE=${MODE}${NC}"
        echo "Valid modes: update, add-qe-tasks, check-sprint"
        exit 1
        ;;
esac
