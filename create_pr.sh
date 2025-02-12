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

    # Array to store PR numbers
    declare -A PR_NUMBERS

    # First pass: Create all PRs and store their numbers
    for BASE_BRANCH in "${TARGET_BRANCHES[@]}"; do
        PR_TITLE="[$BASE_BRANCH, $REPO_NAME] $JIRA_TICKET: $(echo "$BRANCH_NAME" |echo "${TICKET_TITLE}")"
        PR_DESCRIPTION="JIRA: ${JIRA_LINK}\n\n## Describe your changes\n${COMMIT_MESSAGE}"
        
        # Create PR and store its number
        PR_URL=$(gh pr create --title "$PR_TITLE" --body "$PR_DESCRIPTION" --head "$BRANCH_NAME" --base "$BASE_BRANCH" --json number --jq .number)
        PR_NUMBERS[$BASE_BRANCH]=$PR_URL
        echo "Pull request created for $BASE_BRANCH!"
    done

    # Second pass: Update all PR descriptions with cross-references
    for BASE_BRANCH in "${TARGET_BRANCHES[@]}"; do
        NEW_DESCRIPTION="JIRA: ${JIRA_LINK}\n\n"
        
        # Add links to other PRs
        for OTHER_BRANCH in "${TARGET_BRANCHES[@]}"; do
            if [ "$OTHER_BRANCH" != "$BASE_BRANCH" ]; then
                NEW_DESCRIPTION+="PR against ${OTHER_BRANCH}: #${PR_NUMBERS[$OTHER_BRANCH]}\n"
            fi
        done
        
        NEW_DESCRIPTION+="\n## Describe your changes\n${COMMIT_MESSAGE}"
        
        # Update PR description
        gh pr edit "${PR_NUMBERS[$BASE_BRANCH]}" --body "$NEW_DESCRIPTION"
        echo "Updated description for PR against $BASE_BRANCH"
    done

    echo "All pull requests created and updated successfully!"
else
    echo "Can not find JIRA ticket number"
fi
