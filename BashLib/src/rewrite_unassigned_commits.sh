#!/bin/bash

# to run the script paste command below in your terminal
# $NU_HOME/cloud-governance-dev/bin/nu_dev/github_helpers/rewrite_unassigned_commits.sh

function change_commit_author() {
    local COMMIT_HASH=$1
    local  NEW_AUTHOR_EMAIL=$2
    declare NEW_AUTHOR_NAME

    NEW_AUTHOR_NAME=$(git log --format='%an <%ae>' | grep "$NEW_AUTHOR_EMAIL" | head -n 1)

    if [ "$NEW_AUTHOR_NAME" == "" ]; then
        echo "Author with $NEW_AUTHOR_EMAIL not found in the commit history. Specify the name as third argument."
        exit 1
    fi

    git rebase -i "$COMMIT_HASH"^ -x "git commit --amend --author='$NEW_AUTHOR_NAME' --no-edit && git rebase --continue"
}
