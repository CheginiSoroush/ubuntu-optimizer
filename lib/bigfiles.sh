# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/bigfiles.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Read-only large-file finder: lists the biggest files under a directory so
#  "where did my disk space go?" gets an answer in one command. Nothing here
#  deletes anything — the output ends with a pointer to 'uo --disk-clean' for
#  actually freeing space. The size floor and the directory are configurable
#  (UO_BIGFILES_MIN_MB / the optional --bigfiles DIR argument). Every failure
#  (bad directory, find errors) degrades to a warning and exit 0.
#  Entry points: the CLI flag --bigfiles and the "Monitor & inspect" submenu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _bigfiles_human() — format a byte count in compact human units
#
# Pure formatter: whole units below GB (so a "923 MB" file does not become
# "0.9 GB"), one decimal only in the GB range.
#
# Arguments: $1 — size in bytes
# Returns:   prints e.g. "1.5 GB" · "923 MB" · "812 KB" · "512 B"
# ───────────────────────────────────────────────────────────────────────────────
_bigfiles_human() {
    local b="$1"
    case "$b" in ''|*[!0-9]*) echo "?"; return 0 ;; esac
    if [ "$b" -ge 1073741824 ]; then
        awk -v b="$b" 'BEGIN { printf "%.1f GB", b / 1073741824 }'
    elif [ "$b" -ge 1048576 ]; then
        printf '%d MB' $(( b / 1048576 ))
    elif [ "$b" -ge 1024 ]; then
        printf '%d KB' $(( b / 1024 ))
    else
        printf '%d B' "$b"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# bigfiles_show() — list the largest files under a directory (read-only)
#
# Walks the directory with find (staying on one filesystem via -xdev), filters
# by the size floor (UO_BIGFILES_MIN_MB, default 100) and prints the top 20
# files sorted by size, largest first. An unreadable or missing directory is
# a friendly warning and exit 0, never an error; the run always ends with the
# hint that this command deleted nothing.
#
# Arguments: $1 — optional directory (default: UO_BIGFILES_DIR, then $HOME)
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
bigfiles_show() {
    local dir="${1:-${UO_BIGFILES_DIR:-$HOME}}"
    local min="${UO_BIGFILES_MIN_MB:-100}"

    header "🔍 Large File Finder"

    # ── guard: the directory must exist and be readable ───────────────────────
    if [ ! -d "$dir" ]; then
        warn "Directory not found: $dir"
        info "Usage: uo --bigfiles [DIR] (default: \$HOME) — nothing was deleted."
        return 0
    fi
    if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
        warn "Directory is not readable: $dir"
        info "Check the permissions — nothing was deleted."
        return 0
    fi

    echo -e "${BOLD}   Scanning:${NC} $dir  (files larger than ${min} MB — top 20)"
    echo ""

    local -a lines=()
    # -xdev keeps the scan on one filesystem (no /proc, no other mounts);
    # find errors (permission denied on subdirs) are silenced — read-only tool
    mapfile -t lines < <(find "$dir" -xdev -type f -size "+${min}M" -printf '%s\t%p\n' 2> /dev/null \
        | sort -rn | head -n 20)

    if [ ${#lines[@]} -eq 0 ]; then
        info "No files larger than ${min} MB found under $dir"
    else
        local entry size path
        for entry in "${lines[@]}"; do
            size="${entry%%$'\t'*}"
            path="${entry#*$'\t'}"
            printf '   %10s  %s\n' "$(_bigfiles_human "$size")" "$path"
        done
    fi

    echo ""
    info "This scan is read-only — nothing was deleted."
    info "To free space, run: uo --disk-clean"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# bigfiles_menu() — interactive wrapper: ask for the directory, then scan
#
# Menu entry behind "Find large files": prompts for a directory with $HOME
# as the default and hands it to bigfiles_show. A leading "~" is expanded
# manually (read does not expand tilde) — no eval is ever involved.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
bigfiles_menu() {
    local dir
    read -r -p "   Directory to scan [default: $HOME]: " dir || return 0
    [ -z "$dir" ] && dir="$HOME"
    dir="${dir/#\~/$HOME}"
    bigfiles_show "$dir"
}
