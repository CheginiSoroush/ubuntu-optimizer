# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/jsonreport.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Machine-readable JSON version of the system status report, consumed by
#  `uo --report --json`. The output is a single valid JSON document on stdout —
#  the CLI banner, the session summary and every human-only message are
#  suppressed by JSON_MODE in ubuntu-optimizer.sh, so the stream can be piped
#  straight into jq, cron mail or a monitoring dashboard.
#
#  The sections mirror lib/report.sh one-to-one (host, memory, disks, failed
#  services, optimization status, network, top memory consumers, last logged
#  events) but sizes are raw bytes and booleans are real JSON booleans, so
#  scripts never parse decorated text. A compact "summary" block at the top
#  gives dashboards a one-glance health verdict.
#
#  Strictly read-only, exactly like the plain-text report.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _json_escape() — escape a string for a JSON string literal
#
# Backslashes and quotes are escaped, tab/CR/LF become \t \r \n and every
# remaining control character (invalid inside JSON strings) is stripped.
# Also the reason the emitter never needs a external tool (jq/python) to
# build the document.
#
# Arguments: $1 — raw text
# Returns:   0 — always; the escaped text goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/\\n}
    # strip the remaining C0 control characters (0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F)
    printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

# ───────────────────────────────────────────────────────────────────────────────
# _json_int() — print a safe non-negative integer
#
# Values coming from free/df/ps are trusted to be numeric, but a tool that
# changes its output format must never inject garbage into the document —
# anything that is not a plain integer becomes 0.
#
# Arguments: $1 — candidate number
# Returns:   0 — always; the sanitized integer goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_json_int() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        printf '%s' "$1"
    else
        printf '0'
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _json_float() — print a safe decimal number (load averages)
#
# Same idea as _json_int but accepts optional decimals; anything else → 0.
#
# Arguments: $1 — candidate number
# Returns:   0 — always; the sanitized number goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_json_float() {
    if [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$1"
    else
        printf '0'
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# system_report_json() — emit the full system status report as JSON
#
# Builds the document in a string so counters collected across all sections
# (disk warnings, failed checks, failed services) can feed the "summary"
# verdict block, then prints it once. Every section of lib/report.sh is
# represented; booleans are true/false, sizes are bytes, percentages are
# integers. Unknown/unavailable data becomes null — never an empty string
# masquerading as data.
#
# Globals:   SCRIPT_VERSION, LOG_FILE, JOURNALD_DROPIN, SUDOERS_TIMEOUT_FILE,
#            POLKIT_RULE_FILE (read); _net_has_internet, pkg_installed from
#            lib/report.sh / lib/common.sh (called, must be loaded)
# Arguments: none
# Returns:   0 — always (the JSON document goes to stdout)
# ───────────────────────────────────────────────────────────────────────────────
system_report_json() {
    local out=""

    # ---------- host ----------
    local pretty_name kernel arch uptime_s load1 load5 load15
    # shellcheck disable=SC1091  # external system file — safe not to follow
    pretty_name=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")
    kernel=$(uname -r 2>/dev/null)
    arch=$(uname -m 2>/dev/null)
    uptime_s=$(uptime -p 2>/dev/null | sed 's/^up //')
    read -r load1 load5 load15 <<< "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

    # ---------- memory ----------
    local mem_total mem_used swap_total swap_used
    read -r mem_total mem_used < <(free -b 2>/dev/null | awk '/^Mem:/ {print $2, $3}')
    read -r swap_total swap_used < <(free -b 2>/dev/null | awk '/^Swap:/ {print $2, $3}')
    mem_total=$(_json_int "${mem_total:-0}")
    mem_used=$(_json_int "${mem_used:-0}")
    swap_total=$(_json_int "${swap_total:-0}")
    swap_used=$(_json_int "${swap_used:-0}")
    local ram_pct=0 swap_pct=0
    [ "$mem_total" -gt 0 ] 2>/dev/null && ram_pct=$(( mem_used * 100 / mem_total ))
    [ "$swap_total" -gt 0 ] 2>/dev/null && swap_pct=$(( swap_used * 100 / swap_total ))

    # ---------- disks ----------
    local disks_json="" dsrc dfstype dsize dused davail dpct dtarget disk_warnings=0 dcount=0
    while read -r dsrc dfstype dsize dused davail dpct dtarget; do
        [ -z "$dsrc" ] && continue
        local dnum
        dnum=${dpct%\%}
        dnum=$(_json_int "$dnum")
        if [ "$dnum" -ge 85 ] 2>/dev/null; then
            disk_warnings=$(( disk_warnings + 1 ))
        fi
        [ "$dcount" -gt 0 ] && disks_json+=","
        printf -v disks_json '%s{"source":"%s","fstype":"%s","total":%s,"used":%s,"avail":%s,"percent":%s,"target":"%s"}' \
            "$disks_json" "$(_json_escape "$dsrc")" "$(_json_escape "$dfstype")" \
            "$(_json_int "$dsize")" "$(_json_int "$dused")" "$(_json_int "$davail")" \
            "$dnum" "$(_json_escape "$dtarget")"
        dcount=$(( dcount + 1 ))
    done < <(df -B1 --output=source,fstype,size,used,avail,pcent,target \
             -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

    # ---------- failed services ----------
    local failed_list failed_json="" fcount=0 fline
    failed_list=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    while IFS= read -r fline; do
        [ -z "$fline" ] && continue
        [ "$fcount" -gt 0 ] && failed_json+=","
        failed_json+="\"$(_json_escape "$fline")\""
        fcount=$(( fcount + 1 ))
    done <<< "$failed_list"

    # ---------- optimization status (mirrors lib/report.sh) ----------
    local opt_json="" opt_ok=0 opt_total=0 cur ok
    _opt_entry() {
        # $1 name, $2 ok(1/0), $3 current, $4 target-or-empty
        local ok_json="false"
        [ "$2" = "1" ] && { ok_json="true"; opt_ok=$(( opt_ok + 1 )); }
        [ "$opt_total" -gt 0 ] && opt_json+=","
        if [ -n "$4" ]; then
            printf -v opt_json '%s{"name":"%s","ok":%s,"current":"%s","target":"%s"}' \
                "$opt_json" "$(_json_escape "$1")" "$ok_json" "$(_json_escape "$3")" "$(_json_escape "$4")"
        else
            printf -v opt_json '%s{"name":"%s","ok":%s,"current":"%s"}' \
                "$opt_json" "$(_json_escape "$1")" "$ok_json" "$(_json_escape "$3")"
        fi
        opt_total=$(( opt_total + 1 ))
    }

    cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    _opt_entry "bbr" "$([ "$cur" = "bbr" ] && echo 1 || echo 0)" "${cur:-unknown}" "bbr"

    cur=$(sysctl -n vm.swappiness 2>/dev/null)
    _opt_entry "swappiness" "$([ "$cur" = "10" ] && echo 1 || echo 0)" "${cur:-unknown}" "10"

    cur=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)
    _opt_entry "vfs_cache_pressure" "$([ "$cur" = "50" ] && echo 1 || echo 0)" "${cur:-unknown}" "50"

    cur=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    _opt_entry "tcp_notsent_lowat" "$([ "$cur" = "16384" ] && echo 1 || echo 0)" "${cur:-unknown}" "16384"

    cur=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    _opt_entry "tcp_fastopen" "$([ "$cur" = "3" ] && echo 1 || echo 0)" "${cur:-unknown}" "3"

    cur=$(sysctl -n net.core.rmem_max 2>/dev/null)
    _opt_entry "tcp_buffers" "$([ "$cur" = "16777216" ] && echo 1 || echo 0)" "${cur:-unknown}" "16777216"

    cur=$([ -f "${JOURNALD_DROPIN:-}" ] && grep -q "SystemMaxUse" "${JOURNALD_DROPIN}" 2>/dev/null && echo 1 || echo 0)
    _opt_entry "journald_limit" "$cur" "$([ "$cur" = "1" ] && echo enabled || echo off)" "enabled"

    cur=$(sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' /etc/fstab 2>/dev/null | grep -q noatime && echo 1 || echo 0)
    _opt_entry "noatime_root" "$cur" "$([ "$cur" = "1" ] && echo enabled || echo off)" "enabled"

    cur=$(pkg_installed preload 2>/dev/null && echo 1 || echo 0)
    _opt_entry "preload" "$cur" "$([ "$cur" = "1" ] && echo installed || echo absent)" "installed"

    cur=$(pkg_installed tlp 2>/dev/null && echo 1 || echo 0)
    _opt_entry "tlp" "$cur" "$([ "$cur" = "1" ] && echo installed || echo absent)" "installed"

    cur=$([ -f "${SUDOERS_TIMEOUT_FILE:-}" ] && echo 1 || echo 0)
    _opt_entry "sudo_timeout" "$cur" "$([ "$cur" = "1" ] && echo enabled || echo off)" "enabled"

    # polkit — content check like the plain report (safe vs old unrestricted rule)
    local pk=0 pk_state="off"
    if [ -f "${POLKIT_RULE_FILE:-}" ]; then
        if grep -q "subject.active" "${POLKIT_RULE_FILE}" 2>/dev/null; then
            pk=1; pk_state="safe"
        else
            pk_state="old-unrestricted"
        fi
    fi
    _opt_entry "polkit_rule" "$pk" "$pk_state" "safe"

    # ---------- network ----------
    local defiface iface_state="" internet=1 dns=""
    defiface=$(ip -o -4 route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    [ -n "$defiface" ] && iface_state=$(cat "/sys/class/net/$defiface/operstate" 2>/dev/null)
    _net_has_internet || internet=0
    if command -v resolvectl > /dev/null 2>&1; then
        dns=$(resolvectl status 2>/dev/null | grep -m1 "DNS Servers" | sed 's/.*: *//')
    fi
    [ -n "$dns" ] || dns=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

    # ---------- top memory consumers ----------
    local top_json="" tcomm trss tcount=0
    while read -r tcomm trss; do
        [ -z "$tcomm" ] && continue
        [ "$tcount" -gt 0 ] && top_json+=","
        printf -v top_json '%s{"command":"%s","rss_kb":%s}' \
            "$top_json" "$(_json_escape "$tcomm")" "$(_json_int "$trss")"
        tcount=$(( tcount + 1 ))
    done < <(ps -eo comm,rss --sort=-rss 2>/dev/null | awk 'NR>1 && NR<=4 {print $1, $2}')

    # ---------- last logged events ----------
    local events_json="" eline ecount=0
    if [ -s "${LOG_FILE:-}" ]; then
        while IFS= read -r eline; do
            [ -z "$eline" ] && continue
            [ "$ecount" -gt 0 ] && events_json+=","
            events_json+="\"$(_json_escape "$eline")\""
            ecount=$(( ecount + 1 ))
        done < <(grep -E '\] (OK|ERROR|WARN)[[:space:]]' "${LOG_FILE}" 2>/dev/null | tail -n 5)
    fi

    # ---------- summary verdict ----------
    # critical : failed services, or RAM ≥ 90%, or a disk ≥ 85%
    # attention: RAM ≥ 75%, swap ≥ 60%, or pending optimizations
    # good     : everything comfortable
    local status="good"
    if [ "$fcount" -gt 0 ] || [ "$ram_pct" -ge 90 ] || [ "$disk_warnings" -gt 0 ]; then
        status="critical"
    elif [ "$ram_pct" -ge 75 ] || [ "$swap_pct" -ge 60 ] || [ "$opt_ok" -lt "$opt_total" ]; then
        status="attention"
    fi

    # ---------- assemble ----------
    printf -v out '{"tool":"ubuntu-optimizer","version":"%s","generated_at":"%s","summary":{"status":"%s","optimizations_ok":%d,"optimizations_total":%d,"failed_services":%d,"ram_percent":%d,"swap_percent":%d,"disk_warnings":%d,"internet":%s},' \
        "$(_json_escape "${SCRIPT_VERSION:-unknown}")" \
        "$(_json_escape "$(date +%Y-%m-%dT%H:%M:%S%:z 2>/dev/null || date -Iseconds)")" \
        "$status" "$opt_ok" "$opt_total" "$fcount" "$ram_pct" "$swap_pct" "$disk_warnings" \
        "$([ "$internet" = "1" ] && echo true || echo false)"
    out+="\"host\":{\"os\":\"$(_json_escape "$pretty_name")\",\"kernel\":\"$(_json_escape "$kernel")\",\"arch\":\"$(_json_escape "$arch")\",\"uptime\":\"$(_json_escape "$uptime_s")\",\"load\":{\"1m\":$(_json_float "$load1"),\"5m\":$(_json_float "$load5"),\"15m\":$(_json_float "$load15")}},"
    out+="\"memory\":{\"ram\":{\"total\":$mem_total,\"used\":$mem_used,\"percent\":$ram_pct},"
    if [ "$swap_total" -gt 0 ] 2>/dev/null; then
        out+="\"swap\":{\"total\":$swap_total,\"used\":$swap_used,\"percent\":$swap_pct}},"
    else
        out+="\"swap\":null},"
    fi
    out+="\"disks\":[$disks_json],"
    out+="\"services\":{\"failed\":[$failed_json],\"count\":$fcount,\"healthy\":$([ "$fcount" -eq 0 ] && echo true || echo false)},"
    out+="\"optimizations\":[$opt_json],"
    out+="\"network\":{\"default_interface\":$([ -n "$defiface" ] && printf '"%s"' "$(_json_escape "$defiface")" || printf 'null'),\"interface_state\":$([ -n "$iface_state" ] && printf '"%s"' "$(_json_escape "$iface_state")" || printf 'null'),\"internet\":$([ "$internet" = "1" ] && echo true || echo false),\"dns\":$([ -n "$dns" ] && printf '"%s"' "$(_json_escape "$dns")" || printf 'null')},"
    out+="\"top_memory\":[$top_json],"
    out+="\"log_events\":[$events_json]}"

    printf '%s\n' "$out"
    log_write "INFO" "System status report (JSON) generated"
    return 0
}
