# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/swap.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Swap manager: shows what swap exists, creates or removes the classic
#  /swapfile safely, and tunes vm.swappiness. swap_show is read-only;
#  swap_on builds the file with fallocate (dd fallback), sets 0600, runs
#  mkswap + swapon and appends a marked /etc/fstab entry only when one is
#  missing; swap_off removes exactly what swap_on added (the marked fstab
#  lines) and refuses to touch swap partitions or zram devices. The
#  swappiness tune goes through set_sysctl, so the standard undo covers
#  it. Entry points: the CLI flags --swap / --swap-on [MB] / --swap-off /
#  --swappiness N and main-menu item 22.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

readonly SWAP_FILE="/swapfile"
readonly SWAP_FSTAB_MARK="# /swapfile — added by ubuntu-optimizer (uo --swap-on)"

# ───────────────────────────────────────────────────────────────────────────────
# _swap_status_mb() — the total swap in use, in whole MB
#
# Sums the size column of /proc/swaps; prints 0 when the file is missing
# or empty (containers).
#
# Arguments: none
# Returns:   prints the MB integer
# ───────────────────────────────────────────────────────────────────────────────
_swap_status_mb() {
    local file="${UO_SWAP_FAKE_SWAPS:-/proc/swaps}" total_kb=0 line kb
    [ -r "$file" ] || { echo 0; return 0; }
    while IFS= read -r line; do
        case "$line" in
            Filename*|"") continue ;;
        esac
        kb=$(printf '%s\n' "$line" | awk '{print $3}')
        [[ "$kb" =~ ^[0-9]+$ ]] && total_kb=$(( total_kb + kb ))
    done < "$file"
    echo $(( total_kb / 1024 ))
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _swap_has_file() — is there an active /swapfile?
#
# Documented test hook: UO_SWAP_FAKE_SWAPS points at another swaps listing
# than /proc/swaps for the offline test suite.
#
# Arguments: none
# Returns:   0 — the swapfile is listed as active · 1 — not
# ───────────────────────────────────────────────────────────────────────────────
_swap_has_file() {
    local file="${UO_SWAP_FAKE_SWAPS:-/proc/swaps}"
    [ -r "$file" ] || return 1
    # awk exits 0 even without a match — the output itself must be tested
    [ -n "$(awk -v f="$SWAP_FILE" '$1 == f' "$file")" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# _swap_swappiness() — the current vm.swappiness value
#
# Documented test hook: UO_SWAP_FAKE_SWAPPINESS overrides the sysfs read.
#
# Arguments: none
# Returns:   prints the value (empty when unreadable)
# ───────────────────────────────────────────────────────────────────────────────
_swap_swappiness() {
    if [ -n "${UO_SWAP_FAKE_SWAPPINESS:-}" ]; then
        echo "$UO_SWAP_FAKE_SWAPPINESS"
        return 0
    fi
    cat /proc/sys/vm/swappiness 2> /dev/null
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _swap_recommend_mb() — a swapfile size recommendation for this machine
#
# The classic table: RAM ≤ 2 GB → ×2, up to 8 GB → equal, beyond that a
# flat 4 GB (hibernation is deliberately not targeted — a swapfile added
# this way is not resume-safe anyway). Reads MemTotal from /proc/meminfo.
#
# Documented test hook: UO_SWAP_FAKE_MEMINFO points the read at another
# meminfo-format file for the offline test suite.
#
# Arguments: none
# Returns:   prints the recommended MB
# ───────────────────────────────────────────────────────────────────────────────
_swap_recommend_mb() {
    local meminfo="${UO_SWAP_FAKE_MEMINFO:-/proc/meminfo}"
    local mem_mb
    mem_mb=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' "$meminfo" 2> /dev/null)
    [[ "$mem_mb" =~ ^[0-9]+$ ]] || mem_mb=2048
    if [ "$mem_mb" -le 2048 ]; then
        echo $(( mem_mb * 2 ))
    elif [ "$mem_mb" -le 8192 ]; then
        echo "$mem_mb"
    else
        echo 4096
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _swap_swappiness_desc() — plain-language meaning of a swappiness value
#
# Arguments: $1 — swappiness value
# Returns:   prints the description
# ───────────────────────────────────────────────────────────────────────────────
_swap_swappiness_desc() {
    case "$1" in
        1|2|3|4|5|6|7|8|9|10) echo "desktop — swap only to avoid out-of-memory" ;;
        60|61|62|63|64|65|66|67|68|69|70) echo "Ubuntu default — balanced" ;;
        80|81|82|83|84|85|86|87|88|89|90|100) echo "server — swap more aggressively" ;;
        *) echo "custom" ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_show() — the swap status overview (read-only)
#
# /proc/swaps pretty-printed (file, type, size, used, priority), the total
# swap and a recommendation when none exists, plus the current swappiness
# with its meaning. Nothing is changed.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
swap_show() {
    header "💾 Swap Status"

    local file
    file="${UO_SWAP_FAKE_SWAPS:-/proc/swaps}"
    if [ -r "$file" ]; then
        echo ""
        echo -e "${BOLD}   ── Active swap devices ──${NC}"
        awk 'NR == 1 { next } { printf "   • %-20s %-6s %6d MB   used %6d MB\n", $1, $2, $3 / 1024, $4 / 1024 }' "$file" 2> /dev/null
    fi

    local total rec
    total=$(_swap_status_mb)
    if [ "$total" -gt 0 ]; then
        success "Total swap: ${total} MB"
    else
        warn "No swap is active on this machine."
        rec=$(_swap_recommend_mb)
        info "Recommendation for your RAM: a ${rec} MB swapfile (uo --swap-on)"
    fi

    local swappiness
    swappiness=$(_swap_swappiness)
    if [ -n "$swappiness" ]; then
        info "vm.swappiness = ${swappiness} ($(_swap_swappiness_desc "$swappiness"))"
        info "Tune it with: uo --swappiness 10"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_on() — create and enable /swapfile
#
# The size comes from SWAP_SIZE_MB (set by the --swap-on parser, default
# the machine recommendation). An existing active swapfile is reported and
# left alone; an existing inactive one is enabled instead of rebuilt. The
# fstab entry is appended (with the marker comment) only when missing, so
# manual edits are never duplicated. Every mutation goes through the sudo
# wrapper — --dry-run prints the exact commands.
#
# Globals:   SWAP_SIZE_MB (read), DRY_RUN (read), ASSUME_YES (via confirm)
# Arguments: none
# Returns:   0 — swap active (or nothing to do) · 1 — a step failed
# ───────────────────────────────────────────────────────────────────────────────
swap_on() {
    header "💾 Enable Swap"

    if _swap_has_file; then
        success "A swapfile is already active at $SWAP_FILE — nothing to do."
        info "Remove it first with 'uo --swap-off' if you want to change its size."
        return 0
    fi

    local size_mb="${SWAP_SIZE_MB:-}"
    if [ -z "$size_mb" ] || ! [[ "$size_mb" =~ ^[1-9][0-9]*$ ]]; then
        size_mb=$(_swap_recommend_mb)
        info "No size given — recommending ${size_mb} MB for this machine's RAM."
    fi

    info "Swapfile: $SWAP_FILE (${size_mb} MB)"
    warn "This writes a ${size_mb} MB file at the filesystem root."
    if ! confirm_action "Create and enable the ${size_mb} MB swapfile?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    # an existing but inactive swapfile is enabled, not rebuilt
    if sudo test -f "$SWAP_FILE"; then
        info "An existing $SWAP_FILE was found — enabling it instead of overwriting."
    else
        if ! sudo fallocate -l "${size_mb}M" "$SWAP_FILE" 2> /dev/null; then
            info "fallocate not supported here — falling back to dd (slower)."
            if ! sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mb" status=progress; then
                failure "Could not create $SWAP_FILE."
                return 1
            fi
        fi
    fi

    if ! sudo chmod 600 "$SWAP_FILE" \
       || ! sudo mkswap "$SWAP_FILE" \
       || ! sudo swapon "$SWAP_FILE"; then
        failure "Could not prepare $SWAP_FILE (chmod/mkswap/swapon)."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] The ${size_mb} MB swapfile would be enabled now."
        return 0
    fi
    success "Swap enabled: $SWAP_FILE (${size_mb} MB)."

    # fstab entry — appended only when this exact entry is missing
    if ! sudo grep -q "^${SWAP_FILE}[[:space:]]" /etc/fstab 2> /dev/null; then
        if { echo "$SWAP_FSTAB_MARK"; echo "$SWAP_FILE none swap sw 0 0"; } | sudo tee -a /etc/fstab > /dev/null; then
            success "fstab entry added (survives reboots)."
        else
            warn "Could not edit /etc/fstab — the swap works now but will not survive a reboot."
        fi
    else
        info "An fstab entry for $SWAP_FILE already exists — left untouched."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_off() — disable and remove the /swapfile
#
# Only ever touches $SWAP_FILE: swap partitions and zram devices are not
# ours to remove and are reported instead. The marked fstab lines are
# deleted with sed (both the marker comment and the swapfile line), so
# manual fstab content stays intact. Everything runs through the sudo
# wrapper — --dry-run prints the plan.
#
# Globals:   DRY_RUN (read), ASSUME_YES (via confirm)
# Arguments: none
# Returns:   0 — swap removed (or nothing to do) · 1 — a step failed
# ───────────────────────────────────────────────────────────────────────────────
swap_off() {
    header "💾 Remove Swapfile"

    if ! sudo test -f "$SWAP_FILE"; then
        info "No $SWAP_FILE exists — nothing to remove."
        return 0
    fi

    warn "The swap file $SWAP_FILE will be switched off and DELETED."
    if ! confirm_action "Remove $SWAP_FILE?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    if _swap_has_file; then
        if sudo swapoff "$SWAP_FILE"; then
            success "Swap disabled."
        else
            failure "swapoff failed — the system may currently be swapping heavily."
            return 1
        fi
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] $SWAP_FILE would be deleted and the fstab line removed."
        return 0
    fi

    if sudo rm -f "$SWAP_FILE"; then
        success "$SWAP_FILE deleted."
    else
        failure "Could not delete $SWAP_FILE."
        return 1
    fi

    # remove exactly the marked fstab lines (comment + entry)
    if sudo grep -qF "$SWAP_FSTAB_MARK" /etc/fstab 2> /dev/null; then
        if sudo sed -i "\|^${SWAP_FSTAB_MARK}\$|d; \|^${SWAP_FILE}[[:space:]]|d" /etc/fstab; then
            success "fstab entry removed."
        else
            warn "Could not edit /etc/fstab — remove the $SWAP_FILE line manually."
        fi
    fi
    success "Swap removal finished."
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_swappiness() — tune vm.swappiness
#
# The value comes from SWAP_SWAPPINESS (set by the --swappiness parser and
# validated there, 1–100). Written through set_sysctl into the project's
# sysctl drop-in — the standard undo (`uo --undo`) therefore covers it —
# and applied immediately with apply_sysctl. In dry-run mode the sudo
# wrapper prints the writes instead of executing them.
#
# Globals:   SWAP_SWAPPINESS (read), DRY_RUN (read), ASSUME_YES (via confirm)
# Arguments: none
# Returns:   0 — applied (or declined) · 1 — the write failed
# ───────────────────────────────────────────────────────────────────────────────
swap_swappiness() {
    local value="${SWAP_SWAPPINESS:-}"
    if [ -z "$value" ] || ! [[ "$value" =~ ^([1-9][0-9]?|100)$ ]]; then
        value=10
        info "No value given — using the desktop default 10."
    fi

    header "💾 Swappiness → ${value}"
    info "Meaning: $(_swap_swappiness_desc "$value")"
    if ! confirm_action "Set vm.swappiness to ${value}?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    if set_sysctl vm.swappiness "$value" && apply_sysctl; then
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] vm.swappiness = ${value} would be set now."
        else
            success "vm.swappiness = ${value} — applied now and persistent."
            info "Revert with: uo --undo"
        fi
        return 0
    fi
    failure "Could not set vm.swappiness."
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_menu_on() — interactive size prompt → swap_on (menu entry)
#
# Reads the size (MB) with the machine recommendation as the default, then
# runs the standard swap_on flow.
#
# Globals:   SWAP_SIZE_MB (written)
# Arguments: none
# Returns:   exit status of swap_on
# ───────────────────────────────────────────────────────────────────────────────
swap_menu_on() {
    local rec answer
    rec=$(_swap_recommend_mb)
    echo ""
    read -r -p "   Swapfile size in MB [${rec}]: " answer || return 0
    if [ -z "$answer" ]; then
        SWAP_SIZE_MB="$rec"
    else
        if ! [[ "$answer" =~ ^[1-9][0-9]*$ ]]; then
            warn "Invalid size: '$answer' — cancelled."
            return 0
        fi
        SWAP_SIZE_MB="$answer"
    fi
    swap_on
}

# ───────────────────────────────────────────────────────────────────────────────
# swap_menu_swappiness() — interactive value prompt → swap_swappiness (menu entry)
#
# Globals:   SWAP_SWAPPINESS (written)
# Arguments: none
# Returns:   exit status of swap_swappiness
# ───────────────────────────────────────────────────────────────────────────────
swap_menu_swappiness() {
    local answer
    echo ""
    read -r -p "   New vm.swappiness (1–100) [10]: " answer || return 0
    if [ -z "$answer" ]; then
        SWAP_SWAPPINESS="10"
    else
        if ! [[ "$answer" =~ ^([1-9][0-9]?|100)$ ]]; then
            warn "Invalid value: '$answer' — cancelled."
            return 0
        fi
        SWAP_SWAPPINESS="$answer"
    fi
    swap_swappiness
}
