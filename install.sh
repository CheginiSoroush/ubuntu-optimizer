#!/bin/bash
# ============================================================
#   install.sh — install & manage Ubuntu Optimizer & Fixer
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   ./install.sh              install: health check + uo shortcut + alias + PATH
#   ./install.sh --check      check file health and install status
#   ./install.sh --update     update from git (if a git repository)
#   ./install.sh --uninstall  remove shortcut and alias (project files stay)
# ============================================================

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

ok()  { echo -e "${GREEN}   ✓ $1${NC}"; }
bad() { echo -e "${RED}   ✗ $1${NC}"; }
inf() { echo -e "${YELLOW}   ℹ $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/ubuntu-optimizer.sh"
LIB_COMMON="$SCRIPT_DIR/lib/common.sh"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/uo"

COMPLETION_SRC="$SCRIPT_DIR/completions/uo"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
COMPLETION_DST="$COMPLETION_DIR/uo"

REQUIRED_MODULES=(common network system fixnet packages targz appmgmt snapflatpak recovery report github doctor disk gitssh menus)

# Version is read from the project's single source (SCRIPT_VERSION in lib/common.sh)
version() {
    sed -n 's/^readonly SCRIPT_VERSION="\([^"]*\)".*/v\1/p' "$LIB_COMMON" 2>/dev/null
}

# Install/refresh the bash completion file (active in new terminals)
_install_completion() {
    [ -f "$COMPLETION_SRC" ] || return 0
    mkdir -p "$COMPLETION_DIR"
    cp -f "$COMPLETION_SRC" "$COMPLETION_DST"
    return 0
}

# ---------- File health check ----------
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

# ---------- Install status ----------
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

# Append the PATH block to a shell rc file (with duplicate guard)
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

# Remove the PATH block from a shell rc file.
# Skipped when the end marker is missing — the sed range would otherwise
# delete everything up to the end of the file.
# --follow-symlinks: an rc file managed as a symlink (dotfiles) stays a symlink.
_remove_path_block() {   # $1 = rc file path
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    grep -q '^# <<< ubuntu-optimizer path <<<$' "$rcfile" 2>/dev/null || return 0
    sed -i --follow-symlinks \
        '/^# >>> ubuntu-optimizer path >>>$/,/^# <<< ubuntu-optimizer path <<<$/d' \
        "$rcfile" 2>/dev/null
    return 0
}

# Remove only the alias this installer added — a user's own 'alias uo=...'
# pointing elsewhere is left alone.
_remove_alias() {   # $1 = rc file path
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    sed -i --follow-symlinks \
        '/^alias uo="[^"]*ubuntu-optimizer\.sh"$/d; /^# Ubuntu Optimizer & Fixer$/d' \
        "$rcfile" 2>/dev/null
    return 0
}

# ---------- Install ----------
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

    local rc_alias="alias uo=\"$MAIN_SCRIPT\""
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

    echo ""
    inf "To activate in this terminal:  source ~/.bashrc"
    inf "In new terminals, 'uo' is available automatically."
    inf "Tab completion for 'uo' works in new terminals."
    inf "Usage:  uo   |   uo --report   |   uo --help"
}

# ---------- Update from git ----------
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
            # Refresh the installed completion file with the updated version
            _install_completion
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

# ---------- Uninstall ----------
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
    ok "alias and PATH block removed from shell rc files."
    inf "The project itself in $SCRIPT_DIR is untouched."
    inf "To delete the project entirely: rm -rf \"$SCRIPT_DIR\""
}

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
