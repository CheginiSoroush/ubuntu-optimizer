# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/health.sh
# ───────────────────────────────────────────────────────────────────────────────
#  One-shot read-only system health snapshot: load, memory, disk, temperature,
#  battery, failed units, pending updates and uptime. Everything is gathered
#  from /proc, /sys and standard tools — nothing is executed, nothing mutates
#  the system, and every section degrades to an info line when its data source
#  is missing (WSL, containers, headless servers). The whole command always
#  exits 0 — diagnostics must never fail the session. Entry points: the CLI
#  flag --health and the "Monitor & inspect" submenu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _health_have_systemd() — is this machine actually running systemd?
#
# Same marker file the boot module uses (/run/systemd/system exists only under
# a live systemd user space). WSL, chroots and most containers miss it.
#
# Documented disable (test hook): UO_HEALTH_FAKE_SYSTEMD=1 forces the
# "present" verdict so the offline test suite can exercise the systemd-present
# paths with a stubbed systemctl on machines without systemd. The variable is
# not part of the user-facing configuration.
#
# Arguments: none
# Returns:   0 — systemd present · 1 — not present
# ───────────────────────────────────────────────────────────────────────────────
_health_have_systemd() {
    [ -d /run/systemd/system ] && return 0
    [ "${UO_HEALTH_FAKE_SYSTEMD:-0}" = "1" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# _health_ram_pct() — used memory percentage from total/available kB values
#
# Both inputs are the kB integers /proc/meminfo reports. "Used" here is what
# the kernel reports as unavailable (total − available), which is what the
# `free` command and every desktop monitor show as well.
#
# Arguments: $1 — MemTotal in kB · $2 — MemAvailable in kB
# Returns:   prints the used percentage as an integer (0 when total is 0)
# ───────────────────────────────────────────────────────────────────────────────
_health_ram_pct() {
    local total="$1" avail="$2"
    case "$total" in ''|*[!0-9]*) echo 0; return 0 ;; esac
    case "$avail" in ''|*[!0-9]*) echo 0; return 0 ;; esac
    [ "$total" -le 0 ] && { echo 0; return 0; }
    local used=$(( total - avail ))
    [ "$used" -lt 0 ] && used=0
    echo $(( used * 100 / total ))
}

# ───────────────────────────────────────────────────────────────────────────────
# _health_verdict() — plain-language verdict for a memory usage percentage
#
# Arguments: $1 — used percentage (integer)
# Returns:   prints "ok" (<70) · "watch" (<85) · "high" (>=85)
# ───────────────────────────────────────────────────────────────────────────────
_health_verdict() {
    local pct="$1"
    case "$pct" in ''|*[!0-9]*) echo "ok"; return 0 ;; esac
    if [ "$pct" -lt 70 ]; then
        echo "ok"
    elif [ "$pct" -lt 85 ]; then
        echo "watch"
    else
        echo "high"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _health_human_kb() — format a /proc/meminfo kB value for humans
#
# Arguments: $1 — size in kB
# Returns:   prints e.g. "15.6 GB", "923 MB" or "512 kB"
# ───────────────────────────────────────────────────────────────────────────────
_health_human_kb() {
    local kb="$1"
    case "$kb" in ''|*[!0-9]*) echo "unknown"; return 0 ;; esac
    if [ "$kb" -ge 1048576 ]; then
        awk -v kb="$kb" 'BEGIN { printf "%.1f GB", kb / 1048576 }'
    elif [ "$kb" -ge 1024 ]; then
        awk -v kb="$kb" 'BEGIN { printf "%.1f MB", kb / 1024 }'
    else
        printf '%s kB' "$kb"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _health_uptime_human() — uptime seconds in plain words
#
# Two significant units only: days + hours, hours + minutes, or a single
# unit below that. Singular/plural handled ("1 day, 4 hours").
#
# Arguments: $1 — uptime in whole seconds
# Returns:   prints e.g. "3 days, 4 hours"; empty for unparsable input
# ───────────────────────────────────────────────────────────────────────────────
_health_uptime_human() {
    local s="$1"
    case "$s" in ''|*[!0-9]*) return 0 ;; esac
    local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
    local -a parts=()
    if [ "$d" -gt 0 ]; then
        [ "$d" -eq 1 ] && parts+=("1 day") || parts+=("$d days")
        [ "$h" -gt 0 ] && { [ "$h" -eq 1 ] && parts+=("1 hour") || parts+=("$h hours"); }
    elif [ "$h" -gt 0 ]; then
        [ "$h" -eq 1 ] && parts+=("1 hour") || parts+=("$h hours")
        [ "$m" -gt 0 ] && { [ "$m" -eq 1 ] && parts+=("1 minute") || parts+=("$m minutes"); }
    elif [ "$m" -gt 0 ]; then
        [ "$m" -eq 1 ] && parts+=("1 minute") || parts+=("$m minutes")
    else
        [ "$s" -eq 1 ] && parts+=("1 second") || parts+=("$s seconds")
    fi
    local out="${parts[0]}" p
    for p in "${parts[@]:1}"; do
        out+=", $p"
    done
    echo "$out"
}

# ───────────────────────────────────────────────────────────────────────────────
# health_show() — print the full read-only system health snapshot
#
# Eight sections, each independent and each degrading on its own: CPU (load
# averages + core count + the top 5 processes), memory (RAM + swap with a
# used-% verdict), disk (root filesystem line), temperature (lm-sensors when
# present), battery (sysfs), failed systemd units, pending apt updates and
# uptime. Read-only apart from the ps/df probes; every section that cannot be
# measured prints an info line instead of an error — the command always
# exits 0.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
health_show() {
    header "System Health Snapshot"

    # ── 1. CPU: load averages, cores, top processes ───────────────────────────
    echo -e "${BOLD}   ── CPU ──${NC}"
    local l1 l5 l15 cores
    if [ -r /proc/loadavg ]; then
        read -r l1 l5 l15 _ < /proc/loadavg
        cores=$(nproc 2> /dev/null || grep -c '^processor' /proc/cpuinfo 2> /dev/null)
        cores="${cores:-?}"
        echo "   Load average: $l1 $l5 $l15  (${cores} core(s))"
    else
        info "/proc/loadavg is not readable — load averages skipped"
    fi
    if command -v ps > /dev/null 2>&1; then
        ps -eo pcpu,comm --sort=-pcpu 2> /dev/null | head -n 6 | tail -n +2 | while IFS= read -r hp; do
            printf '   • %s\n' "$hp"
        done
    else
        info "ps not found — the top-process list is skipped"
    fi
    echo ""

    # ── 2. Memory: RAM + swap with a verdict ──────────────────────────────────
    echo -e "${BOLD}   ── Memory ──${NC}"
    if [ -r /proc/meminfo ]; then
        local mem_total=0 mem_avail=0 swap_total=0 swap_free=0 val
        val=$(awk '$1 == "MemTotal:" {print $2}' /proc/meminfo 2> /dev/null); [ -n "$val" ] && mem_total=$val
        val=$(awk '$1 == "MemAvailable:" {print $2}' /proc/meminfo 2> /dev/null); [ -n "$val" ] && mem_avail=$val
        val=$(awk '$1 == "SwapTotal:" {print $2}' /proc/meminfo 2> /dev/null); [ -n "$val" ] && swap_total=$val
        val=$(awk '$1 == "SwapFree:" {print $2}' /proc/meminfo 2> /dev/null); [ -n "$val" ] && swap_free=$val

        local ram_pct verdict
        ram_pct=$(_health_ram_pct "$mem_total" "$mem_avail")
        verdict=$(_health_verdict "$ram_pct")
        local mem_used=$(( mem_total - mem_avail ))
        [ "$mem_used" -lt 0 ] && mem_used=0
        echo "   RAM: $(_health_human_kb "$mem_used") used of $(_health_human_kb "$mem_total") (${ram_pct}% used)"
        if [ "$verdict" = "ok" ]; then
            success "Memory usage is ok"
        else
            warn "Memory usage is ${ram_pct}% — verdict: ${verdict}"
        fi
        if [ "$swap_total" -gt 0 ]; then
            local swap_used=$(( swap_total - swap_free ))
            [ "$swap_used" -lt 0 ] && swap_used=0
            echo "   Swap: $(_health_human_kb "$swap_used") used of $(_health_human_kb "$swap_total")"
        else
            echo "   Swap: none configured"
        fi
    else
        info "/proc/meminfo is not readable — memory snapshot skipped"
    fi
    echo ""

    # ── 3. Disk: root filesystem ──────────────────────────────────────────────
    echo -e "${BOLD}   ── Disk (/) ──${NC}"
    if command -v df > /dev/null 2>&1; then
        local d_total d_used d_avail d_pct
        read -r d_total d_used d_avail d_pct <<< "$(df -h / 2> /dev/null | awk 'NR==2 {print $2, $3, $4, $5}')"
        if [ -n "$d_total" ]; then
            echo "   Total: $d_total  |  Used: $d_used ($d_pct)  |  Free: $d_avail"
            case "${d_pct%\%}" in
                ''|*[!0-9]*) ;;
                *) [ "${d_pct%\%}" -ge 90 ] && \
                    warn "Root filesystem is ${d_pct} full — run 'uo --disk-clean' to free space" ;;
            esac
        else
            info "df returned no data for / — disk snapshot skipped"
        fi
    else
        info "df not found — disk snapshot skipped"
    fi
    echo ""

    # ── 4. Temperature: lm-sensors when present ───────────────────────────────
    echo -e "${BOLD}   ── Temperature ──${NC}"
    if command -v sensors > /dev/null 2>&1; then
        local temp_out
        temp_out=$(sensors 2> /dev/null | grep '°C')
        if [ -n "$temp_out" ]; then
            printf '%s\n' "$temp_out" | while IFS= read -r tl; do
                printf '   • %s\n' "$tl"
            done
        else
            info "sensors produced no temperature readings on this machine"
        fi
    else
        info "lm-sensors is not installed — temperature unavailable (sudo apt install lm-sensors)"
    fi
    echo ""

    # ── 5. Battery: sysfs power supply ────────────────────────────────────────
    echo -e "${BOLD}   ── Battery ──${NC}"
    local bat bat_cap bat_status bats_found=0
    for bat in /sys/class/power_supply/BAT*; do
        [ -d "$bat" ] || continue
        bats_found=$(( bats_found + 1 ))
        bat_cap=$(cat "$bat/capacity" 2> /dev/null)
        bat_status=$(cat "$bat/status" 2> /dev/null)
        bat_cap="${bat_cap:-?}"
        bat_status="${bat_status:-unknown}"
        echo "   ${bat##*/}: ${bat_cap}% (${bat_status})"
    done
    [ "$bats_found" -eq 0 ] && info "No battery found (desktop machine?)"
    echo ""

    # ── 6. Failed systemd units ───────────────────────────────────────────────
    echo -e "${BOLD}   ── Failed units ──${NC}"
    if _health_have_systemd && command -v systemctl > /dev/null 2>&1; then
        local failed_n
        failed_n=$(systemctl --failed --no-legend --no-pager 2> /dev/null | wc -l)
        if [ "${failed_n:-0}" -gt 0 ]; then
            warn "$failed_n failed unit(s) — inspect with 'uo --boot' (failed units section)"
        else
            success "No failed units"
        fi
    else
        info "systemd is not available — failed-unit check skipped"
    fi
    echo ""

    # ── 7. Pending updates: best-effort apt count ─────────────────────────────
    echo -e "${BOLD}   ── Pending updates ──${NC}"
    if command -v apt > /dev/null 2>&1; then
        local upd_n
        # the "Listing..." header line does not count; apt failures stay silent
        upd_n=$(apt list --upgradable 2> /dev/null | grep -cv '^Listing' || true)
        [ -n "$upd_n" ] || upd_n=0
        if [ "$upd_n" -gt 0 ]; then
            warn "$upd_n package update(s) pending — 'uo --update -y' applies them"
        else
            success "No package updates pending (or the apt lists are not refreshed yet)"
        fi
    else
        info "apt not found — the pending-update count is skipped"
    fi
    echo ""

    # ── 8. Uptime ─────────────────────────────────────────────────────────────
    echo -e "${BOLD}   ── Uptime ──${NC}"
    if [ -r /proc/uptime ]; then
        local up_raw up_secs up_human
        up_raw=$(awk '{print $1}' /proc/uptime 2> /dev/null)
        up_secs="${up_raw%%.*}"
        up_human=$(_health_uptime_human "$up_secs")
        if [ -n "$up_human" ]; then
            echo "   Up for: $up_human"
        else
            info "/proc/uptime contains an unexpected value — uptime skipped"
        fi
    else
        info "/proc/uptime is not readable — uptime skipped"
    fi
    return 0
}
