# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/selfupdate.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Updates the toolkit itself (`uo --self-update`). Two installation kinds are
#  supported, detected automatically:
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
SU_REMOTE_VERSION=""
SU_REMOTE_BRANCH=""

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
        raw=$(curl -fsSL --connect-timeout 15 --max-time 30 "${auth[@]}" \
            "https://raw.githubusercontent.com/${SELFUPDATE_REPO}/${branch}/lib/common.sh" 2>/dev/null) || continue
        SU_REMOTE_VERSION=$(sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)".*/\1/p' <<< "$raw")
        if [ -n "$SU_REMOTE_VERSION" ]; then
            SU_REMOTE_BRANCH="$branch"
            return 0
        fi
    done

    failure "Could not read the remote version from raw.githubusercontent.com."
    info "Check your internet connection (or GH_TOKEN) and try again."
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# selfupdate_is_git_checkout() — is this installation a git clone?
#
# Arguments: $1 — project directory to inspect (defaults to SCRIPT_DIR)
# Returns:   0 — a .git directory exists (git-managed checkout)
#            1 — static copy (or the directory is missing)
# ───────────────────────────────────────────────────────────────────────────────
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
        warn "The working tree has local changes (uncommitted edits)."
        if ! confirm_action "Continue updating anyway? (git pull --ff-only keeps them when possible)"; then
            info "Declined — nothing changed. Commit or stash your edits, then re-run."
            return 0
        fi
    fi
    if ! confirm_action "Update the toolkit from $SCRIPT_VERSION to v$SU_REMOTE_VERSION now?"; then
        info "Declined — the toolkit was not changed."
        return 0
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
    warn "Running sessions keep the old code in memory — start a new 'uo' run."
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
    if ! confirm_action "Download and apply the update to v$SU_REMOTE_VERSION now?"; then
        info "Declined — the toolkit was not changed."
        return 0
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
    warn "Running sessions keep the old code in memory — start a new 'uo' run."
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
