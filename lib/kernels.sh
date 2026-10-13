# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/kernels.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Old-kernel cleanup: Ubuntu keeps every kernel it ever installed, and
#  /boot slowly fills up. kernels_show lists what is installed (and which
#  one is running); kernels_clean removes the kernels that are neither
#  running nor among the newest — by default everything except the running
#  kernel and one spare, adjustable with UO_KERNEL_KEEP. The running kernel
#  and the newest kernel are protected by construction and can never be
#  selected for removal. Works from the /boot/vmlinuz-* listing and purges
#  the matching linux-image / -modules / -headers packages through the
#  sudo wrapper, so --dry-run prints the exact purge plan. Entry points:
#  the CLI flags --kernel-list / --kernel-clean and main-menu item 22.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_boot_dir() — the directory the kernel listing reads
#
# Documented test hook: UO_KERNEL_BOOT_DIR points the listing at another
# directory than /boot (the offline test suite builds a fake tree). Not
# part of the user-facing configuration.
#
# Arguments: none
# Returns:   prints the boot directory path
# ───────────────────────────────────────────────────────────────────────────────
_kernels_boot_dir() {
    echo "${UO_KERNEL_BOOT_DIR:-/boot}"
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_running() — the version of the currently running kernel
#
# Documented test hook: UO_KERNEL_FAKE_RUNNING overrides `uname -r` for
# the offline test suite. Not part of the user-facing configuration.
#
# Arguments: none
# Returns:   prints the running kernel version
# ───────────────────────────────────────────────────────────────────────────────
_kernels_running() {
    echo "${UO_KERNEL_FAKE_RUNNING:-$(uname -r 2> /dev/null)}"
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_installed() — every kernel version found in the boot directory
#
# Reads the vmlinuz-* basenames and sorts them newest-last with sort -V
# (so 6.8.0-51-generic sorts before 6.8.0-52-generic). Symlinked or
# unreadable entries degrade to "not installed" and are skipped silently.
#
# Arguments: none
# Returns:   prints one version per line, oldest first; nothing on error
# ───────────────────────────────────────────────────────────────────────────────
_kernels_installed() {
    local dir f
    dir=$(_kernels_boot_dir)
    [ -d "$dir" ] || return 0
    for f in "$dir"/vmlinuz-*; do
        [ -e "$f" ] || continue
        basename -- "$f" | sed 's/^vmlinuz-//'
    done | sort -V
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_newest() — the newest installed kernel version
#
# Arguments: none
# Returns:   prints the version (empty when none is installed)
# ───────────────────────────────────────────────────────────────────────────────
_kernels_newest() {
    _kernels_installed | tail -n 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_packages_for() — the deb packages that make up one kernel
#
# Exact-prefix matching keeps the meta packages (linux-generic,
# linux-image-generic, …) untouchable: only linux-image-VER,
# linux-image-unsigned-VER, linux-modules-VER, linux-modules-extra-VER and
# linux-headers-VER are returned, and only those actually installed.
#
# Arguments: $1 — kernel version (e.g. 6.8.0-45-generic)
# Returns:   prints one package name per line (may be empty)
# ───────────────────────────────────────────────────────────────────────────────
_kernels_packages_for() {
    local ver="$1" prefix
    [ -n "$ver" ] || return 0
    command -v dpkg-query > /dev/null 2>&1 || return 0
    for prefix in "linux-image-" "linux-image-unsigned-" "linux-modules-" "linux-modules-extra-" "linux-headers-"; do
        if pkg_installed "${prefix}${ver}"; then
            echo "${prefix}${ver}"
        fi
    done
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_keep_count() — how many kernels to keep (running one included)
#
# UO_KERNEL_KEEP overrides the default of 2 (the running kernel + one
# spare to boot into if an update misbehaves). The floor is 2 — keeping
# only the running kernel would leave no fallback and is refused.
#
# Arguments: none
# Returns:   prints the keep count (always ≥ 2)
# ───────────────────────────────────────────────────────────────────────────────
_kernels_keep_count() {
    local keep="${UO_KERNEL_KEEP:-2}"
    [[ "$keep" =~ ^[1-9][0-9]*$ ]] || keep=2
    [ "$keep" -lt 2 ] && keep=2
    echo "$keep"
}

# ───────────────────────────────────────────────────────────────────────────────
# _kernels_remove_candidates() — the versions that may be purged
#
# The protected set is computed first: the running kernel, the newest
# kernel, and the (keep - 1) newest spares. Everything older is a
# candidate. The running kernel is protected even when it is itself an
# old one — a machine pinned to an LTS kernel must never lose it.
#
# Globals:   none (reads the boot tree and uname via the helpers above)
# Arguments: none
# Returns:   prints one candidate version per line (oldest first)
# ───────────────────────────────────────────────────────────────────────────────
_kernels_remove_candidates() {
    local -a installed=() protected=() candidates=()
    mapfile -t installed < <(_kernels_installed)
    [ ${#installed[@]} -gt 0 ] || return 0
    local running newest keep
    running=$(_kernels_running)
    newest=$(_kernels_newest)
    keep=$(_kernels_keep_count)

    # the (keep - 1) newest spares — the last entries of the sorted list
    local i
    for (( i=${#installed[@]} - 2; i >= 0 && ${#protected[@]} < keep - 1; i-- )); do
        protected+=("${installed[i]}")
    done
    protected+=("$running" "$newest")

    local ver is_protected p
    for ver in "${installed[@]}"; do
        is_protected=0
        for p in "${protected[@]}"; do
            [ "$ver" = "$p" ] && { is_protected=1; break; }
        done
        [ "$is_protected" = "0" ] && candidates+=("$ver")
    done

    if [ ${#candidates[@]} -gt 0 ]; then
        printf '%s\n' "${candidates[@]}"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# kernels_show() — list the installed kernels (read-only)
#
# One line per kernel: version, a RUNNING / newest marker, and the disk
# space its packages occupy (dpkg Installed-Size in whole MB, "--" when
# the package data is not available). Closes with a hint at
# --kernel-clean when removal candidates exist.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
kernels_show() {
    header "🐧 Installed Kernels"

    local -a installed=()
    mapfile -t installed < <(_kernels_installed)
    if [ ${#installed[@]} -eq 0 ]; then
        info "No kernels found in $(_kernels_boot_dir) — nothing to list."
        return 0
    fi

    local running newest ver marker pkgs pkg size_kb total_kb
    running=$(_kernels_running)
    newest=$(_kernels_newest)
    echo ""
    echo -e "${BOLD}   ── Installed kernels (oldest first) ──${NC}"
    for ver in "${installed[@]}"; do
        marker=""
        [ "$ver" = "$running" ] && marker="${GREEN} ← running${NC}"
        [ "$ver" = "$newest" ] && marker="${marker}${BOLD} · newest${NC}"
        # the size of every package that belongs to this kernel
        total_kb=0
        while IFS= read -r pkg; do
            [ -n "$pkg" ] || continue
            size_kb=$(dpkg-query -W -f='${Installed-Size}' "$pkg" 2> /dev/null)
            [[ "$size_kb" =~ ^[0-9]+$ ]] && total_kb=$(( total_kb + size_kb ))
        done < <(_kernels_packages_for "$ver")
        if [ "$total_kb" -gt 0 ]; then
            printf '   • %-28s %6d MB%s\n' "$ver" "$(( total_kb / 1024 ))" "$marker"
        else
            printf '   • %-28s      --%s\n' "$ver" "$marker"
        fi
    done

    local -a cand=()
    mapfile -t cand < <(_kernels_remove_candidates)
    echo ""
    if [ ${#cand[@]} -gt 0 ]; then
        warn "${#cand[@]} old kernel(s) could be removed — run 'uo --kernel-clean' to free the space."
    else
        success "No old kernels — nothing to clean."
    fi
    info "Keep count is adjustable: UO_KERNEL_KEEP=N (default 2, minimum 2)."
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# kernels_clean() — remove the old kernels
#
# Flow: candidates → the exact package purge list → plan → confirm →
# apt purge → autoremove → report. The running and the newest kernel are
# excluded by _kernels_remove_candidates, so they can never appear in the
# plan. Every mutation goes through the sudo wrapper (--dry-run prints
# the plan). When dpkg is missing the purge list stays empty and the run
# reports "nothing to do" instead of touching /boot by hand.
#
# Globals:   DRY_RUN (read); ASSUME_YES (read via confirm_action)
# Arguments: none
# Returns:   0 — nothing to do, declined, or the purge succeeded
#            1 — at least one package purge failed
# ───────────────────────────────────────────────────────────────────────────────
kernels_clean() {
    header "🧹 Old Kernel Cleanup"
    info "The running kernel and the newest one are always protected."

    local -a cand=()
    mapfile -t cand < <(_kernels_remove_candidates)
    if [ ${#cand[@]} -eq 0 ]; then
        info "No old kernels found — nothing to clean."
        return 0
    fi

    # ── build the exact package list ───────────────────────────────────────────
    local -a purge_list=()
    local ver pkg
    for ver in "${cand[@]}"; do
        while IFS= read -r pkg; do
            [ -n "$pkg" ] && purge_list+=("$pkg")
        done < <(_kernels_packages_for "$ver")
    done
    if [ ${#purge_list[@]} -eq 0 ]; then
        info "Old kernels were found but no matching packages are registered with dpkg."
        info "The /boot files were probably placed manually — nothing will be removed."
        return 0
    fi

    # ── plan ───────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}   ── Kernels to remove ──${NC}"
    for ver in "${cand[@]}"; do
        printf '   • %s\n' "$ver"
    done
    echo ""
    echo -e "${BOLD}   ── Packages to purge ──${NC}"
    printf '   • %s\n' "${purge_list[@]}"
    echo ""
    warn "A reboot is recommended afterwards — but you can keep working until then."
    if ! confirm_action "Remove ${#cand[@]} old kernel(s) (${#purge_list[@]} packages)?"; then
        info "Cancelled — nothing was removed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    # ── purge ─────────────────────────────────────────────────────────────────
    local rc=0
    if sudo apt-get purge -y "${purge_list[@]}"; then
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] ${#purge_list[@]} kernel packages would be removed."
            return 0
        fi
        success "${#purge_list[@]} kernel packages removed."
    else
        failure "apt purge failed — see the apt messages above."
        rc=1
    fi
    # sweep the now-orphaned dependencies (older kernel headers chains)
    if sudo apt-get autoremove --purge -y; then
        success "Orphaned dependencies removed."
    else
        warn "autoremove reported problems — the kernels are already gone; check manually."
    fi

    if [ "$rc" -eq 0 ]; then
        success "Kernel cleanup finished — /boot has room for the next updates again."
    else
        warn "Kernel cleanup finished with errors — see the messages above."
    fi
    return "$rc"
}
