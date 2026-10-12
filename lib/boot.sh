# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/boot.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Boot time diagnostics: how long the machine takes to reach a usable state,
#  which units slow the boot down and which units failed. Fully read-only —
#  nothing here mutates the system, so it is safe on every machine (servers,
#  WSL, containers). On systems without systemd every entry degrades to a
#  friendly hint instead of an error. Entry points: the CLI flags --boot,
#  main-menu item 20 and the --boot submenu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _boot_have_systemd() — is this machine actually running systemd?
#
# /run/systemd/system exists only under a live systemd user space — the
# canonical marker for "systemd tools will answer". WSL, chroots and most
# containers have it missing.
#
# Documented disable (test hook): UO_BOOT_FAKE_SYSTEMD=1 forces the "present"
# verdict so the offline test suite can exercise the systemd-present paths
# with stubbed systemd-analyze/systemctl on machines without systemd. The
# variable is not part of the user-facing configuration.
#
# Arguments: none
# Returns:   0 — systemd present · 1 — not present
# ───────────────────────────────────────────────────────────────────────────────
_boot_have_systemd() {
    [ -d /run/systemd/system ] && return 0
    [ "${UO_BOOT_FAKE_SYSTEMD:-0}" = "1" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# _boot_seconds() — convert a systemd time literal to seconds
#
# Accepts the literals systemd prints: "9.378s", "1min 9.378s", "2min",
# "1h 2min". Anything unparsable becomes 0, so a verdict computed from the
# result stays on the safe "no verdict" path.
#
# Arguments: $1 — time literal (e.g. the total field of systemd-analyze)
# Returns:   prints the seconds as an integer (truncated)
# ───────────────────────────────────────────────────────────────────────────────
_boot_seconds() {
    local spec="$1" total=0 chunk num
    for chunk in $spec; do
        case "$chunk" in
            *min*) num="${chunk%%min*}" ;;
            *h*)   num="${chunk%%h*}" ;;
            *s*)   num="${chunk%%s*}" ;;
            *)     num="$chunk" ;;
        esac
        case "$num" in
            ''|*[!0-9.]*) continue ;;   # unparsable chunk — skip it
        esac
        case "$chunk" in
            *min*) total=$(awk -v t="$total" -v n="$num" 'BEGIN { printf "%.0f", t + n * 60 }') ;;
            *h*)   total=$(awk -v t="$total" -v n="$num" 'BEGIN { printf "%.0f", t + n * 3600 }') ;;
            *)     total=$(awk -v t="$total" -v n="$num" 'BEGIN { printf "%.0f", t + n }') ;;
        esac
    done
    echo "$total"
}

# ───────────────────────────────────────────────────────────────────────────────
# _boot_verdict() — human verdict for a total boot time
#
# Arguments: $1 — total seconds (integer)
# Returns:   prints the verdict text
# ───────────────────────────────────────────────────────────────────────────────
_boot_verdict() {
    local secs="$1"
    if [ "$secs" -le 0 ]; then
        echo ""
    elif [ "$secs" -lt 20 ]; then
        echo "Excellent — the machine boots fast"
    elif [ "$secs" -lt 40 ]; then
        echo "Good — but there is room to shave a few seconds"
    elif [ "$secs" -lt 60 ]; then
        echo "Slow — the blame list below shows what to look at"
    else
        echo "Very slow — check the blame list and the startup applications"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# boot_show() — full boot time analysis (read-only)
#
# Three systemd-analyze views plus the failed unit list:
#   • total boot time (kernel + initrd + userspace) with a verdict
#   • the ten slowest units (systemd-analyze blame)
#   • the critical chain (the units the boot actually waited for)
#   • failed units from systemctl --failed
# Without systemd every section degrades to an info line and the run still
# succeeds (exit 0) — diagnostics must never fail the session.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
boot_show() {
    header "Boot Time Analysis"

    if ! _boot_have_systemd || ! command -v systemd-analyze > /dev/null 2>&1; then
        info "systemd is not available on this machine (container/WSL?) — boot analysis skipped"
        return 0
    fi

    # ── 1. total boot time ────────────────────────────────────────────────────
    local boot_line total verdict
    boot_line=$(systemd-analyze 2> /dev/null | tail -n1)
    if [ -n "$boot_line" ]; then
        echo -e "${BOLD}   Startup finished:${NC} $boot_line"
        # the total is the field after the final '=' (e.g. "1min 9.378s")
        total="${boot_line##*= }"
        total=$(_boot_seconds "$total")
        verdict=$(_boot_verdict "$total")
        [ -n "$verdict" ] && info "$verdict"
    else
        info "systemd-analyze returned no boot time (first boot?)"
    fi
    echo ""

    # ── 2. slowest units ──────────────────────────────────────────────────────
    echo -e "${BOLD}   ── 10 slowest units (blame) ──${NC}"
    local blame_out
    blame_out=$(systemd-analyze blame 2> /dev/null | head -n 10)
    if [ -n "$blame_out" ]; then
        printf '%s\n' "$blame_out" | while IFS= read -r bl; do
            printf '   %s\n' "$bl"
        done
    else
        info "blame data not available"
    fi
    echo ""

    # ── 3. critical chain ─────────────────────────────────────────────────────
    echo -e "${BOLD}   ── Critical chain (what the boot waited for) ──${NC}"
    local chain_out
    chain_out=$(systemd-analyze critical-chain 2> /dev/null)
    if [ -n "$chain_out" ]; then
        printf '%s\n' "$chain_out" | while IFS= read -r cl; do
            printf '   %s\n' "$cl"
        done
    else
        info "critical chain not available (needs a readable system bus)"
    fi
    echo ""

    # ── 4. failed units ───────────────────────────────────────────────────────
    boot_failed_list
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# boot_failed_list() — print the failed unit section (no header)
#
# Shared by boot_show (section 4) and the standalone boot_failed_show entry.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
boot_failed_list() {
    if ! _boot_have_systemd || ! command -v systemctl > /dev/null 2>&1; then
        info "systemd is not available — failed-unit check skipped"
        return 0
    fi
    echo -e "${BOLD}   ── Failed units ──${NC}"
    local failed_out
    failed_out=$(systemctl --failed --no-legend --no-pager 2> /dev/null)
    if [ -n "$failed_out" ]; then
        local count
        count=$(printf '%s\n' "$failed_out" | wc -l)
        warn "$count failed unit(s):"
        printf '%s\n' "$failed_out" | while IFS= read -r fl; do
            # keep only the unit name column — the load/active/sub columns
            # waste width and the details live in `systemctl status UNIT`
            printf '   • %s\n' "${fl%% *}"
        done
        info "inspect a unit with: systemctl status UNIT — or try 'uo --fixnet-run' / 'uo --doctor'"
    else
        success "No failed units"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# boot_failed_show() — failed system units only (read-only)
#
# Standalone entry for the --boot submenu: header + the failed-unit section.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
boot_failed_show() {
    header "Failed System Units"
    boot_failed_list
    return 0
}
