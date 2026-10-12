# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/disk.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Read-only disk space analysis and an interactive cleanup pass (apt cache,
#  journald, crash reports, old snap revisions, old kernels, autoremove).
#  Entry points: menu items 15/16 and the CLI flags --disk / --disk-clean.
#  The cleanup has no dry-run mode — documented in --help.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _disk_avail_mb() — free space of a mount point, in whole MB
#
# Reads df's "avail" column in 1K blocks — other "-B" units print a suffix
# (kB/MB) that would break arithmetic — and converts to MB. Prints nothing
# on failure so callers can treat empty output as "unknown".
#
# Arguments: $1 — mount point path (default /)
# Returns:   0 — MB value printed
#            1 — df failed or output not numeric (nothing printed)
# ───────────────────────────────────────────────────────────────────────────────
_disk_avail_mb() {   # $1=path (default /)
    local kb
    kb=$(df --output=avail -k "${1:-/}" 2>/dev/null | tail -n 1 | tr -d ' ')
    [[ "$kb" =~ ^[0-9]+$ ]] || return 1
    printf '%s' $((kb / 1024))
}

# ───────────────────────────────────────────────────────────────────────────────
# _old_kernel_pkgs() — list removable kernel image packages
#
# Prints every installed linux-image-* package except the running kernel
# and the newest installed one, so a fallback kernel is always kept.
# Version-sorted (sort -V) to determine the newest.
#
# Arguments: none
# Returns:   0 — always (output may be empty)
# ───────────────────────────────────────────────────────────────────────────────
_old_kernel_pkgs() {
    local current pkg newest
    local -a all=()
    current="linux-image-$(uname -r)"
    mapfile -t all < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-[0-9]*' 2>/dev/null \
        | awk '$1 == "ii" {print $2}' | sort -V)
    [ ${#all[@]} -gt 0 ] || return 0
    newest="${all[-1]}"
    for pkg in "${all[@]}"; do
        [ "$pkg" = "$current" ] && continue
        [ "$pkg" = "$newest" ] && continue
        printf '%s\n' "$pkg"
    done
}

# ── Analyzer ──────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# disk_analyze() — print a read-only disk space analysis
#
# Shows root filesystem usage with a low-space warning (< 2 GB free), a size
# breakdown by category (apt cache, snap, /opt, ~/.local, logs, crashes,
# Timeshift, old-kernel count), the ten largest /opt entries and the ten
# largest deb packages. Read-only apart from the sudo du/find probes; ends
# with one INFO log line.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
disk_analyze() {
    header "📊 Disk Space Analysis"

    local total used avail pct
    read -r total used avail pct <<< "$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')"
    echo "   Total: $total  |  Used: $used ($pct)  |  Free: $avail"
    echo ""

    # Threshold warning — a finding, not a failure of the tool
    local avail_mb
    avail_mb=$(_disk_avail_mb /)
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt 2048 ]; then
        warn "Low disk space! (${avail_mb} MB free)"
        info "Run 'uo --disk-clean' to free space."
        echo ""
    fi

    # ---- breakdown ----
    echo -e "${BOLD}── Space by Category ──${NC}"

    local apt_cache opt_dir home_local snap_dir log_dir crash_dir
    apt_cache=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
    opt_dir=$(du -sh /opt 2>/dev/null | cut -f1)
    home_local=$(du -sh "$HOME/.local" 2>/dev/null | cut -f1)
    snap_dir=$(sudo du -sh /var/lib/snapd 2>/dev/null | cut -f1)
    log_dir=$(sudo du -sh /var/log 2>/dev/null | cut -f1)
    crash_dir=$(sudo du -sh /var/crash 2>/dev/null | cut -f1)
    # Timeshift snapshots
    if [ -d /timeshift ]; then
        local ts_size ts_count
        ts_size=$(sudo du -sh /timeshift 2>/dev/null | cut -f1)
        ts_count=$(sudo find /timeshift/snapshots -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        [ -n "$ts_size" ] && printf "   • Timeshift:      %s (%s snapshots)\n" "$ts_size" "$ts_count"
    fi

    [ -n "$apt_cache" ] && printf "   • apt cache:      %s\n" "$apt_cache"
    [ -n "$snap_dir" ] && printf "   • snap:           %s\n" "$snap_dir"
    [ -n "$opt_dir" ] && printf "   • /opt (apps):    %s\n" "$opt_dir"
    [ -n "$home_local" ] && printf "   • ~/.local:        %s\n" "$home_local"
    [ -n "$log_dir" ] && printf "   • /var/log:       %s\n" "$log_dir"
    [ -n "$crash_dir" ] && printf "   • /var/crash:      %s\n" "$crash_dir"

    # Old kernels
    local -a old_kernels=()
    mapfile -t old_kernels < <(_old_kernel_pkgs)
    [ ${#old_kernels[@]} -gt 0 ] && printf "   • Old kernels:    %s (removable)\n" "${#old_kernels[@]}"

    echo ""

    # ---- /opt breakdown ----
    echo -e "${BOLD}── /opt (apps) ──${NC}"
    sudo du -sh /opt/*/ 2>/dev/null | sort -rh | head -10 | while read -r size name; do
        printf "   • %-30s %s\n" "$(basename "$name")" "$size"
    done

    # ---- largest packages ----
    echo ""
    echo -e "${BOLD}── Largest deb packages ──${NC}"
    dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' 2>/dev/null \
        | sort -rn | head -10 | awk '{printf "   • %-25s %.0f MB\n", $2, $1/1024}'

    log_write "INFO" "disk analysis shown"
    return 0
}

# ── Cleanup ────────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# disk_cleanup() — free disk space interactively (no dry-run support)
#
# After an explicit confirmation: cleans the apt cache, vacuums journald
# logs to 100 MB, removes crash reports, deletes disabled snap revisions,
# runs apt autoremove and — asked separately — purges old kernels together
# with their headers/modules siblings (the running and newest kernel are
# always kept). Measures freed space via _disk_avail_mb before/after and
# logs the result.
#
# Arguments: none
# Returns:   0 — always (individual failures are reported, not propagated)
# ───────────────────────────────────────────────────────────────────────────────
disk_cleanup() {
    header "🧹 Disk Cleanup"

    info "This will:"
    echo "      • clean the apt cache"
    echo "      • vacuum the journald logs to 100MB"
    echo "      • remove crash reports"
    echo "      • remove old (disabled) snap revisions"
    echo "      • remove old kernels (asked separately; the running and newest are kept)"
    echo "      • run apt autoremove (unused dependencies)"
    confirm_action "Proceed with the cleanup?" || { info "Cancelled."; return 0; }

    local before after freed_mb
    before=$(_disk_avail_mb /)

    # apt cache — the result is reported honestly, not unconditionally
    if sudo apt clean 2>/dev/null && sudo apt autoclean 2>/dev/null; then
        success "apt cache cleaned."
    else
        warn "apt cache cleanup failed."
    fi

    # Old kernels — only installed packages are purged: apt rejects the whole
    # command when one of the names does not exist
    local -a old_kernels=() purge_list=()
    local k p
    mapfile -t old_kernels < <(_old_kernel_pkgs)
    if [ ${#old_kernels[@]} -gt 0 ]; then
        info "Old kernels (the running and the newest kernel are always kept):"
        printf '      • %s\n' "${old_kernels[@]}"
        if confirm_action "Remove these ${#old_kernels[@]} old kernel(s)?"; then
            for k in "${old_kernels[@]}"; do
                purge_list+=("$k")
                for p in "${k/linux-image/linux-headers}" \
                         "${k/linux-image/linux-modules}" \
                         "${k/linux-image/linux-modules-extra}"; do
                    pkg_installed "$p" && purge_list+=("$p")
                done
            done
            if sudo apt purge -y "${purge_list[@]}" > /dev/null 2>&1; then
                success "Old kernels removed: ${old_kernels[*]}"
            else
                failure "Failed to remove the old kernels."
            fi
        else
            info "Old kernels kept."
        fi
    fi

    # journald
    if command -v journalctl > /dev/null 2>&1; then
        info "Vacuuming journald logs to 100MB..."
        if sudo journalctl --vacuum-size=100M > /dev/null 2>&1; then
            success "journald vacuumed."
        else
            warn "journald vacuum failed."
        fi
    fi

    # crash reports
    if [ -d /var/crash ] && [ -n "$(ls -A /var/crash 2>/dev/null)" ]; then
        info "Removing crash reports..."
        if sudo find /var/crash -mindepth 1 -delete 2>/dev/null; then
            success "Crash reports removed."
        else
            warn "Crash reports could not be removed."
        fi
    fi

    # snap old revisions
    if command -v snap > /dev/null 2>&1; then
        local -a snap_old=()
        local entry name rev snap_fail=0
        mapfile -t snap_old < <(snap list --all 2>/dev/null | awk '/disabled/ {print $1" "$3}')
        if [ ${#snap_old[@]} -gt 0 ]; then
            info "Removing ${#snap_old[@]} old snap revisions..."
            for entry in "${snap_old[@]}"; do
                read -r name rev <<< "$entry"
                sudo snap remove "$name" --revision="$rev" > /dev/null 2>&1 || snap_fail=1
            done
            if [ "$snap_fail" = "0" ]; then
                success "Old snap revisions removed."
            else
                warn "Some old snap revisions could not be removed."
            fi
        fi
    fi

    # apt autoremove
    info "Running apt autoremove..."
    if sudo apt autoremove -y > /dev/null 2>&1; then
        success "Autoremove completed."
    else
        warn "Autoremove failed."
    fi

    after=$(_disk_avail_mb /)
    echo ""
    if [ -n "$before" ] && [ -n "$after" ]; then
        freed_mb=$((after - before))
        [ "$freed_mb" -lt 0 ] && freed_mb=0
        success "Approximately ${freed_mb}MB freed."
    else
        freed_mb="?"
        info "Freed space could not be measured."
    fi
    df -h /
    log_write "INFO" "disk cleanup done (${freed_mb}MB freed)"
    return 0
}

# ── Pre-install disk check ─────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# disk_check_install() — guard required free space before an install
#
# Compares the free space on / with the required amount and points the user
# to 'uo --disk-clean' when it is insufficient. Fails open: when the value
# cannot be determined the check is skipped so installs are never blocked
# by a df quirk.
#
# Arguments: $1 — required free space in MB (default 500)
# Returns:   0 — enough space, or free space undeterminable
#            1 — insufficient disk space
# ───────────────────────────────────────────────────────────────────────────────
disk_check_install() {   # $1=required MB (default 500)
    local required="${1:-500}"
    local avail_mb
    avail_mb=$(_disk_avail_mb /)
    if [ -z "$avail_mb" ]; then
        info "Free disk space could not be determined; check skipped."
        return 0
    fi
    if [ "$avail_mb" -lt "$required" ]; then
        failure "Insufficient disk space: ${avail_mb}MB free (need ${required}MB)."
        info "Run: uo --disk-clean"
        return 1
    fi
    return 0
}
