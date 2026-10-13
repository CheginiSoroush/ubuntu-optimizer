# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/selfupdate.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Updates the toolkit itself (`uo --self-update`) and keeps it current
#  automatically (`selfupdate_auto_check` — called at every 'uo' startup:
#  a TTL-cached version check that offers to apply a newer release first
#  and re-execs the fresh code; opt out with --no-update / UO_AUTO_UPDATE=0).
#  Two installation kinds are supported, detected automatically:
#
#    1. git checkout   — .git exists beside the script → version check against
#                        the remote default branch, then `git pull --ff-only`
#                        (a dirty tree is warned about and confirmed first).
#    2. static copy    — no .git → the branch archive tarball is downloaded,
#                        verified with `bash -n` BEFORE anything is touched,
#                        the current files are backed up and the new tree is
#                        swapped in with atomic renames (a running bash keeps
#                        reading its own inode, so in-place writes are avoided).
#
#  The remote version is read from lib/common.sh on raw.githubusercontent.com
#  (main first, then master) — the same file that holds the local
#  SCRIPT_VERSION, so both sides always speak the same language. Updates are
#  accepted from the official repository only; the source is not configurable.
#  A failed verification after a static update restores the backup
#  automatically, and every path ends with a rollback hint.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Constants ──────────────────────────────────────────────────────────────────
readonly SELFUPDATE_REPO="CheginiSoroush/ubuntu-optimizer"
readonly SELFUPDATE_BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-optimizer/selfupdate-backups"
# Startup-check state: the TTL cache for the automatic update check and the
# mode flags shared with the two update flows below.
readonly SU_AUTO_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ubuntu-optimizer/autoupdate.check"
SU_REMOTE_VERSION=""
SU_REMOTE_BRANCH=""
SU_CACHED_TS=""
SU_CACHED_VERSION=""
SU_CACHED_BRANCH=""
SU_QUIET=0    # 1 = fetch silently (the startup check must stay invisible)
SU_AUTO=0     # 1 = apply on behalf of the auto check (prompts already handled)

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_version_newer() — dotted-version comparison (candidate > current)
#
# Uses `sort -V` (GNU coreutils — part of every Ubuntu install), so 7.10
# correctly sorts above 7.9 where a plain string compare would not.
#
# Arguments: $1 — candidate version (e.g. the remote one)
#            $2 — current version (e.g. SCRIPT_VERSION)
# Returns:   0 — candidate is strictly newer
#            1 — candidate is equal to or older than current
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_version_newer() {
    local candidate="$1" current="$2"
    [ -z "$candidate" ] || [ -z "$current" ] && return 1
    [ "$candidate" = "$current" ] && return 1
    [ "$(printf '%s\n%s\n' "$candidate" "$current" | sort -V | head -n 1)" = "$current" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_fetch_remote_version() — read the remote SCRIPT_VERSION
#
# Fetches lib/common.sh from raw.githubusercontent.com (default-branch
# detection: main first, then master) with the same curl timeouts the GitHub
# module uses and extracts the SCRIPT_VERSION line. GH_TOKEN/GITHUB_TOKEN are
# honoured for raw requests too (a fine-grained token may be required for
# private forks; the public repository works anonymously).
#
# Globals:   SELFUPDATE_REPO (read)
#            SU_REMOTE_VERSION, SU_REMOTE_BRANCH — written
# Arguments: none
# Returns:   0 — remote version parsed
#            1 — network failure or no version line on either branch
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_fetch_remote_version() {
    SU_REMOTE_VERSION=""
    SU_REMOTE_BRANCH=""

    if ! command -v curl > /dev/null 2>&1; then
        # Quiet mode (the startup check) never installs anything — it gives up
        [ "${SU_QUIET:-0}" = "1" ] && return 1
        info "Installing curl..."
        sudo apt install -y curl > /dev/null 2>&1 || { failure "Failed to install curl."; return 1; }
    fi

    local branch raw auth=()
    if [ -n "${GH_TOKEN:-}" ]; then
        auth=(-H "Authorization: Bearer ${GH_TOKEN}")
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    for branch in main master; do
        raw=$(curl -fsSL --connect-timeout "${SU_CONNECT_TIMEOUT:-15}" --max-time "${SU_MAX_TIMEOUT:-30}" "${auth[@]}" \
            "https://raw.githubusercontent.com/${SELFUPDATE_REPO}/${branch}/lib/common.sh" 2>/dev/null) || continue
        SU_REMOTE_VERSION=$(sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)".*/\1/p' <<< "$raw")
        if [ -n "$SU_REMOTE_VERSION" ]; then
            SU_REMOTE_BRANCH="$branch"
            return 0
        fi
    done

    [ "${SU_QUIET:-0}" = "1" ] && return 1
    failure "Could not read the remote version from raw.githubusercontent.com."
    info "Check your internet connection (or GH_TOKEN) and try again."
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_cache_read() — load the last startup-check result
#
# Reads the single-line cache written by selfupdate_cache_write:
#   "<unix-ts>\t<version>\t<branch>". Any malformed or missing file is a
#   clean miss (the caller then goes to the network). All three fields are
#   reset first, so a failed read never leaves stale state behind.
#
# Globals:   SU_AUTO_CACHE (read)
#            SU_CACHED_TS, SU_CACHED_VERSION, SU_CACHED_BRANCH — written
# Arguments: none
# Returns:   0 — a well-formed cache line was loaded
#            1 — missing/unreadable/malformed cache (fields emptied)
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_cache_read() {
    SU_CACHED_TS=""
    SU_CACHED_VERSION=""
    SU_CACHED_BRANCH=""
    [ -f "$SU_AUTO_CACHE" ] || return 1
    local line
    line=$(head -n 1 "$SU_AUTO_CACHE" 2>/dev/null) || return 1
    SU_CACHED_TS="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    SU_CACHED_VERSION="${rest%%$'\t'*}"
    SU_CACHED_BRANCH="${rest#*$'\t'}"
    [[ "$SU_CACHED_TS" =~ ^[0-9]+$ ]] || { SU_CACHED_TS=""; SU_CACHED_VERSION=""; SU_CACHED_BRANCH=""; return 1; }
    [ -n "$SU_CACHED_VERSION" ] || return 1
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_cache_write() — persist a startup-check result atomically
#
# Writes "<unix-ts>\t<version>\t<branch>" via a temp file + rename, so a
# concurrent reader never sees a half-written line. Failures are silently
# ignored — the cache is an optimization, never a requirement.
#
# Globals:   SU_AUTO_CACHE (read)
# Arguments: $1 — unix timestamp of the check
#            $2 — remote version seen
#            $3 — remote branch the version came from
# Returns:   0 — written; 1 — the cache directory/file was not writable
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_cache_write() {
    local ts="$1" ver="$2" branch="$3"
    local dir
    dir=$(dirname -- "$SU_AUTO_CACHE")
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s\t%s\t%s\n' "$ts" "$ver" "$branch" > "${SU_AUTO_CACHE}.tmp" 2>/dev/null || return 1
    mv -f "${SU_AUTO_CACHE}.tmp" "$SU_AUTO_CACHE" 2>/dev/null
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_reexec() — swap this process for the freshly updated code
#
# Called only after a successful automatic update: re-runs the main script
# (now the new version on disk) with the original arguments, guarded by
# UO_AUTO_UPDATE_REEXEC so the new run skips the check and can never loop.
# Factored into a function so tests can stub the exec away.
#
# Globals:   SCRIPT_DIR (read)
# Arguments: $@ — the original CLI arguments, passed through verbatim
# Returns:   never (exec replaces the process)
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_reexec() {
    info "Restarting with the new version..."
    exec env UO_AUTO_UPDATE_REEXEC=1 "$SCRIPT_DIR/ubuntu-optimizer.sh" "$@"
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_auto_check() — automatic update check at every 'uo' startup
#
# The whole point: `uo` keeps itself current. Before any real work runs, the
# remote version is resolved (TTL-cached under SU_AUTO_CACHE — default 300s,
# UO_UPDATE_CHECK_TTL seconds overrides, 0 = check every run; short 3s/6s
# timeouts keep an offline start snappy). When a strictly newer version
# exists:
#   · interactive run  → one banner + one y/n question, then the update
#                        applies and the process re-execs into the new code
#                        with the original arguments — the user never has to
#                        think about versions again;
#   · -y (unattended)  → the update applies straight away, promptless;
#   · machine modes (--json / --output) or a pipe → a one-line stderr notice,
#                        stdout stays pure, nothing is downloaded.
# Every failure path (offline, rate limit, declined, failed download) falls
# through to the normal run — the check can never block real work.
#
# Opt-outs (any one is enough): --no-update flag · UO_AUTO_UPDATE=0 ·
# a queued --self-update (the manual flow owns its check) · --timer-tick
# (scheduled monitor runs stay silent) · the re-exec guard.
#
# Globals:   SCRIPT_DIR, SCRIPT_VERSION, ASSUME_YES, JSON_MODE, OUTPUT_FILE,
#            AUTO_UPDATE, UO_AUTO_UPDATE, UO_UPDATE_CHECK_TTL, CLI_ACTIONS (read)
#            SU_* (written through the shared helpers)
# Arguments: $@ — the original CLI arguments (reused verbatim on re-exec)
# Returns:   0 — up to date, skipped, declined or updated (re-exec never returns)
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_auto_check() {
    # Just re-exec'd after an update — the fresh code runs, skip the check
    [ "${UO_AUTO_UPDATE_REEXEC:-}" = "1" ] && return 0
    # Opt-outs: --no-update (AUTO_UPDATE=0) and the environment switch
    [ "${AUTO_UPDATE:-1}" = "1" ] || return 0
    [ "${UO_AUTO_UPDATE:-1}" != "0" ] || return 0
    # The manual self-update and the scheduled monitor tick own their flows
    local act
    for act in ${CLI_ACTIONS[@]+"${CLI_ACTIONS[@]}"}; do
        case "${act%%|*}" in
            self_update_interactive|timer_tick) return 0 ;;
        esac
    done

    # Resolve the remote version — from the TTL cache when fresh, network otherwise
    local ttl="${UO_UPDATE_CHECK_TTL:-300}"
    [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=300
    local ver="" branch=""
    if selfupdate_cache_read && [ -n "$SU_CACHED_VERSION" ]; then
        local age=$(( $(date +%s) - SU_CACHED_TS ))
        [ "$age" -lt 0 ] && age=$((ttl + 1))    # clock jumped back — re-check
        if [ "$age" -lt "$ttl" ]; then
            ver="$SU_CACHED_VERSION"
            branch="$SU_CACHED_BRANCH"
        fi
    fi
    if [ -z "$ver" ]; then
        # Short timeouts + full silence: an offline start must stay snappy
        SU_QUIET=1 SU_CONNECT_TIMEOUT=3 SU_MAX_TIMEOUT=6 selfupdate_fetch_remote_version || return 0
        ver="$SU_REMOTE_VERSION"
        branch="$SU_REMOTE_BRANCH"
        selfupdate_cache_write "$(date +%s)" "$ver" "$branch"
    fi
    [ -z "$ver" ] && return 0
    [ "$ver" = "$SCRIPT_VERSION" ] && return 0
    if [ -n "$SCRIPT_VERSION" ] && ! selfupdate_version_newer "$ver" "$SCRIPT_VERSION"; then
        return 0    # a development checkout ahead of the remote — nothing to do
    fi

    # Machine-readable runs: a one-line stderr notice, stdout stays pure
    if [ "${JSON_MODE:-0}" = "1" ] || [ -n "${OUTPUT_FILE:-}" ]; then
        printf 'ℹ Update available: v%s → v%s — run: uo --self-update\n' "$SCRIPT_VERSION" "$ver" >&2
        return 0
    fi
    # Unattended runs that cannot answer a prompt: notice only
    if [ ! -t 0 ] && [ "${ASSUME_YES:-0}" != "1" ]; then
        printf 'ℹ Update available: v%s → v%s — run: uo --self-update\n' "$SCRIPT_VERSION" "$ver" >&2
        return 0
    fi

    printf '%s\n' "${BOLD}📦 A new version is available: v${SCRIPT_VERSION} → v${ver}${NC}"
    if [ "${ASSUME_YES:-0}" != "1" ]; then
        if ! confirm_action "Update the toolkit now, before starting?"; then
            info "Continuing with v$SCRIPT_VERSION — update later with: uo --self-update"
            return 0
        fi
    fi

    # Apply — the shared update functions skip their own prompts in auto mode
    local rc=0
    SU_AUTO=1
    if selfupdate_is_git_checkout; then
        selfupdate_update_git || rc=1
    else
        selfupdate_update_tarball || rc=1
    fi
    SU_AUTO=0
    if [ "$rc" -ne 0 ]; then
        warn "Continuing with v$SCRIPT_VERSION — the update did not complete."
        return 0
    fi
    # Swap this very process for the freshly installed code, same arguments
    selfupdate_reexec "$@"
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_is_git_checkout() — is this installation a git clone?
#
# Arguments: $1 — project directory to inspect (defaults to SCRIPT_DIR)
# Returns:   0 — a .git directory exists (git-managed checkout)
#            1 — static copy (or the directory is missing)
# ───────────────────────────────────────────────────────────────────────────────
# The optional argument is exercised by test/selfupdate.bats — shellcheck
# only sees the lib callers (which pass none), hence the directive:
# shellcheck disable=SC2120
selfupdate_is_git_checkout() {
    local dir="${1:-$SCRIPT_DIR}"
    [ -d "$dir/.git" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_verify_tree() — bash -n health check over a project tree
#
# Checks the main script and every lib/*.sh module of the given directory for
# syntax errors. Used on the freshly downloaded tree BEFORE a static update
# replaces anything, and on the live tree AFTER an update of either kind, so a
# broken download never becomes the installed state.
#
# Arguments: $1 — project directory to verify
# Returns:   0 — every file parses
#            1 — the main script or any module has a syntax error / is missing
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_verify_tree() {
    local dir="$1"
    [ -f "$dir/ubuntu-optimizer.sh" ] || return 1
    bash -n "$dir/ubuntu-optimizer.sh" 2>/dev/null || return 1
    local f
    for f in "$dir"/lib/*.sh; do
        [ -f "$f" ] || return 1
        bash -n "$f" 2>/dev/null || return 1
    done
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_refresh_completions() — refresh the installed completion files
#
# Overwrites the installed bash completion and the zsh completion (both only
# when their installed copies exist, so a user who never installed them is not
# surprised with new files). Completion changes take effect in new terminals.
#
# Globals:   SCRIPT_DIR (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_refresh_completions() {
    local bash_dst="$HOME/.local/share/bash-completion/completions/uo"
    if [ -f "$bash_dst" ] && [ -f "$SCRIPT_DIR/completions/uo" ]; then
        cp -f "$SCRIPT_DIR/completions/uo" "$bash_dst"
        ok "Bash completion refreshed."
    fi
    if [ -f "$HOME/.zfunc/_uo" ] && [ -f "$SCRIPT_DIR/completions/_uo" ]; then
        cp -f "$SCRIPT_DIR/completions/_uo" "$HOME/.zfunc/_uo"
        ok "zsh completion refreshed."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_update_git() — update a git checkout with pull --ff-only
#
# Warns about (and confirms) a dirty working tree first — local edits survive
# a fast-forward pull in most cases, but they can conflict. On pull failure or
# a broken tree afterwards, precise manual rollback instructions are printed.
#
# Globals:   SCRIPT_DIR, SCRIPT_VERSION, SU_REMOTE_VERSION, DRY_RUN (read)
# Arguments: none
# Returns:   0 — updated (or declined)
#            1 — pull failed or the tree is broken afterwards
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_update_git() {
    if [ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)" ]; then
        if [ "${SU_AUTO:-0}" = "1" ]; then
            # Never touch local edits silently — leave the decision to a
            # manual `uo --self-update` and let the current run continue
            warn "The working tree has local changes — skipping the automatic update (decide with: uo --self-update)."
            return 1
        fi
        warn "The working tree has local changes (uncommitted edits)."
        if ! confirm_action "Continue updating anyway? (git pull --ff-only keeps them when possible)"; then
            info "Declined — nothing changed. Commit or stash your edits, then re-run."
            return 0
        fi
    fi
    if [ "${SU_AUTO:-0}" != "1" ]; then
        if ! confirm_action "Update the toolkit from $SCRIPT_VERSION to v$SU_REMOTE_VERSION now?"; then
            info "Declined — the toolkit was not changed."
            return 0
        fi
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN — would run: git -C \"$SCRIPT_DIR\" pull --ff-only"
        return 0
    fi

    info "Fetching and applying updates..."
    if ! git -C "$SCRIPT_DIR" pull --ff-only > /dev/null 2>&1; then
        failure "git pull --ff-only failed — the checkout may have diverged from upstream."
        info "Manual fix:  git -C \"$SCRIPT_DIR\" stash && git -C \"$SCRIPT_DIR\" pull --ff-only"
        info "Discard local commits instead:  git -C \"$SCRIPT_DIR\" reset --hard origin/${SU_REMOTE_BRANCH}"
        return 1
    fi

    if ! selfupdate_verify_tree "$SCRIPT_DIR"; then
        failure "The updated files are broken (syntax error) — rolling back."
        git -C "$SCRIPT_DIR" reset --hard ORIG_HEAD > /dev/null 2>&1 \
            && warn "Rolled back to the previous commit (ORIG_HEAD)." \
            || info "Manual rollback: git -C \"$SCRIPT_DIR\" reset --hard ORIG_HEAD"
        return 1
    fi

    selfupdate_refresh_completions
    success "Toolkit updated: v$SCRIPT_VERSION → v$SU_REMOTE_VERSION."
    if [ "${SU_AUTO:-0}" != "1" ]; then
        warn "Running sessions keep the old code in memory — start a new 'uo' run."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_update_tarball() — update a static copy from the branch archive
#
# Flow: download → extract → verify (bash -n + version match) → backup → swap
# in with renames → verify → (auto-restore on failure). Only the directory
# entries the tool actually runs from are replaced (ubuntu-optimizer.sh,
# install.sh, lib/, completions/, test/, README/CHANGELOG/LICENSE), so user
# notes in the folder survive. The backup under SELFUPDATE_BACKUP_ROOT is both
# the rollback and the audit trail.
#
# Globals:   SCRIPT_DIR, SCRIPT_VERSION, SU_REMOTE_VERSION, SU_REMOTE_BRANCH,
#            SELFUPDATE_BACKUP_ROOT, DRY_RUN (read)
# Arguments: none
# Returns:   0 — updated (or declined)
#            1 — download, verification or replacement failed
# ───────────────────────────────────────────────────────────────────────────────
selfupdate_update_tarball() {
    if ! command -v tar > /dev/null 2>&1; then
        failure "tar is required for the archive update but was not found."
        return 1
    fi
    if [ "${SU_AUTO:-0}" != "1" ]; then
        if ! confirm_action "Download and apply the update to v$SU_REMOTE_VERSION now?"; then
            info "Declined — the toolkit was not changed."
            return 0
        fi
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN — would download: https://github.com/${SELFUPDATE_REPO}/archive/refs/heads/${SU_REMOTE_BRANCH}.tar.gz"
        info "DRY RUN — would back up to: $SELFUPDATE_BACKUP_ROOT/ and swap the files in with atomic renames."
        return 0
    fi

    local tmp
    tmp=$(mktemp -d) || { failure "Could not create a temporary directory."; return 1; }

    info "Downloading the branch archive..."
    if ! curl -fsSL --connect-timeout 15 --max-time 120 \
        "https://github.com/${SELFUPDATE_REPO}/archive/refs/heads/${SU_REMOTE_BRANCH}.tar.gz" \
        -o "$tmp/src.tar.gz" 2>/dev/null; then
        failure "The archive download failed — check your internet connection."
        rm -rf "$tmp"
        return 1
    fi

    if ! tar -xzf "$tmp/src.tar.gz" -C "$tmp" 2>/dev/null; then
        failure "The archive could not be extracted (corrupt download?)."
        rm -rf "$tmp"
        return 1
    fi

    local src
    src=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'ubuntu-optimizer-*' | head -n 1)
    if [ -z "$src" ]; then
        failure "Unexpected archive layout — update aborted."
        rm -rf "$tmp"
        return 1
    fi

    # Verify BEFORE anything is touched — a broken download never reaches disk
    if ! selfupdate_verify_tree "$src"; then
        failure "The downloaded files failed the syntax check — update aborted, nothing was changed."
        rm -rf "$tmp"
        return 1
    fi
    if [ "$(sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)".*/\1/p' "$src/lib/common.sh" 2>/dev/null)" != "$SU_REMOTE_VERSION" ]; then
        failure "The downloaded tree does not match the expected version — update aborted."
        rm -rf "$tmp"
        return 1
    fi

    local backup
    backup="$SELFUPDATE_BACKUP_ROOT/v${SCRIPT_VERSION}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup" || { failure "Could not create the backup directory."; rm -rf "$tmp"; return 1; }

    info "Backing up the current installation to: $backup"
    # Move (rename) the live entries into the backup — instant and atomic; the
    # running bash process keeps reading its already-open files unharmed.
    local entry
    for entry in ubuntu-optimizer.sh install.sh lib completions test README.md README.fa.md CHANGELOG.md LICENSE; do
        [ -e "$SCRIPT_DIR/$entry" ] && mv -f "$SCRIPT_DIR/$entry" "$backup/"
    done

    # Copy the new tree beside the target, then rename into place — a rename
    # swaps the directory entry, never the inode the running script reads.
    for entry in ubuntu-optimizer.sh install.sh lib completions test README.md README.fa.md CHANGELOG.md LICENSE; do
        [ -e "$src/$entry" ] || continue
        cp -a "$src/$entry" "$SCRIPT_DIR/.selfupdate-new" || { failure "Copy failed for: $entry"; break; }
        mv -f "$SCRIPT_DIR/.selfupdate-new" "$SCRIPT_DIR/$entry" || { failure "Rename failed for: $entry"; break; }
    done

    if ! selfupdate_verify_tree "$SCRIPT_DIR"; then
        failure "Verification after the update failed — restoring the backup."
        for entry in ubuntu-optimizer.sh install.sh lib completions test README.md README.fa.md CHANGELOG.md LICENSE; do
            [ -e "$backup/$entry" ] && mv -f "$backup/$entry" "$SCRIPT_DIR/"
        done
        warn "The previous installation was restored — the toolkit is unchanged."
        rm -rf "$tmp"
        return 1
    fi

    rm -rf "$tmp"
    selfupdate_refresh_completions
    success "Toolkit updated: v$SCRIPT_VERSION → v$SU_REMOTE_VERSION."
    info "Rollback if needed: restore the files from $backup"
    if [ "${SU_AUTO:-0}" != "1" ]; then
        warn "Running sessions keep the old code in memory — start a new 'uo' run."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# self_update_interactive() — CLI entry for `uo --self-update`
#
# Orchestrates the whole flow: version check → comparison → (dry-run plan |)
# git or archive update. Exit codes stay script-friendly: 0 when nothing needs
# doing (up to date, local newer, declined) and after a successful update, 1
# when the update was attempted and failed.
#
# Globals:   SCRIPT_DIR, SCRIPT_VERSION, DRY_RUN, ASSUME_YES (read)
#            SU_REMOTE_VERSION, SU_REMOTE_BRANCH (written)
# Arguments: none
# Returns:   0 — up to date, declined, or updated
#            1 — an attempted update failed (already reported)
# ───────────────────────────────────────────────────────────────────────────────
self_update_interactive() {
    header "⬆️  Self Update"

    info "Installed version: v$SCRIPT_VERSION"
    local kind="copy"
    if selfupdate_is_git_checkout; then
        kind="git"
        info "Installation kind: git checkout ($SCRIPT_DIR)"
    else
        info "Installation kind: static copy — the update is downloaded as an archive."
    fi

    info "Checking the latest version on GitHub..."
    if ! selfupdate_fetch_remote_version; then
        return 1
    fi
    info "Latest version on GitHub: v$SU_REMOTE_VERSION (branch: $SU_REMOTE_BRANCH)"

    if [ "$SU_REMOTE_VERSION" = "$SCRIPT_VERSION" ]; then
        success "The toolkit is up to date (v$SCRIPT_VERSION)."
        return 0
    fi
    # An unreadable local version must never block an update — fail toward
    # updating instead of silently claiming to be "newer"
    if [ -n "$SCRIPT_VERSION" ] && ! selfupdate_version_newer "$SU_REMOTE_VERSION" "$SCRIPT_VERSION"; then
        info "The installed version (v$SCRIPT_VERSION) is newer than the remote (v$SU_REMOTE_VERSION) — a development checkout? Nothing to do."
        return 0
    fi

    success "A new version is available: v$SCRIPT_VERSION → v$SU_REMOTE_VERSION"

    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN — plan only, nothing has been changed."
        if [ "$kind" = "git" ]; then
            info "DRY RUN — would run: git -C \"$SCRIPT_DIR\" pull --ff-only"
        else
            info "DRY RUN — would download https://github.com/${SELFUPDATE_REPO}/archive/refs/heads/${SU_REMOTE_BRANCH}.tar.gz"
            info "DRY RUN — verify with bash -n, back up to $SELFUPDATE_BACKUP_ROOT, swap in with atomic renames."
        fi
        return 0
    fi

    if [ "$kind" = "git" ]; then
        selfupdate_update_git
    else
        selfupdate_update_tarball
    fi
}
