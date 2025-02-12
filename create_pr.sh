#!/bin/bash

BRANCH_NAME=$(git symbolic-ref --short HEAD)
BRANCH_REGEX="^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+"
BRANCH_PREFIX=$(echo "$BRANCH_NAME" | grep -oE "$BRANCH_REGEX")
JIRA_TICKET=$(grep -oE '(?i)[a-zA-Z]{2,3}-[0-9]+' <<< "$BRANCH_PREFIX")
REPO_NAME=$(basename "$PWD")
TARGET_BRANCHES=("main" "ci-devel-server" "ci-stage-server")

if [ -n "${JIRA_TICKET}" ]; then
    TICKET_TITLE=$(echo "${BRANCH_NAME#"$BRANCH_PREFIX"}" | sed -e 's/[-_]/ /g' -e 's/\b\(.\)/\u\1/g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)
    JIRA_LINK="https://owenscorning.atlassian.net/browse/${JIRA_TICKET}"

    # Array to store PR numbers (using normal arrays instead of associative array)
    PR_URLS=()
    PR_BRANCHES=()

    # First pass: Create all PRs and store their numbers
    for BASE_BRANCH in "${TARGET_BRANCHES[@]}"; do
        PR_TITLE="[$BASE_BRANCH, $REPO_NAME] $JIRA_TICKET: $(echo "$BRANCH_NAME" |echo "${TICKET_TITLE}")"
        PR_DESCRIPTION="JIRA: ${JIRA_LINK}\n\n## Describe your changes\n${COMMIT_MESSAGE}"
        
        # Create PR and get its URL
        PR_URL=$(gh pr create --title "$PR_TITLE" --body "$PR_DESCRIPTION" --head "$BRANCH_NAME" --base "$BASE_BRANCH")
        PR_URLS+=("$PR_URL")
        PR_BRANCHES+=("$BASE_BRANCH")
        echo "Pull request created for $BASE_BRANCH!"
    done

    # Second pass: Update all PR descriptions with cross-references
    for i in "${!PR_BRANCHES[@]}"; do
        BASE_BRANCH="${PR_BRANCHES[$i]}"
        # Create the description using heredoc for proper formatting
        NEW_DESCRIPTION=$(cat <<EOF
JIRA: ${JIRA_LINK}

EOF
)

        for j in "${!PR_BRANCHES[@]}"; do
            if [ "${PR_BRANCHES[$j]}" != "$BASE_BRANCH" ]; then
                NEW_DESCRIPTION+=$(cat <<EOF

PR against \`${PR_BRANCHES[$j]}\`: ${PR_URLS[$j]}
EOF
)
            fi
        done
        
        NEW_DESCRIPTION+=$(cat <<EOF

## Describe your changes
${COMMIT_MESSAGE}
EOF
)
        
        # Update PR description
        gh pr edit "${PR_URLS[$i]}" --body "$NEW_DESCRIPTION"
        echo "Updated description for PR against $BASE_BRANCH"
    done

    echo "All pull requests created and updated successfully!"
else
    echo "Can not find JIRA ticket number"
fi
