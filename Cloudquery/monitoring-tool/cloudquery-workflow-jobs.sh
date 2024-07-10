#!/usr/bin/env bash
set -eo pipefail

export CLOUD_GOVERNANCE_DEV="$NU_HOME/cloud-governance-dev"
export CLOUDQUERY_REPO="$NU_HOME/cloudquery"
export HELPERS_SCRIPTS="$CLOUD_GOVERNANCE_DEV/bin/squad_cost_center/helpers"
export CLOUDQUERY_SCRIPTS="$CLOUD_GOVERNANCE_DEV/Cloudquery"
export MONITORING_TOOL_SCRIPTS="$CLOUDQUERY_SCRIPTS/monitoring-tool"
export CLOUDQUERY_MONITORING_PY="$CLOUDQUERY_REPO/scripts/monitoring.py"
export GITHUB_REPOSITORY="nubank/cloudquery"

## GitHub CLI api
## https://cli.github.com/manual/gh_api

json_array_get_id_by_name() {
    # Parameter validation: we need exactly two parameters
    if [[ $# -ne 2 ]]; then
        echo "Usage: json_search json_array value_to_search"
        exit 1
    fi

    # Parameter extraction
    local json_array="$1"
    local value_to_search="$2"

    # Processing JSON array
    local id
    id=$(echo "$json_array" | jq -r --arg vts "$value_to_search" '.[] | select(.name == $vts) | .id')
    if [ -z "$id" ]; then
        echo "No element found."
        exit 1
    else
        echo "$id"
    fi
}

clear
echo

TODAY_DATE=$(date -u "+%Y-%m-%d")
export TODAY_DATE

workflow_runs=$(gh api /repos/nubank/cloudquery/actions/runs | jq '.workflow_runs')
mapfile -t workflow_runs_ids < <(json_array_get_id_by_name "$workflow_runs" "Sync AWS")
WORKFLOW_RUN_ID="${workflow_runs_ids[0]}"
export WORKFLOW_RUN_ID
echo "WORKFLOW_RUN_ID: $WORKFLOW_RUN_ID"

## Get the jobs for the workflow run using the GitHub CLI
#echo
#gh api /repos/nubank/cloudquery/actions/runs/"$WORKFLOW_RUN_ID"/jobs \
#> "$MONITORING_TOOL_SCRIPTS"/output/workflow-jobs.json

## Get the jobs for the workflow run using curl
#echo
#curl -L \
#  -H "Accept: application/vnd.github+json" \
#  -H "Authorization: Bearer $GITHUB_TOKEN" \
#  -H "X-GitHub-Api-Version: 2022-11-28" \
#  https://api.github.com/repos/nubank/cloudquery/actions/runs/"$WORKFLOW_RUN_ID"/jobs \
#  > "$MONITORING_TOOL_SCRIPTS"/output/workflow-jobs.json
