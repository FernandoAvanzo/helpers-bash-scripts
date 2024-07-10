#!/bin/bash
export CLOUD_GOVERNANCE_DEV="$NU_HOME/cloud-governance-dev"
export HELPERS_SCRIPTS="$CLOUD_GOVERNANCE_DEV/bin/squad_cost_center/helpers"
# shellcheck source=./tool_check_script.sh
source "$HELPERS_SCRIPTS/tool_check_script.sh"

function replace_identity_file() {
  local file=$1
  local original_line="IdentityFile /var/run/secrets/ssh/ssh-privatekey"
  local new_line="IdentityFile ~/.ssh/github-ssh"

  # -i option is for in-place edit
  # -e option is used to script editing command
  # s is the substitute flag
  # g is for global replacement (change all occurrences, not just first one)
  sed -i -e "s@$original_line@$new_line@g" "$file"
}

function git_update() {
  local repo_path=$1
  # Check if the repository path was provided
  if [[ -z "$repo_path" ]]; then
    echo "Please provide a repository path."
    return 1
  fi
  # Check if the repository path exists
  if [[ ! -d "$repo_path" ]]; then
    echo "The provided path does not exist or is not a directory."
    return 1
  fi
  # Navigate to the repository's directory
  cd "$repo_path" || exit
  # Check if the directory is a git repository
  if [[ ! -d .git ]]; then
    # If there's no .git directory, it's not a git repository
    echo "The provided directory is not a git repository."
    return 1
  fi
  # Pull the latest changes from the remote repository
  git fetch --all
  git pull
  echo "The repository has been updated."
}

function create_branch() {
  # Navigate to the repository's folder
  cd "$1" || exit

  # Fetch the latest data from the original ("upstream") repository
  git fetch origin
  echo

  # Create a branch based on 'master'
  git checkout -b bulk-squad-idm-id master
  echo

  # Push this new branch to origin
  git push origin bulk-squad-idm-id
  echo
}

function update_and_push() {
  declare pr_title
  local repo_path=$1
  local branch_name=bulk-squad-idm-id # modify as required
  local commit_message="bulking squads idm-ids"
  pr_title="Bulking idm-ids in squads - $(date +'%m/%d/%Y')"

  # If an argument is not provided, exit.
  if [ -z "$repo_path" ]; then
    echo "Please provide the path to your local git repository"
    exit 1
  fi

  check_and_install_tools

  # Go to your local repository directory
  cd "$repo_path" || exit

  # Checkout to the branch
  git checkout $branch_name

  # If the branch does not exist, return 1
  if ! git checkout $branch_name; then
    echo "Please provide a valid branch name"
    exit 1
  fi

  # Adding new files to the staging area
  git add .

  # Committing the changes
  git commit -m "$commit_message"

  # Pushing the changes to the branch
  git push origin $branch_name

  # Create a pull request and get the URL
  gh pr create --title "$pr_title" --body "" --base master --head $branch_name --fill --web
  echo

  echo "Pull Request has been created."
  echo
}

function get_changed_files() {
  local git_repository_path=$1
  local sub_directory_path=$2
  declare -n return_array=$3

  declare -a changed_files_query
  mapfile -t changed_files_query < <(git -C "$git_repository_path" \
                                      diff origin/master...HEAD \
                                      --name-only \
                                      --diff-filter=AM | grep "^$sub_directory_path")

  if [[ ${#changed_files_query[@]} -eq 0 ]]; then
    echo
  else
    return_array=("${changed_files_query[@]}")
  fi
}
