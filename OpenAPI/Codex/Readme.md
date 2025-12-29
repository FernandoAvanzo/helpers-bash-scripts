# Codex API OPEN AI

## Install Guide

Here’s a Linux-focused, end-to-end guide plus an automation script for installing, configuring, and testing the Codex CLI.

---

## 1. What you’re installing

Codex CLI is OpenAI’s local coding agent that runs in your terminal and can read, modify, and run code on your machine. It officially supports macOS and **Linux**.([OpenAI Developers][1])

You’ll interact with it via the `codex` command after installing the npm package `@openai/codex`.([DataCamp][2])

---

## 2. Prerequisites on Linux

### 2.1. OS

* Any modern Linux distro (Ubuntu 20.04+/Debian 10+/Fedora/etc.) is fine.
* Official docs just say Codex CLI supports **macOS and Linux**; Windows users are told to use WSL.([OpenAI Developers][1])

### 2.2. Node.js & npm

Codex CLI is distributed as a Node package and is designed to run best on **Node.js 22 or newer**: multiple recent guides and community threads explicitly note that upgrading to Node 22+ fixes install/runtime issues and that Codex is tested on Node 22+.([Medium][3])

Check your current versions:

```bash
node -v
npm -v
```

If you see something like:

* `v22.x.y` for Node → perfect.
* Command not found or Node < 22 → install/upgrade Node (see section 3).

(The npm docs also use `node -v` and `npm -v` as the standard way to verify installation.([docs.npmjs.com][4]))

### 2.3. Git & common tools

Codex often runs commands like `git`, `bash`, `ls`, `sed`, `python` inside its sandbox when working with your repo. Several GitHub issues show failures when basic tools aren’t installed (e.g., `bash: python: command not found`, `bash: sed: command not found`).([GitHub][5])

Install them (Debian/Ubuntu example):

```bash
sudo apt update
sudo apt install -y git curl build-essential python3
```

### 2.4. OpenAI account / auth options

Codex can authenticate in two main ways:([OpenAI Developers][1])

1. **ChatGPT sign-in (recommended)**

    * Requires a paid ChatGPT plan: **Plus, Pro, Business, Edu, or Enterprise**.([OpenAI Developers][1])

2. **OpenAI API key**

    * Requires available **API credits** on the OpenAI platform and an API key created at the API dashboard.([OpenAI Developers][1])

You can switch between these later, so don’t stress about picking one permanently.

---

## 3. Installing / upgrading Node.js & npm (if needed)

The most flexible, cross-distro way is to use **nvm** (Node Version Manager).([GitHub][6])

### 3.1. Install nvm

```bash
# Install nvm (from the official repo)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# Load nvm in your current shell
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

(Next time you open a terminal, nvm will be loaded automatically if you followed its installer message.)

### 3.2. Install Node.js 22

```bash
# Install an LTS v22.x and make it default in this shell
nvm install 22
nvm use 22

# Verify versions
node -v
npm -v
```

Recent tutorials show examples like `nvm install v22.16.0` and using `nvm list` to confirm the active version.([DigitalOcean][7])

---

## 4. Installing the Codex CLI

Official quickstart says to install Codex CLI via npm (or Homebrew).([OpenAI Developers][1])

On Linux, npm is the simplest:

```bash
# With Node 22 active
npm install -g @openai/codex

# Verify installation
codex --version
```

If you see **`npm WARN EBADENGINE`** about unsupported engine, that’s typically a Node version mismatch. Articles show that with Node ≥ 22 this warning disappears and Codex works correctly.([Medium][3])

> 🔧 **If `codex` is “command not found” but npm install succeeded**
> Your global npm bin directory isn’t on your `$PATH`. Find it and add it:
>
> ```bash
> npm bin -g          # or: npm config get prefix
> # Example output: /home/you/.nvm/versions/node/v22.16.0/bin
>
> echo 'export PATH="$PATH:/home/you/.nvm/versions/node/v22.16.0/bin"' >> ~/.bashrc
> source ~/.bashrc
> ```
>
> npm’s own docs call out that Node & npm must be installed, and global binaries live in the npm prefix’s `bin` dir.([docs.npmjs.com][4])

---

## 5. Authenticating & configuring Codex CLI

### 5.1. Default ChatGPT login (OAuth in browser)

From the quickstart: running `codex` for the first time launches the CLI and prompts you to authenticate; recommended is ChatGPT sign-in.([OpenAI Developers][1])

1. Run:

   ```bash
   codex
   ```

2. The CLI will open your browser for ChatGPT OAuth. Log in with your **Plus/Pro/Business/Edu/Enterprise** account.([OpenAI Developers][1])

3. When the browser says it’s done, go back to the terminal; Codex is now authenticated.

4. Check status:

   ```bash
   codex login status
   # exit code 0 ⇒ logged in
   ```

The CLI reference states that `codex login` authenticates with ChatGPT OAuth, device auth, or an API key, and `codex login status` prints the current mode and exits 0 when logged in.([OpenAI Developers][8])

> **Headless / no browser?**
> On headless servers it will fall back to a *device auth* flow: it prints a URL and a one-time code; open that URL from any machine where you can log into ChatGPT, enter the code, approve, and Codex on the server will complete login.([OpenAI Developers][8])

### 5.2. Using an OpenAI API key instead

From the “Using Codex with your API key” section in the quickstart:([OpenAI Developers][1])

1. **Ensure API credits** in your OpenAI platform account.([OpenAI Developers][1])

2. Create an API key at the **API keys dashboard** on the platform.([OpenAI Developers][1])

3. Export it in your shell:

   ```bash
   export OPENAI_API_KEY="sk-...your-key-here..."
   ```

4. Set Codex to prefer API-key auth (two options):

   **Option A – via config file**

    * Create or edit `~/.codex/config.toml` (this is the shared config for CLI & IDE).([OpenAI Developers][9])
    * Add:

      ```toml
      preferred_auth_method = "apikey"
      ```

   Codex’s configuration page describes this central config file and shows examples of top-level options like `model`, `approval_policy`, `sandbox_mode`, and provider settings.([OpenAI Developers][9])

   **Option B – via login command**

    * Pipe the key into `codex login --with-api-key`:

      ```bash
      printenv OPENAI_API_KEY | codex login --with-api-key
      codex login status
      ```

   The CLI reference shows `--with-api-key` reads a key from stdin (example uses `printenv OPENAI_API_KEY | codex login --with-api-key`).([OpenAI Developers][8])

You can switch back to ChatGPT login later by setting `preferred_auth_method = "chatgpt"` in `config.toml` or using `codex --config preferred_auth_method="chatgpt"`.([OpenAI Developers][1])

---

## 6. Optional: basic config (`config.toml`)

Codex’s config doc describes `~/.codex/config.toml` as the central configuration for both the CLI and IDE extension.([OpenAI Developers][9])

A minimal, sane starting config:

```toml
# ~/.codex/config.toml

# Use a stable, well-supported model
model = "gpt-4o"

# How cautious Codex should be about running commands:
# untrusted | on-failure | on-request | never
approval_policy = "untrusted"

# Sandbox levels: read-only | workspace-write | danger-full-access
sandbox_mode = "workspace-write"

# (Optional) prefer API key or ChatGPT auth
# preferred_auth_method = "apikey"
# preferred_auth_method = "chatgpt"
```

Docs also show you can tweak `model_reasoning_effort`, define multiple profiles under `[profiles.<name>]`, and configure custom providers like Ollama or Azure via a `[model_providers.*]` section.([OpenAI Developers][9])

---

## 7. Example: test that Codex CLI is working

### 7.1. Quick non-interactive smoke test

Run:

```bash
codex --sandbox read-only exec "Print 'Codex CLI is working on Linux' and then list the files in the current directory using bash."
```

* `codex exec PROMPT` runs a one-off, non-interactive task.([OpenAI Developers][8])
* `--sandbox read-only` keeps Codex from editing files while you test.([OpenAI Developers][9])

You should see Codex reason about the request and run commands (like `ls -la`) inside its sandbox.

### 7.2. Interactive TUI

Run:

```bash
codex
```

This launches the interactive TUI.([OpenAI Developers][1])

Try something like:

> “Scan this repo, list the main modules, and suggest a refactor plan in bullet points.”

---

## 8. Common troubleshooting notes

### 8.1. `npm WARN EBADENGINE` / “Unsupported engine”

* **Symptom:** During `npm install -g @openai/codex`, you get `npm WARN EBADENGINE` or “unsupported engine”.
* **Cause:** Codex’s package engines declaration expects a recent Node; using older Node triggers the warning.
* **Fix:** Upgrade to **Node 22+** with nvm or your distro’s packages; multiple Codex install guides note that upgrading to Node 22 resolves these issues.([Medium][3])

### 8.2. `codex: command not found`

* **Symptom:** After `npm install -g @openai/codex`, `codex` is not recognized.
* **Cause:** Global npm `bin` directory not on `$PATH`.
* **Fix:** Find it with `npm bin -g` or `npm config get prefix`, then add `/that/path/bin` to your shell’s PATH. npm docs explain that global executables live under the npm prefix’s `bin`.([docs.npmjs.com][4])

### 8.3. Login keeps failing

* Ensure you have a valid **ChatGPT Plus/Pro/Business/Edu/Enterprise** plan if you’re using ChatGPT login.([OpenAI Developers][1])
* Run `codex login status` to see if Codex thinks it’s authenticated.([OpenAI Developers][8])
* If on a headless server, watch for device-auth instructions (URL + code) instead of a browser popup.([OpenAI Developers][8])
* For API key mode, double-check `OPENAI_API_KEY` and `preferred_auth_method="apikey"` in `config.toml`.([OpenAI Developers][1])

### 8.4. Codex can’t run common commands (e.g., `python`, `sed`, `cat`)

Issues report `bash: python: command not found` or similar when Codex tries to inspect files.([GitHub][5])

* Install the missing tools (`sudo apt install python3 sed coreutils ripgrep`, etc.).
* Make sure they’re on your `$PATH`.
* Remember Codex executes inside a sandbox; see the config docs for `sandbox_mode` and workspace write/network access toggles.([OpenAI Developers][9])

### 8.5. “Codex works only on Node 22, breaks other projects”

If you use **nvm** to switch Node versions per project, you might see Codex “disappear” when switching away from Node 22 (because global npm packages are per-Node). A GitHub issue discusses exactly this pain point.([GitHub][10])

Workarounds:

* Keep Node 22 as your **default** (`nvm alias default 22`) and let projects that need older versions use `nvm use 18`/`20` only when you’re inside them.
* Or use `npx codex` from a directory where Node 22 is active.
* Or install Codex globally for each Node version you care about (less ideal).

### 8.6. Sandbox / permission issues

Some users report tasks failing silently or Codex asking for repeated approvals due to sandbox restrictions; others fix recurring errors by using `--full-auto` and allowing out-of-sandbox execution for specific commands.([Reddit][11])

* Check `sandbox_mode` in `config.toml` (`read-only`, `workspace-write`, or `danger-full-access`).([OpenAI Developers][9])
* For debugging in a safe test repo, you can temporarily use:

  ```bash
  codex --sandbox workspace-write
  ```

  or, in truly disposable environments, `danger-full-access` (not recommended on sensitive machines).

---

## 9. Automation script: wrap everything

Below is a **bash script** that:

1. Ensures you’re on Linux.
2. Ensures Node 22+ and npm are available (optionally installs nvm + Node 22).
3. Installs Codex CLI globally.
4. Logs in with API key if `OPENAI_API_KEY` is set, otherwise tells you to log in via ChatGPT.
5. Runs a small smoke test.

> ⚠️ Review before running, especially the part that installs nvm and a new Node version. Save it as `install_codex_cli.sh` and run with `bash install_codex_cli.sh`.

```bash
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
```

---

## 10. Good reference links

For deeper reading and to keep up with changes:

* **Codex Quickstart (official docs)** – install, auth, CLI/IDE/cloud overview, API key usage.([OpenAI Developers][1])
* **Codex CLI reference** – detailed command-line flags for `codex`, `codex exec`, `codex login`, `codex mcp`, etc.([OpenAI Developers][8])
* **Codex configuration guide** – `~/.codex/config.toml` options for models, sandbox, features, MCP, telemetry.([OpenAI Developers][9])
* **Codex GitHub repo** – open-source CLI source, issues, discussions, and changelog.([GitHub][12])
* **Node.js & npm install docs** – official guidance on verifying and installing Node & npm (including version managers).([docs.npmjs.com][4])

If you want, next we can tailor `config.toml` specifically for your typical stack (languages, frameworks, DB drivers) so Codex is “pre-tuned” for your projects.

[1]: https://developers.openai.com/codex/quickstart/ "Quickstart"
[2]: https://www.datacamp.com/tutorial/open-ai-codex-cli-tutorial?utm_source=chatgpt.com "OpenAI Codex CLI Tutorial"
[3]: https://medium.com/dyfrad/getting-started-with-openai-codex-cli-on-macos-a-hands-on-guide-e8a9146991a5?utm_source=chatgpt.com "Getting Started with OpenAI Codex CLI on macOS"
[4]: https://docs.npmjs.com/downloading-and-installing-node-js-and-npm/?utm_source=chatgpt.com "Downloading and installing Node.js and npm"
[5]: https://github.com/openai/codex/issues/3041?utm_source=chatgpt.com "Cannot execute any bash commands · Issue #3041"
[6]: https://github.com/nvm-sh/nvm?utm_source=chatgpt.com "nvm-sh/nvm: Node Version Manager - POSIX-compliant ..."
[7]: https://www.digitalocean.com/community/tutorials/how-to-install-node-js-on-ubuntu-22-04?utm_source=chatgpt.com "How to Install Node.js on Ubuntu (Step-by-Step Guide)"
[8]: https://developers.openai.com/codex/cli/reference/ "Codex CLI reference"
[9]: https://developers.openai.com/codex/local-config "Configuring Codex"
[10]: https://github.com/openai/codex/issues/164?utm_source=chatgpt.com "relax node 22 or newer requirement #164 - openai/codex"
[11]: https://www.reddit.com/r/ChatGPTCoding/comments/1n2gxti/getting_same_error_everytime_with_codex_cli/?utm_source=chatgpt.com "Getting same error everytime with codex CLI"
[12]: https://github.com/openai/codex "GitHub - openai/codex: Lightweight coding agent that runs in your terminal"

