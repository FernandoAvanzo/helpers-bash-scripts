#!/usr/bin/env bash
set -eo pipefail

export CLOUDQUERY_PROJECT="<local-path>/helpers-bash-scripts"
export HELPERS_SCRIPTS="$CLOUDQUERY_PROJECT/bin/squad_cost_center/helpers"
export CLOUDQUERY_SCRIPTS="$CLOUDQUERY_PROJECT/Cloudquery"
export CLOUDWATCH_METRICS_SCRIPTS="$CLOUDQUERY_SCRIPTS/cloudwatch-metrics"
export CLOUDWATCH_METRICS_OUTPUT="$CLOUDWATCH_METRICS_SCRIPTS/output"

get_timestamp() {
  local time=$1
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # GNU date command (for Linux)
    date -u -d "yesterday $time" "+%Y-%m-%dT%H:%M:%SZ"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    # BSD date command (for MacOS)
    local yesterday
    yesterday=$(date -u -v-1d "+%Y-%m-%d")
    echo "${yesterday}T${time}Z"
  else
    echo "Unknown OS"
  fi
}

test_connection() {
  cloudquery test-connection "$CLOUDWATCH_METRICS_SCRIPTS"/config.yml
}

# Function to log in to Cloudquery
login() {
  cloudquery login
}

START_TIME=$(get_timestamp "00:00:00")
export START_TIME

END_TIME=$(get_timestamp "01:59:00")
export END_TIME
echo "START_TIME: $START_TIME"
echo "END_TIME: $END_TIME"


if ! test_connection; then
  echo "Connection test failed. Attempting to login..."
  if ! login; then
    echo "Login failed. Please check your credentials and try again."
    exit 1
    else
      cloudquery sync "$CLOUDWATCH_METRICS_SCRIPTS"/config.yml
  fi
else
  cloudquery sync "$CLOUDWATCH_METRICS_SCRIPTS"/config.yml
fi
