# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/browserclean.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Browser cache cleanup — the only writing feature of the monitor family.
#  Targets the pure cache directories of the Chromium family (Chrome,
#  Chromium, Edge, Brave, Opera, Vivaldi — including their flatpak variants
#  under ~/.var/app), the Firefox profile caches and the XDG thumbnails.
#  Only cache CONTENTS are deleted (the directories themselves stay), so
#  bookmarks, passwords, cookies and history can never be touched by design.
#  A browser that is currently running is skipped with a warning — safety
#  first, even with -y. Honors the global DRY_RUN flag (sizes only) and the
#  usual confirmation flow. Entry points: the CLI flag --browser-clean and
#  the "Monitor & inspect" submenu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _browserclean_proc_for() — map a cache directory name to its process name(s)
#
# The cache dirs are named after the package, the processes are not
# (google-chrome runs as "chrome", microsoft-edge as "msedge", vivaldi as
# "vivaldi-bin"). Several candidates may apply and are separated by "|";
# pgrep is run against every candidate.
#
# Arguments: $1 — cache directory basename (e.g. google-chrome)
# Returns:   prints the pipe-separated process basenames (empty when unknown)
# ───────────────────────────────────────────────────────────────────────────────
_browserclean_proc_for() {
    case "$1" in
        google-chrome)  echo "chrome" ;;
        chromium)       echo "chromium|chrome" ;;
        microsoft-edge) echo "msedge" ;;
        brave)          echo "brave" ;;
        opera)          echo "opera" ;;
        vivaldi)        echo "vivaldi|vivaldi-bin" ;;
        *)              echo "" ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# _browserclean_cache_roots() — every cache root that may host browser data
#
# The primary XDG cache root plus the flatpak per-app cache roots
# (~/.var/app/<app-id>/cache), where sandboxed browsers keep their profiles.
#
# Arguments: none
# Returns:   prints one directory per line
# ───────────────────────────────────────────────────────────────────────────────
_browserclean_cache_roots() {
    printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
    local flat
    for flat in "$HOME/.var/app/"*/cache; do
        [ -d "$flat" ] && printf '%s\n' "$flat"
    done
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _browserclean_dir_mb() — total size of tab-separated paths, in whole MB
#
# du -sm per path (the same measure the disk module uses), summed. A missing
# or unreadable path simply contributes 0 — cleanup targets are optional.
#
# Arguments: $1 — paths joined with tabs
# Returns:   prints the summed MB as an integer
# ───────────────────────────────────────────────────────────────────────────────
_browserclean_dir_mb() {
    local sum=0 p m
    local -a paths=()
    IFS=$'\t' read -r -a paths <<< "$1"
    for p in "${paths[@]}"; do
        [ -d "$p" ] || continue
        m=$(du -sm "$p" 2> /dev/null | cut -f1)
        [[ "$m" =~ ^[0-9]+$ ]] && sum=$(( sum + m ))
    done
    printf '%s' "$sum"
}

# ───────────────────────────────────────────────────────────────────────────────
# _browserclean_collect() — discover every cache target that actually exists
#
# Prints one record per browser: "label|process-name(s)|path<TAB>path…".
# The "|" field separator keeps empty fields intact (thumbnails have no
# owner); the paths stay tab-joined inside the third field. Only directories
# that exist AND contain at least one cache subdirectory become targets.
# Read-only.
#
# Arguments: none
# Returns:   0 — records on stdout (may be empty)
# ───────────────────────────────────────────────────────────────────────────────
_browserclean_collect() {
    local root app sub pdir label
    local -a roots=() subpaths=()
    local -a chromium_apps=(google-chrome chromium microsoft-edge brave opera vivaldi)

    mapfile -t roots < <(_browserclean_cache_roots)

    # ── Chromium family ───────────────────────────────────────────────────────
    for root in "${roots[@]}"; do
        for app in "${chromium_apps[@]}"; do
            [ -d "$root/$app" ] || continue
            subpaths=()
            for sub in "Default/Cache" "Default/Code Cache" "Default/GPUCache"; do
                [ -d "$root/$app/$sub" ] && subpaths+=("$root/$app/$sub")
            done
            [ ${#subpaths[@]} -gt 0 ] || continue
            case "$root" in
                "$HOME"/.var/app/*) label="$app (flatpak)" ;;
                *)                  label="$app" ;;
            esac
            printf '%s|%s|%s\n' "$label" "$(_browserclean_proc_for "$app")" \
                "$(IFS=$'\t'; echo "${subpaths[*]}")"
        done
    done

    # ── Firefox: every *.default* profile keeps its own caches ────────────────
    for root in "${roots[@]}"; do
        [ -d "$root/mozilla/firefox" ] || continue
        for pdir in "$root/mozilla/firefox/"*.default*; do
            [ -d "$pdir" ] || continue
            subpaths=()
            for sub in cache2 startupCache shader-cache; do
                [ -d "$pdir/$sub" ] && subpaths+=("$pdir/$sub")
            done
            [ ${#subpaths[@]} -gt 0 ] || continue
            case "$root" in
                "$HOME"/.var/app/*) label="Firefox (flatpak)" ;;
                *)                  label="Firefox" ;;
            esac
            printf '%s|firefox|%s\n' "$label" \
                "$(IFS=$'\t'; echo "${subpaths[*]}")"
        done
    done

    # ── Thumbnails (no owning process) ────────────────────────────────────────
    local tdir="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"
    if [ -d "$tdir" ] && [ -n "$(ls -A "$tdir" 2> /dev/null)" ]; then
        # the record format is always "label|proc|paths" — thumbnails own no
        # process, so the middle field stays empty (the parse below relies on it)
        printf '%s|%s|%s\n' "Thumbnails" "" "$tdir"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _browserclean_is_running() — is the owning browser process alive?
#
# pgrep on every executable basename candidate. When pgrep itself is missing
# the answer is "yes" — safety first: an unverifiable browser is never
# cleaned. Empty candidates (thumbnails) are never "running".
#
# Arguments: $1 — pipe-separated process basenames (e.g. "vivaldi|vivaldi-bin")
# Returns:   0 — running (or unverifiable) · 1 — not running
# ───────────────────────────────────────────────────────────────────────────────
_browserclean_is_running() {
    local cand="$1" p
    [ -n "$cand" ] || return 1
    if ! command -v pgrep > /dev/null 2>&1; then
        return 0   # cannot verify → treat as running (skip)
    fi
    local -a cands=()
    IFS='|' read -r -a cands <<< "$cand"
    for p in "${cands[@]}"; do
        pgrep -x "$p" > /dev/null 2>&1 && return 0
    done
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# browser_clean() — empty the browser cache directories
#
# Flow: collect targets → skip browsers that are currently running (warned
# even in -y mode) → measure each target with du -sm → ask once (unless -y)
# → delete the CONTENTS of each cache directory (never the directories
# themselves) → report the freed MB per browser and the total. With
# DRY_RUN=1 only the sizes are printed and nothing is deleted. By
# construction only cache subdirectories are reachable here — bookmarks,
# passwords, cookies and history are never touched.
#
# Arguments: none
# Returns:   0 — always (individual problems are reported, not propagated)
# ───────────────────────────────────────────────────────────────────────────────
browser_clean() {
    header "🧹 Browser Cache Cleanup"
    info "Only caches are touched — bookmarks, passwords, cookies and history are never touched."

    # ── collect + measure ─────────────────────────────────────────────────────
    local -a records=() plan=() _bc_paths=()
    mapfile -t records < <(_browserclean_collect)
    if [ ${#records[@]} -eq 0 ]; then
        info "No browser cache directories found — nothing to clean."
        return 0
    fi

    local rec label proc paths_str before total_mb=0
    echo ""
    echo -e "${BOLD}   ── Cache targets ──${NC}"
    for rec in "${records[@]}"; do
        IFS='|' read -r label proc paths_str <<< "$rec"
        if _browserclean_is_running "$proc"; then
            warn "$label is running — its cache is skipped for safety (close it first)"
            continue
        fi
        before=$(_browserclean_dir_mb "$paths_str")
        printf '   • %-24s %s MB\n' "$label" "$before"
        total_mb=$(( total_mb + before ))
        plan+=("$rec")
    done

    if [ ${#plan[@]} -eq 0 ]; then
        warn "Nothing was cleaned — every browser that owns a cache is running."
        return 0
    fi

    # ── dry run: sizes only, nothing is deleted ───────────────────────────────
    if [ "$DRY_RUN" = "1" ]; then
        info "DRY RUN — ${total_mb} MB would be freed. Nothing has been deleted."
        return 0
    fi

    # ── one confirmation for the whole batch ──────────────────────────────────
    confirm_action "Clean these browser caches (${total_mb} MB)?" || {
        info "Cancelled — nothing was deleted."
        return 0
    }

    # ── clean: empty each cache directory, keep the directories themselves ────
    local path after freed freed_total=0
    for rec in "${plan[@]}"; do
        IFS='|' read -r label proc paths_str <<< "$rec"
        before=$(_browserclean_dir_mb "$paths_str")
        IFS=$'\t' read -r -a _bc_paths <<< "$paths_str"
        for path in "${_bc_paths[@]}"; do
            [ -d "$path" ] && find "$path" -mindepth 1 -delete 2> /dev/null
        done
        after=$(_browserclean_dir_mb "$paths_str")
        freed=$(( before - after ))
        [ "$freed" -lt 0 ] && freed=0
        success "$label cleaned — freed ${freed} MB"
        freed_total=$(( freed_total + freed ))
    done

    echo ""
    success "Total freed: ${freed_total} MB of browser cache."
    return 0
}
