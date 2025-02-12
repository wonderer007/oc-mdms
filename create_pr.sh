#!/bin/bash

BRANCH_NAME=$(git symbolic-ref --short HEAD)
BRANCH_REGEX="^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+"
BRANCH_PREFIX=$(echo "$BRANCH_NAME" | grep -oE "$BRANCH_REGEX")
JIRA_TICKET=$(grep -oE '(?i)[a-zA-Z]{2,3}-[0-9]+' <<< "$BRANCH_PREFIX")
REPO_NAME=$(basename "$PWD")
BASE_BRANCH="main"

# Only proceed if JIRA_TICKET is defined and not empty
if [ -n "${JIRA_TICKET}" ]; then
    TICKET_TITLE=$(echo "${BRANCH_NAME#"$BRANCH_PREFIX"}" | sed -e 's/[-_]/ /g' -e 's/\b\(.\)/\u\1/g') | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
    # Extract PR title (everything after JIRA TICKET)
    PR_TITLE="[$BASE_BRANCH, $REPO_NAME] $JIRA_TICKET: $(echo "$BRANCH_NAME" |echo "${TICKET_TITLE}")"
    # Get the latest commit message
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)

    # Construct the JIRA link
    JIRA_LINK="https://owenscorning.atlassian.net/browse/${JIRA_TICKET}"

    # Create the PR description
    PR_DESCRIPTION=$(cat <<EOF
JIRA: ${JIRA_LINK}

## Describe your changes
${COMMIT_MESSAGE}
EOF
    )

    # Create the pull request using GitHub CLI
    gh pr create --title "$PR_TITLE" --body "$PR_DESCRIPTION" --head "$BRANCH_NAME" --base "$BASE_BRANCH"

    echo "Pull request created successfully!"
else
  echo "Can not find JIRA ticket number"
fi
