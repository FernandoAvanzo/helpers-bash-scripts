#!/usr/bin/env bash
set -euo pipefail

REQUIRED_NODE_MAJOR=22

echo "=== OpenAI Codex CLI installer (Linux) ==="

# 1) Basic OS check
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script is intended for Linux only. Aborting."
  exit 1
fi

# Helper to load nvm if present
load_nvm() {
  if [[ -z "${NVM_DIR:-}" ]]; then
    export NVM_DIR="$HOME/.nvm"
  fi
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
  fi
}

# 2) Check Node & npm
NODE_VERSION_STR=$(node -v 2>/dev/null || echo "")
if [[ -z "$NODE_VERSION_STR" ]]; then
  echo "Node.js not found. We'll install nvm + Node ${REQUIRED_NODE_MAJOR}.x."
  # Install nvm
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  load_nvm
  nvm install "${REQUIRED_NODE_MAJOR}"
  nvm use "${REQUIRED_NODE_MAJOR}"
else
  echo "Detected Node.js: ${NODE_VERSION_STR}"
  NODE_MAJOR=$(echo "$NODE_VERSION_STR" | sed 's/^v//' | cut -d. -f1)
  if (( NODE_MAJOR < REQUIRED_NODE_MAJOR )); then
    echo "Node.js major version is ${NODE_MAJOR}, but Codex works best with >= ${REQUIRED_NODE_MAJOR}."
    echo "Installing Node ${REQUIRED_NODE_MAJOR}.x via nvm (non-destructive for system packages)."
    if ! command -v nvm &>/dev/null; then
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    fi
    load_nvm
    nvm install "${REQUIRED_NODE_MAJOR}"
    nvm use "${REQUIRED_NODE_MAJOR}"
    NODE_VERSION_STR=$(node -v)
    echo "Now using Node.js ${NODE_VERSION_STR}"
  else
    echo "Node.js >= ${REQUIRED_NODE_MAJOR} already installed."
  fi
fi

# Ensure npm exists
if ! command -v npm &>/dev/null; then
  echo "npm command not found even though Node is installed."
  echo "Please ensure npm is installed or available for this Node version, then re-run."
  exit 1
fi

echo "npm version: $(npm -v)"

# 3) Install Codex CLI
echo
echo "=== Installing Codex CLI globally with npm ==="
npm install -g @openai/codex

# Ensure codex is on PATH
if ! command -v codex &>/dev/null; then
  echo "WARNING: 'codex' is not on your PATH even after install."
  PREFIX=$(npm config get prefix)
  echo "Global npm prefix is: $PREFIX"
  echo "Try adding the following to your shell config (e.g. ~/.bashrc):"
  echo "  export PATH=\"\$PATH:${PREFIX}/bin\""
  echo "Then open a new terminal and run 'codex --version'."
  exit 1
fi

echo "Codex CLI version: $(codex --version)"

# 4) Authentication
echo
echo "=== Authentication setup ==="
if codex login status &>/dev/null; then
  echo "Codex already has valid credentials (login status OK)."
else
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    echo "OPENAI_API_KEY detected. Logging in with API key..."
    printenv OPENAI_API_KEY | codex login --with-api-key
    if codex login status &>/dev/null; then
      echo "Successfully authenticated Codex using API key."
    else
      echo "ERROR: codex login with API key did not succeed. Please check your OPENAI_API_KEY."
      exit 1
    fi
  else
    echo "No existing login detected and OPENAI_API_KEY is not set."
    echo "You will need to log in using your ChatGPT account manually:"
    echo "  1) Run:  codex"
    echo "  2) Follow the browser-based sign-in flow (ChatGPT Plus/Pro/Business/Edu/Enterprise)."
  fi
fi

# 5) Optional smoke test
echo
echo "=== Running a simple Codex exec smoke test (read-only sandbox) ==="
codex --sandbox read-only exec \
  "Print 'Codex CLI is working on this Linux machine' and then list the files in the current directory."

echo
echo "=== Done. Codex CLI is installed, configured, and tested. ==="
echo "Tip: customize ~/.codex/config.toml (model, sandbox_mode, approval_policy, etc.) to fit your workflow."
