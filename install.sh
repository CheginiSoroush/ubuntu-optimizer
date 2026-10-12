#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — install.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Standalone installer/manager for the toolkit: verifies project file health,
#  installs the 'uo' shortcut, alias, PATH block and bash completion, updates
#  from git (--update), checks status (--check) or uninstalls (--uninstall).
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Non-interactive output (pipe/redirect): colors are disabled automatically
if [ ! -t 1 ]; then
    GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

# ───────────────────────────────────────────────────────────────────────────────
# ok() — print a green check line
#
# Installer success message; the colour is empty when piped/redirected.
#
# Arguments: $1 — message text
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
ok()  { echo -e "${GREEN}   ✓ $1${NC}"; }
# ───────────────────────────────────────────────────────────────────────────────
# bad() — print a red cross line
#
# Installer failure message; the colour is empty when piped/redirected.
#
# Arguments: $1 — message text
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
bad() { echo -e "${RED}   ✗ $1${NC}"; }
# ───────────────────────────────────────────────────────────────────────────────
# inf() — print a yellow info line
#
# Installer informational message; the colour is empty when piped/redirected.
#
# Arguments: $1 — message text
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
inf() { echo -e "${YELLOW}   ℹ $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/ubuntu-optimizer.sh"
LIB_COMMON="$SCRIPT_DIR/lib/common.sh"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/uo"

COMPLETION_SRC="$SCRIPT_DIR/completions/uo"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
COMPLETION_DST="$COMPLETION_DIR/uo"
ZSH_COMPLETION_SRC="$SCRIPT_DIR/completions/_uo"
ZFUNC_DIR="$HOME/.zfunc"
ZSH_COMPLETION_DST="$ZFUNC_DIR/_uo"

REQUIRED_MODULES=(common cache config network system fixnet packages targz appmgmt snapflatpak recovery report jsonreport github doctor disk htmlreport gitssh undo profile boot autostart selfupdate timer menus)

# ───────────────────────────────────────────────────────────────────────────────
# version() — print the project version (vX.Y) from lib/common.sh
#
# Extracts the SCRIPT_VERSION line with sed so the installer never hardcodes
# a version of its own (single source of truth). Output is empty when the
# file or the version line is missing.
#
# Globals:   LIB_COMMON (read)
# Arguments: none
# Returns:   0 — version extracted and printed
#            non-zero — lib/common.sh unreadable or no version line
# ───────────────────────────────────────────────────────────────────────────────
version() {
    sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)".*/v\1/p' "$LIB_COMMON" 2>/dev/null
}

# ───────────────────────────────────────────────────────────────────────────────
# _install_completion() — copy the uo bash completion into place
#
# Copies completions/uo to the user's bash-completion directory (created on
# demand). A silent no-op when the source file is absent, so it can be
# called unconditionally by the install and update flows. Takes effect in
# new terminals only.
#
# Globals:   COMPLETION_SRC, COMPLETION_DIR, COMPLETION_DST (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_install_completion() {
    [ -f "$COMPLETION_SRC" ] || return 0
    mkdir -p "$COMPLETION_DIR"
    cp -f "$COMPLETION_SRC" "$COMPLETION_DST"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _install_zsh_completion() — copy the zsh completion into ~/.zfunc
#
# Copies completions/_uo into ~/.zfunc and appends a guarded "ubuntu-optimizer
# zfunc" block to ~/.zshrc that adds the directory to fpath and runs compinit.
# Skipped entirely when ~/.zshrc does not exist (zsh not in use). Duplicate-safe:
# both the file copy and the rc block return immediately when already present.
# Takes effect in new terminals only.
#
# Globals:   ZSH_COMPLETION_SRC, ZFUNC_DIR, ZSH_COMPLETION_DST (read/write)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_install_zsh_completion() {
    [ -f "$HOME/.zshrc" ] || return 0
    [ -f "$ZSH_COMPLETION_SRC" ] || return 0
    mkdir -p "$ZFUNC_DIR"
    cp -f "$ZSH_COMPLETION_SRC" "$ZSH_COMPLETION_DST"
    if ! grep -q "ubuntu-optimizer zfunc" "$HOME/.zshrc" 2>/dev/null; then
        {
            echo ""
            echo "# >>> ubuntu-optimizer zfunc >>>"
            echo 'fpath=("'"$ZFUNC_DIR"'" $fpath)'
            echo "autoload -Uz compinit && compinit"
            echo "# <<< ubuntu-optimizer zfunc <<<"
        } >> "$HOME/.zshrc"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# check_health() — verify all project files exist and are syntactically valid
#
# Checks that ubuntu-optimizer.sh and every module in REQUIRED_MODULES is
# present and passes bash -n, that lib/common.sh exposes SCRIPT_VERSION, and
# that bash is 4.3+. Read-only — safe to run from scripts and CI.
#
# Globals:   MAIN_SCRIPT, LIB_COMMON, REQUIRED_MODULES, SCRIPT_DIR (read)
# Arguments: none
# Returns:   0 — all files healthy
#            1 — file missing, syntax error or bash too old
# ───────────────────────────────────────────────────────────────────────────────
check_health() {
    echo -e "${BOLD}── File health check ──${NC}"
    if [ ! -f "$MAIN_SCRIPT" ]; then
        bad "ubuntu-optimizer.sh not found in this folder!"
        return 1
    fi
    if ! bash -n "$MAIN_SCRIPT" 2>/dev/null; then
        bad "Syntax error in ubuntu-optimizer.sh"
        return 1
    fi
    if [ ! -f "$LIB_COMMON" ] || [ -z "$(version)" ]; then
        bad "lib/common.sh not found or SCRIPT_VERSION missing in it"
        return 1
    fi
    ok "ubuntu-optimizer.sh ($(version))"

    local m f broken=0
    for m in "${REQUIRED_MODULES[@]}"; do
        f="$SCRIPT_DIR/lib/$m.sh"
        if [ ! -f "$f" ]; then
            bad "Missing module: lib/$m.sh"
            broken=1
        elif ! bash -n "$f" 2>/dev/null; then
            bad "Syntax error in: lib/$m.sh"
            broken=1
        else
            ok "lib/$m.sh"
        fi
    done
    [ "$broken" = "0" ] || return 1

    # log_write in common.sh uses printf %(datefmt)T (bash 4.3+)
    if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 403 )); then
        bad "Bash version too old (need: 4.3+) — current: $BASH_VERSION"
        return 1
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# check_install_status() — report the state of everything the installer created
#
# Read-only overview: the ~/.local/bin/uo shortcut, the 'uo' alias and PATH
# block in ~/.bashrc (and ~/.zshrc when present), the installed completion
# file, and whether ~/.local/bin is on the current shell's PATH.
#
# Globals:   BIN_LINK, BIN_DIR, COMPLETION_DST (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
check_install_status() {
    echo -e "${BOLD}── Install status ──${NC}"
    if [ -L "$BIN_LINK" ]; then
        ok "Shortcut active: $BIN_LINK → $(readlink "$BIN_LINK")"
    else
        inf "Shortcut 'uo' is not installed."
    fi
    if grep -q "alias uo=" "$HOME/.bashrc" 2>/dev/null; then
        ok "alias 'uo' present in ~/.bashrc."
    else
        inf "alias 'uo' not present in ~/.bashrc."
    fi
    if grep -q "ubuntu-optimizer path" "$HOME/.bashrc" 2>/dev/null; then
        ok "PATH block present in ~/.bashrc."
    else
        inf "PATH block not present in ~/.bashrc."
    fi
    if [ -f "$HOME/.zshrc" ]; then
        if grep -q "alias uo=" "$HOME/.zshrc" 2>/dev/null; then
            ok "alias 'uo' present in ~/.zshrc."
        else
            inf "alias 'uo' not present in ~/.zshrc."
        fi
        if grep -q "ubuntu-optimizer path" "$HOME/.zshrc" 2>/dev/null; then
            ok "PATH block present in ~/.zshrc."
        else
            inf "PATH block not present in ~/.zshrc."
        fi
    fi
    if [ -f "$COMPLETION_DST" ]; then
        ok "bash completion installed: $COMPLETION_DST"
    else
        inf "bash completion is not installed."
    fi
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        inf "$BIN_DIR is not in the current shell PATH (works in new shells)."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _add_path_block() — append the guarded PATH block to a shell rc file
#
# Appends a marked "ubuntu-optimizer path" block that exports ~/.local/bin
# only when it is not already on PATH. Duplicate-safe: returns immediately
# when the block marker is already present in the rc file.
#
# Arguments: $1 — rc file path (e.g. ~/.bashrc); missing files are skipped
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_add_path_block() {   # $1 = rc file path
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    grep -q "ubuntu-optimizer path" "$rcfile" 2>/dev/null && return 0
    {
        echo ""
        echo "# >>> ubuntu-optimizer path >>>"
        # shellcheck disable=SC2016  # intentional: $PATH/$HOME expand when the rc file is sourced
        echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
        echo "# <<< ubuntu-optimizer path <<<"
    } >> "$rcfile"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _remove_path_block() — delete the PATH block from a shell rc file
#
# Removes the marked block with a bounded sed range. Skipped when the end
# marker is missing — the sed range would otherwise delete everything up to
# the end of the file. --follow-symlinks: an rc file managed as a symlink
# (dotfiles) stays a symlink.
#
# Arguments: $1 — rc file path; missing files are skipped
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_remove_path_block() {   # $1 = rc file path
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    grep -q '^# <<< ubuntu-optimizer path <<<$' "$rcfile" 2>/dev/null || return 0
    sed -i --follow-symlinks \
        '/^# >>> ubuntu-optimizer path >>>$/,/^# <<< ubuntu-optimizer path <<<$/d' \
        "$rcfile" 2>/dev/null
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _remove_alias() — remove the installer-added 'uo' alias from an rc file
#
# Deletes only the alias lines this installer wrote (the legacy double-quoted
# form and the current single-quoted form). A user's own 'alias uo=...'
# pointing elsewhere is deliberately left alone.
#
# Arguments: $1 — rc file path; missing files are skipped
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_remove_alias() {   # $1 = rc file path
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    sed -i --follow-symlinks \
        '/^alias uo="[^"]*ubuntu-optimizer\.sh"$/d; /^alias uo='\''[^'\'']*ubuntu-optimizer\.sh'\''$/d; /^# Ubuntu Optimizer & Fixer$/d' \
        "$rcfile" 2>/dev/null
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# do_install() — install the toolkit integration (default mode)
#
# Runs the health check first and aborts with exit 1 when files are broken.
# Otherwise creates the ~/.local/bin/uo symlink, adds the 'uo' alias to
# ~/.bashrc (and ~/.zshrc when present), the PATH block and the bash
# completion. All additions are duplicate-safe — re-running is harmless.
#
# Globals:   MAIN_SCRIPT, BIN_DIR, BIN_LINK, COMPLETION_DST (read/write)
# Arguments: none
# Returns:   0 — install completed
#            exits 1 — when the pre-install health check fails
# ───────────────────────────────────────────────────────────────────────────────
do_install() {
    echo -e "${BOLD}${CYAN}Installing Ubuntu Optimizer & Fixer $(version)${NC}"
    echo ""
    if ! check_health; then
        echo ""
        bad "Install aborted — fix the errors above first."
        exit 1
    fi
    echo ""

    mkdir -p "$BIN_DIR"
    ln -sf "$MAIN_SCRIPT" "$BIN_LINK"
    chmod +x "$MAIN_SCRIPT"
    ok "Shortcut created: $BIN_LINK"

    # Single quotes around the path keep the alias working even when the
    # project folder name contains spaces
    local rc_alias="alias uo='${MAIN_SCRIPT}'"
    if ! grep -q "alias uo=" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# Ubuntu Optimizer & Fixer"
            echo "$rc_alias"
        } >> "$HOME/.bashrc"
        ok "alias 'uo' added to ~/.bashrc."
    fi
    if [ -f "$HOME/.zshrc" ] && ! grep -q "alias uo=" "$HOME/.zshrc" 2>/dev/null; then
        {
            echo ""
            echo "# Ubuntu Optimizer & Fixer"
            echo "$rc_alias"
        } >> "$HOME/.zshrc"
        ok "alias 'uo' added to ~/.zshrc."
    fi

    # ~/.local/bin on PATH so 'uo' works without the alias
    _add_path_block "$HOME/.bashrc"
    _add_path_block "$HOME/.zshrc"
    ok "$BIN_DIR set in shell rc files."

    # Bash completion for 'uo' — picked up in new terminals
    _install_completion
    ok "Bash completion installed: $COMPLETION_DST"

    # zsh completion — only when zsh is in use (~/.zshrc exists)
    _install_zsh_completion
    if [ -f "$ZSH_COMPLETION_DST" ]; then
        ok "zsh completion installed: $ZSH_COMPLETION_DST"
    fi

    echo ""
    inf "To activate in this terminal:  source ~/.bashrc"
    inf "In new terminals, 'uo' is available automatically."
    inf "Tab completion for 'uo' works in new terminals."
    inf "Usage:  uo   |   uo --report   |   uo --help"
}

# ───────────────────────────────────────────────────────────────────────────────
# do_update() — update the project from its git remote
#
# Runs git pull when SCRIPT_DIR is a git repository, re-runs the health
# check on the pulled tree and refreshes the installed completion file.
# Outside a repository it prints the manual update instructions and exits 0.
#
# Globals:   SCRIPT_DIR (read)
# Arguments: none
# Returns:   0 — updated, or manual-mode informational exit
#            exits 1 — when git pull fails or files break after the update
# ───────────────────────────────────────────────────────────────────────────────
do_update() {
    echo -e "${BOLD}${CYAN}Updating Ubuntu Optimizer & Fixer${NC}"
    echo ""
    if [ -d "$SCRIPT_DIR/.git" ]; then
        inf "Fetching updates from git..."
        if git -C "$SCRIPT_DIR" pull; then
            echo ""
            if ! check_health; then
                bad "Some files are broken after the update!"
                exit 1
            fi
            # Refresh the installed completion files with the updated versions
            _install_completion
            _install_zsh_completion
            echo ""
            ok "Update complete. Current version: $(version)"
        else
            bad "git pull failed — check your internet or repository access."
            exit 1
        fi
    else
        inf "This folder is not a git repository; automatic update unavailable."
        inf "Manual method: replace the files, then run: $0 --check"
        exit 0
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# do_uninstall() — remove the shell integration, keep the project files
#
# Removes the ~/.local/bin/uo shortcut, the 'uo' alias, the PATH block from
# ~/.bashrc (and ~/.zshrc) and the installed bash completion. The project
# directory itself is never touched — deleting it is left to the user.
#
# Globals:   BIN_LINK, COMPLETION_DST (read/write)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
do_uninstall() {
    echo -e "${BOLD}${CYAN}Uninstalling Ubuntu Optimizer & Fixer${NC}"
    echo ""
    rm -f "$BIN_LINK"
    ok "Shortcut 'uo' removed."
    _remove_alias "$HOME/.bashrc"
    _remove_path_block "$HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ]; then
        _remove_alias "$HOME/.zshrc"
        _remove_path_block "$HOME/.zshrc"
    fi
    rm -f "$COMPLETION_DST"
    ok "Bash completion removed."
    if [ -f "$ZSH_COMPLETION_DST" ]; then
        rm -f "$ZSH_COMPLETION_DST"
        ok "zsh completion removed."
    fi
    if [ -f "$HOME/.zshrc" ]; then
        sed -i --follow-symlinks \
            '/^# >>> ubuntu-optimizer zfunc >>>$/,/^# <<< ubuntu-optimizer zfunc <<<$/d' \
            "$HOME/.zshrc" 2>/dev/null
    fi
    ok "alias and PATH block removed from shell rc files."
    inf "The project itself in $SCRIPT_DIR is untouched."
    inf "To delete the project entirely: rm -rf \"$SCRIPT_DIR\""
}

# ───────────────────────────────────────────────────────────────────────────────
# usage() — print the installer help text
#
# Renders the mode overview (install / --check / --update / --uninstall /
# --help) from a quoted heredoc so the text is emitted verbatim.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
usage() {
    cat << 'EOF'
install.sh — manage the Ubuntu Optimizer & Fixer installation

  ./install.sh              install: health check + uo shortcut + alias + PATH
  ./install.sh --check      only check file health and install status
  ./install.sh --update     update from git (if a git repository)
  ./install.sh --uninstall  remove shortcut and alias (project files stay)
  ./install.sh --help       show this help
EOF
}

case "${1:-}" in
    --check)
        # Exit 1 when unhealthy — usable from scripts/CI
        check_health || exit 1
        echo ""
        check_install_status
        ;;
    --update)    do_update ;;
    --uninstall) do_uninstall ;;
    -h|--help)   usage ;;
    "")          do_install ;;
    *)           echo "Invalid option: $1"; usage; exit 1 ;;
esac
