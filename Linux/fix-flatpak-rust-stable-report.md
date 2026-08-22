# Technical Report: `fix-flatpak-rust-stable.sh`

## 1. Executive summary

`fix-flatpak-rust-stable.sh` is a Bash utility for repairing Flatpak installations affected by a failed update of the Freedesktop Rust stable SDK extension. It targets the exact runtime reference:

```text
runtime/org.freedesktop.Sdk.Extension.rust-stable/x86_64/25.08
```

The script repairs both the per-user and system-wide Flatpak installations by default. It validates and refreshes the Flathub remote, runs metadata and repository repair operations, retries the problematic runtime update, and performs a complete Flatpak update. When Flathub returns HTTP 404 for the target reference, the script can apply a temporary, exact-reference mask so unrelated Flatpak updates can continue.

The workaround is local and reversible. A mask does not repair a missing object on Flathub; it prevents Flatpak from repeatedly requesting that object until the remote repository is fixed.

## 2. Objective and scope

### Objective

The operational objectives are to:

1. Repair local Flatpak metadata and repository consistency.
2. Ensure that the `flathub` remote exists, is enabled, and uses the expected OSTree endpoint.
3. Attempt to update the Rust stable SDK extension explicitly.
4. Distinguish a remote HTTP 404 from other update failures.
5. Mask only the affected runtime when a 404 is confirmed.
6. Allow all other Flatpak applications and runtimes to update.
7. Preserve enough state to inspect the run and restore remote configuration.

### Scope

The script manages the `flathub` remote and the target Rust SDK extension in the user and/or system Flatpak installation. It does not modify application source code, reinstall the operating system, or repair a missing object on the Flathub server. The default system-wide path requires `sudo` privileges.

## 3. Script structure

The script is organized into the following functional areas:

| Area | Main functions | Responsibility |
|---|---|---|
| Configuration | Global variables and flags | Defines the target ref, remote URLs, state locations, and execution modes. |
| Help and diagnostics | `usage`, `log`, `die`, `on_error` | Documents options and provides timestamped output and error guidance. |
| Command execution | `quote_cmd`, `run`, `run_capture` | Logs commands, supports dry-run behavior, and captures update output. |
| Resumable execution | `step_done`, `mark_step_done`, `step` | Records completed operations and skips them on a repeated run with the same run state. |
| Preconditions | `need_command`, `confirm`, `prepare` | Checks required tools, prepares state directories, and obtains a sudo credential. |
| State backup and recovery | `backup_state`, `rollback` | Saves remote configuration and inventory data, then restores remote config and script-added masks when requested. |
| Remote management | `remote_exists_*`, `ensure_*_remote` | Detects, adds, or modifies Flathub for each Flatpak scope. |
| Repair | `repair_user`, `repair_system` | Refreshes appstream metadata and executes Flatpak repair in dry-run and active modes. |
| Target update and masking | `update_*_ref_or_mask`, `handle_update_failure`, `mask_*`, `unmask_*` | Updates the target ref, masks it on HTTP 404, or fails on other errors. |
| Final update | `final_update_user`, `final_update_system` | Updates all Flatpak content and optionally removes unused refs. |
| Verification | `verify` | Logs remotes, masks, and installed Rust extension entries. |
| Argument dispatch | The final `while` loop and main flow | Parses options, rejects conflicting modes, and executes the selected workflow. |

## 4. Implementation approach

### 4.1 Safety and shell behavior

The script starts with `#!/usr/bin/env bash` and enables:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

This makes unset variables, failed commands, and pipeline failures visible. An `ERR` trap reports the approximate failing line and points to the run log and rollback command.

The `run` wrapper logs every command before executing it. The `run_capture` wrapper additionally redirects command output to a file, appends it to the main log, and returns the original command status. This is important for identifying HTTP 404 responses from the target update.

### 4.2 State, logs, and resumability

State is stored below:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/flatpak-rust-stable-fix/
```

Each invocation receives a timestamped directory:

```text
run-YYYYMMDD-HHMMSS/
├── run.log
├── steps/
├── user-ref-update.log       # created when user-scope target update runs
├── system-ref-update.log     # created when system-scope target update runs
└── added-masks.tsv           # created when this script adds masks
```

`latest-run`, `latest-backup`, and `latest-added-masks` are symbolic links that make the most recent state easy to locate. Step marker files, such as `user_repair.done`, prevent completed operations from being repeated during a resumed run.

### 4.3 Backup strategy

Before changing Flatpak state, `backup_state` records:

- user and system remote details;
- installed Flatpak application inventories;
- user and system masks;
- Flatpak history;
- the user repository configuration, when present;
- the system repository configuration, when present.

The backup is primarily a configuration and diagnostic snapshot. Rollback restores repository configuration files and removes masks recorded as added by the latest run. It does not restore package versions, application data, or every Flatpak operation performed after the backup.

### 4.4 User and system scopes

The default execution processes both scopes. Scope-specific functions consistently use either:

```bash
flatpak --user ...
sudo flatpak --system ...
```

`--user-only` excludes system operations; `--system-only` excludes user operations. The script rejects using both flags together.

### 4.5 Flathub remote normalization

For each selected scope, the script checks whether a remote named `flathub` exists.

- If it exists, `remote-modify` sets the OSTree URL to `https://dl.flathub.org/repo/`, enables the remote, and enables metadata updates.
- If it does not exist, `remote-add --if-not-exists` creates it from `https://dl.flathub.org/repo/flathub.flatpakrepo`.

This ensures that subsequent metadata refresh and repair operations use the intended remote.

### 4.6 Repair and update sequence

For each selected scope, the normal sequence is:

1. Ensure the Flathub remote.
2. Refresh Flathub appstream metadata.
3. Run `flatpak repair --dry-run` to inspect repair candidates.
4. Run active `flatpak repair`.
5. Check whether the target Rust ref is installed.
6. Attempt a noninteractive update of the target ref.
7. If the target update succeeds, continue.
8. If the output contains an HTTP 404 signature, optionally mask the exact ref and continue.
9. If the failure is not an HTTP 404, stop and direct the user to the captured log.
10. Update all Flatpak content.
11. Optionally uninstall unused refs.

The target ref is skipped when it is not installed in the current scope. This avoids treating an absent runtime as an error.

### 4.7 HTTP 404 handling

The script searches captured output case-insensitively for:

```text
HTTP 404
Server returned HTTP 404
status code 404
```

When found, it masks only:

```text
runtime/org.freedesktop.Sdk.Extension.rust-stable/x86_64/25.08
```

The mask is applied only if it does not already exist. Newly added masks are recorded in a tab-separated file containing the scope and ref. This lets `--rollback` remove only masks created by the script, while `--unmask` removes the target mask directly from selected scopes.

With `--no-mask`, an HTTP 404 is treated as fatal instead of applying the workaround. Any non-404 update failure is fatal in all modes.

### 4.8 Dry-run behavior

`--dry-run` causes commands routed through `run` and `run_capture` to be logged without executing their state-changing command. It still creates the run directory and log, checks required commands, and—unless `--user-only` is selected—requests sudo authentication in `prepare`. Therefore, it should be viewed as a command preview rather than a completely side-effect-free execution.

## 5. Application and expected results

The script is useful when the Flatpak GUI or CLI repeatedly fails while updating the Freedesktop Rust stable SDK extension, particularly when the failure is an HTTP 404 from Flathub. The expected outcomes are:

- local Flatpak repair completes or reports a specific failure;
- Flathub is available and enabled in the selected scope;
- the Rust extension updates successfully, or is temporarily masked only after a confirmed 404;
- unrelated Flatpak content can update;
- logs and backups remain available under the state directory;
- verification output shows current remotes, masks, and installed Rust extension entries.

The workaround should be temporary. After Flathub publishes or replicates the missing object, remove the mask and retry the update.

## 6. Use guide

### Prerequisites

- Bash.
- Flatpak installed and available in `PATH`.
- `awk`, `grep`, `cp`, `mkdir`, `tee`, and `readlink`.
- `sudo` access for system-wide operations.
- Network access to Flathub when refreshing metadata or updating.

Make the script executable if necessary:

```bash
chmod +x /home/fernandoavanzo/Projects/helpers-bash-scripts/Linux/fix-flatpak-rust-stable.sh
```

### General command

Run the default repair for both user and system installations:

```bash
/home/fernandoavanzo/Projects/helpers-bash-scripts/Linux/fix-flatpak-rust-stable.sh
```

The script asks for confirmation unless `--yes` or `--dry-run` is supplied.

### Command examples

Preview the planned operations:

```bash
./fix-flatpak-rust-stable.sh --dry-run
```

Run without an interactive confirmation:

```bash
./fix-flatpak-rust-stable.sh --yes
```

Repair only the user installation:

```bash
./fix-flatpak-rust-stable.sh --user-only
```

Repair only the system installation:

```bash
./fix-flatpak-rust-stable.sh --system-only
```

Include removal of unused Flatpak refs after a successful update:

```bash
./fix-flatpak-rust-stable.sh --include-unused
```

Do not automatically mask the target when an HTTP 404 is detected:

```bash
./fix-flatpak-rust-stable.sh --no-mask
```

Remove the target mask after Flathub has been fixed:

```bash
./fix-flatpak-rust-stable.sh --unmask
flatpak update
```

Remove the target mask only from one scope:

```bash
./fix-flatpak-rust-stable.sh --unmask --user-only
./fix-flatpak-rust-stable.sh --unmask --system-only
```

Restore backed-up remote configuration and remove masks recorded by the last run:

```bash
./fix-flatpak-rust-stable.sh --rollback
```

Display the built-in help:

```bash
./fix-flatpak-rust-stable.sh --help
```

### Parameters

| Parameter | Effect |
|---|---|
| `--yes`, `-y` | Suppresses the confirmation prompt. |
| `--include-unused` | Runs `flatpak uninstall --unused -y` for each selected scope after the general update. |
| `--user-only` | Operates only on the per-user Flatpak installation. |
| `--system-only` | Operates only on the system-wide Flatpak installation. Requires sudo for normal repair/update operations. |
| `--dry-run` | Logs planned commands without executing commands routed through the script’s execution wrappers. |
| `--no-mask` | Fails on a detected HTTP 404 instead of applying the temporary mask. |
| `--unmask` | Removes the exact Rust stable extension mask from selected scopes and exits. |
| `--rollback` | Restores available remote configuration backups and removes masks recorded by the latest run, then exits. |
| `--help`, `-h` | Prints usage and behavior information, then exits. |

`--user-only` and `--system-only` are mutually exclusive. `--rollback` and `--unmask` are also mutually exclusive.

### Logs and recovery locations

By default, inspect the latest run with:

```bash
ls -la "${XDG_STATE_HOME:-$HOME/.local/state}/flatpak-rust-stable-fix/latest-run"
less "${XDG_STATE_HOME:-$HOME/.local/state}/flatpak-rust-stable-fix/latest-run/run.log"
```

The latest backup is available through `latest-backup`. If a run stops after changing state, use the rollback command shown in the error output, then inspect the log before retrying.

## 7. Operational considerations and limitations

1. A 404 is evidence that the requested remote object is unavailable at the server/CDN at the time of the request; local repair cannot recreate it.
2. The mask is exact and reversible, but it can prevent the Rust extension from receiving updates until it is removed.
3. `--rollback` restores remote configuration files and script-added masks; it is not a full system snapshot restore.
4. `--include-unused` can remove refs that are no longer required. Use it only when that cleanup is intended.
5. The state directory can contain inventories and command output. Protect it according to the sensitivity of the local system.
6. The script was syntax-validated with `bash -n`; actual Flatpak changes require an appropriate local Flatpak installation, permissions, and network availability.

## 8. Conclusion

The script combines standard Flatpak repair operations with targeted diagnosis and reversible containment of a known remote-object failure. Its separation of user and system scopes, command logging, backups, step markers, and explicit unmask/rollback paths make it suitable for controlled recovery of the affected Rust SDK extension while minimizing disruption to the rest of the Flatpak environment.
