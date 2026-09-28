# shellcheck shell=bash
# ============================================================
#   lib/report.sh — system status & health report (read-only)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#   Does not use success/warn so the report does not fill the log.
# ============================================================

# Status line with ✓/✗ — $1=state(1/0)  $2=title  $3=details
_report_line() {
    if [ "$1" = "1" ]; then
        echo -e "   ${GREEN}✓${NC} $2${3:+ — $3}"
    else
        echo -e "   ${RED}✗${NC} $2${3:+ — $3}"
    fi
}

# Format bytes in a human-readable form
_fmt_size() {
    numfmt --to=iec "$1" 2>/dev/null || echo "$(( $1 / 1024 / 1024 )) MB"
}

# Multi-method connectivity test — ICMP is unreliable because some ISPs
# block or deprioritize it; in that case TCP and HTTP are checked
_net_has_internet() {
    ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 && return 0
    ping -c 1 -W 2 1.1.1.1 > /dev/null 2>&1 && return 0

    timeout 3 bash -c 'exec 3<>/dev/tcp/8.8.8.8/53'  2>/dev/null && return 0
    timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null && return 0

    if command -v curl > /dev/null 2>&1; then
        curl -s --connect-timeout 3 --max-time 5 -o /dev/null \
             "http://connectivity-check.ubuntu.com" 2>/dev/null && return 0
    fi
    return 1
}

system_report() {
    header "📊 System Status Report"

    # ---------- System ----------
    # os-release is read in a subshell so its variables do not leak into the current shell
    local pretty_name
    # shellcheck disable=SC1091  # external system file — safe not to follow
    pretty_name=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")
    echo -e "${BOLD}🖥 System:${NC}"
    echo "   • $pretty_name | kernel $(uname -r) | $(uname -m)"
    echo "   • Uptime: $(uptime -p 2>/dev/null | sed 's/^up //')"
    echo "   • System load: $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

    # ---------- Memory ----------
    echo ""
    echo -e "${BOLD}💾 Memory:${NC}"
    local mem_total mem_used swap_total swap_used pct spct
    read -r mem_total mem_used < <(free -b | awk '/^Mem:/ {print $2, $3}')
    read -r swap_total swap_used < <(free -b | awk '/^Swap:/ {print $2, $3}')

    if [ "${mem_total:-0}" -gt 0 ] 2>/dev/null; then
        pct=$(( mem_used * 100 / mem_total ))
        echo "   • RAM: $(_fmt_size "$mem_used") of $(_fmt_size "$mem_total") (${pct}%)"
        [ "$pct" -ge 90 ] && echo -e "   ${RED}⚠${NC} Critical RAM usage!"
    fi
    if [ "${swap_total:-0}" -gt 0 ] 2>/dev/null; then
        spct=$(( swap_used * 100 / swap_total ))
        echo "   • Swap: $(_fmt_size "$swap_used") of $(_fmt_size "$swap_total") (${spct}%)"
        [ "$spct" -ge 60 ] && echo -e "   ${YELLOW}⚠${NC} High swap usage (low RAM or a memory leak)"
    else
        echo "   • Swap: none / zero"
    fi

    # ---------- Disks ----------
    echo ""
    echo -e "${BOLD}💿 Disks:${NC}"
    local src fstype size used avail pcent target usage mark
    while read -r src fstype size used avail pcent target; do
        [ -z "$src" ] && continue
        usage=${pcent%\%}
        mark="${GREEN}✓${NC}"
        if [ "${usage:-0}" -ge 85 ] 2>/dev/null; then
            mark="${RED}⚠${NC}"
        fi
        echo -e "   $mark $target ($fstype) — total: $size | used: $used | free: $avail ($pcent)"
    done < <(df -h --output=source,fstype,size,used,avail,pcent,target \
             -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

    # ---------- Failed services ----------
    echo ""
    echo -e "${BOLD}🔧 Services:${NC}"
    local failed_list failed_count
    failed_list=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    if [ -n "$failed_list" ]; then
        failed_count=$(echo "$failed_list" | wc -l)
        echo -e "   ${RED}⚠${NC} $failed_count service(s) in a failed state:"
        # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
        echo "$failed_list" | sed 's/^/      • /'
    else
        echo -e "   ${GREEN}✓${NC} All system services are healthy."
    fi

    # ---------- Optimization status ----------
    echo ""
    echo -e "${BOLD}⚙ Optimization status (this script's work):${NC}"
    local cur
    cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    _report_line "$([ "$cur" = "bbr" ] && echo 1 || echo 0)" "BBR" "current: ${cur:-unknown}"

    cur=$(sysctl -n vm.swappiness 2>/dev/null)
    _report_line "$([ "$cur" = "10" ] && echo 1 || echo 0)" "swappiness" "current: ${cur:-unknown} (target: 10)"

    cur=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)
    _report_line "$([ "$cur" = "50" ] && echo 1 || echo 0)" "vfs_cache_pressure" "current: ${cur:-unknown} (target: 50)"

    cur=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    _report_line "$([ "$cur" = "16384" ] && echo 1 || echo 0)" "TCP optimization" "current: ${cur:-unknown}"

    cur=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
    _report_line "$([ "$cur" = "3" ] && echo 1 || echo 0)" "TCP fastopen" "current: ${cur:-unknown} (target: 3)"

    cur=$(sysctl -n net.core.rmem_max 2>/dev/null)
    _report_line "$([ "$cur" = "16777216" ] && echo 1 || echo 0)" "TCP buffers" "current: ${cur:-unknown} (target: 16777216)"

    _report_line "$([ -f "$JOURNALD_DROPIN" ] && grep -q "SystemMaxUse" "$JOURNALD_DROPIN" 2>/dev/null && echo 1 || echo 0)" "journald size limit"
    _report_line "$(sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' /etc/fstab 2>/dev/null | grep -q noatime && echo 1 || echo 0)" "noatime on root"
    _report_line "$(pkg_installed preload && echo 1 || echo 0)" "preload"
    _report_line "$(pkg_installed tlp && echo 1 || echo 0)" "tlp (battery)"
    _report_line "$([ -f "$SUDOERS_TIMEOUT_FILE" ] && echo 1 || echo 0)" "sudo timeout"

    # polkit rule — content check: the safe version (local sessions) or the old unrestricted one
    local pk=0 pk_detail="not enabled"
    if [ -f "$POLKIT_RULE_FILE" ]; then
        if grep -q "subject.active" "$POLKIT_RULE_FILE" 2>/dev/null; then
            pk=1
            pk_detail="safe version (local sessions only)"
        else
            pk_detail="old unrestricted version — re-run setup_polkit_rule"
        fi
    fi
    _report_line "$pk" "polkit rule" "$pk_detail"

    # ---------- Network ----------
    echo ""
    echo -e "${BOLD}🌐 Network:${NC}"
    local defiface dns
    # Default-route interface — robust against routes without 'via'
    defiface=$(ip -o -4 route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    if [ -n "$defiface" ]; then
        echo "   • Default interface: $defiface (state: $(cat "/sys/class/net/$defiface/operstate" 2>/dev/null))"
    else
        echo -e "   ${RED}✗${NC} No default route is active (no internet connection)"
    fi
    if _net_has_internet; then
        echo -e "   ${GREEN}✓${NC} Internet connection is up."
    else
        echo -e "   ${RED}✗${NC} No internet connection! (if you just disconnected a VPN: run fixnet)"
    fi
    if command -v resolvectl > /dev/null 2>&1; then
        dns=$(resolvectl status 2>/dev/null | grep -m1 "DNS Servers" | sed 's/.*: *//')
    fi
    [ -n "$dns" ] || dns=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    [ -n "$dns" ] && echo "   • Current DNS: $dns"

    # ---------- Top memory consumers ----------
    echo ""
    echo -e "${BOLD}🧠 Top memory consumers (RAM):${NC}"
    ps -eo comm,rss --sort=-rss 2>/dev/null | awk 'NR>1 && NR<=4 {printf "   • %-25s %6.0f MB\n", $1, $2/1024}'

    # ---------- Last logged events ----------
    if [ -s "$LOG_FILE" ]; then
        echo ""
        echo -e "${BOLD}📜 Last 5 logged events:${NC}"
        grep -E '\] (OK|ERROR|WARN)[[:space:]]' "$LOG_FILE" 2>/dev/null | tail -n 5 | sed 's/^/   /'
    fi

    log_write "INFO" "System status report displayed"
    return 0
}
