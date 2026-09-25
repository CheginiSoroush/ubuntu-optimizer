# ============================================================
#   lib/report.sh — گزارش وضعیت سیستم و سلامت (فقط خواندنی)
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#   از success/warn استفاده نمی‌شود تا خود گزارش لاگ را پر نکند.
# ============================================================

# خط وضعیت با علامت ✓/✗ — $1=وضعیت(1/0)  $2=عنوان  $3=جزئیات
_report_line() {
    if [ "$1" = "1" ]; then
        echo -e "   ${GREEN}✓${NC} $2${3:+ — $3}"
    else
        echo -e "   ${RED}✗${NC} $2${3:+ — $3}"
    fi
}

# قالب‌بندی بایت به شکل خوانا
_fmt_size() {
    numfmt --to=iec "$1" 2>/dev/null || echo "$(( $1 / 1024 / 1024 )) MB"
}

# تست چندروشه اتصال — ICMP غیرقابل‌اعتماد است چون بعضی ISP ها آن را
# مسدود یا کم‌اولویت می‌کنند؛ در آن صورت TCP و HTTP بررسی می‌شوند
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
    header "📊 گزارش وضعیت سیستم"

    # ---------- سیستم ----------
    . /etc/os-release 2>/dev/null
    echo -e "${BOLD}🖥 سیستم:${NC}"
    echo "   • ${PRETTY_NAME:-لینوکس} | کرنل $(uname -r) | $(uname -m)"
    echo "   • آپ‌تایم: $(uptime -p 2>/dev/null | sed 's/^up //')"
    echo "   • بار سیستم (load): $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

    # ---------- حافظه ----------
    echo ""
    echo -e "${BOLD}💾 حافظه:${NC}"
    local mem_total mem_used swap_total swap_used pct spct
    read -r mem_total mem_used < <(free -b | awk '/^Mem:/ {print $2, $3}')
    read -r swap_total swap_used < <(free -b | awk '/^Swap:/ {print $2, $3}')

    if [ "${mem_total:-0}" -gt 0 ] 2>/dev/null; then
        pct=$(( mem_used * 100 / mem_total ))
        echo "   • رم: $(_fmt_size "$mem_used") از $(_fmt_size "$mem_total") (${pct}%)"
        [ "$pct" -ge 90 ] && echo -e "   ${RED}⚠${NC} مصرف رم بحرانی است!"
    fi
    if [ "${swap_total:-0}" -gt 0 ] 2>/dev/null; then
        spct=$(( swap_used * 100 / swap_total ))
        echo "   • Swap: $(_fmt_size "$swap_used") از $(_fmt_size "$swap_total") (${spct}%)"
        [ "$spct" -ge 60 ] && echo -e "   ${YELLOW}⚠${NC} مصرف swap بالاست (رم کم است یا نشت حافظه دارید)"
    else
        echo "   • Swap: وجود ندارد / صفر"
    fi

    # ---------- دیسک ----------
    echo ""
    echo -e "${BOLD}💿 دیسک‌ها:${NC}"
    local src fstype size used avail pcent target usage mark
    while read -r src fstype size used avail pcent target; do
        [ -z "$src" ] && continue
        usage=${pcent%\%}
        mark="${GREEN}✓${NC}"
        if [ "${usage:-0}" -ge 85 ] 2>/dev/null; then
            mark="${RED}⚠${NC}"
        fi
        echo -e "   $mark $target ($fstype) — کل: $size | استفاده: $used | آزاد: $avail ($pcent)"
    done < <(df -h --output=source,fstype,size,used,avail,pcent,target \
             -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2)

    # ---------- سرویس‌های خراب ----------
    echo ""
    echo -e "${BOLD}🔧 سرویس‌ها:${NC}"
    local failed_list failed_count
    failed_list=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    if [ -n "$failed_list" ]; then
        failed_count=$(echo "$failed_list" | wc -l)
        echo -e "   ${RED}⚠${NC} $failed_count سرویس در وضعیت خراب (failed):"
        echo "$failed_list" | sed 's/^/      • /'
    else
        echo -e "   ${GREEN}✓${NC} همه سرویس‌های سیستم سالم‌اند."
    fi

    # ---------- وضعیت بهینه‌سازی‌های این اسکریپت ----------
    echo ""
    echo -e "${BOLD}⚙ وضعیت بهینه‌سازی‌ها (کارهای این اسکریپت):${NC}"
    local cur
    cur=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    _report_line "$([ "$cur" = "bbr" ] && echo 1 || echo 0)" "BBR" "فعلی: ${cur:-نامشخص}"

    cur=$(sysctl -n vm.swappiness 2>/dev/null)
    _report_line "$([ "$cur" = "10" ] && echo 1 || echo 0)" "swappiness" "فعلی: ${cur:-نامشخص} (هدف: 10)"

    cur=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)
    _report_line "$([ "$cur" = "50" ] && echo 1 || echo 0)" "vfs_cache_pressure" "فعلی: ${cur:-نامشخص} (هدف: 50)"

    cur=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    _report_line "$([ "$cur" = "16384" ] && echo 1 || echo 0)" "بهینه‌سازی TCP" "فعلی: ${cur:-نامشخص}"

    _report_line "$([ -f "$JOURNALD_DROPIN" ] && grep -q "SystemMaxUse" "$JOURNALD_DROPIN" 2>/dev/null && echo 1 || echo 0)" "محدودیت حجم لاگ journald"
    _report_line "$(grep -q "noatime" /etc/fstab 2>/dev/null && echo 1 || echo 0)" "noatime روی ریشه"
    _report_line "$(pkg_installed preload && echo 1 || echo 0)" "preload"
    _report_line "$(pkg_installed tlp && echo 1 || echo 0)" "tlp (باتری)"
    _report_line "$([ -f "$SUDOERS_TIMEOUT_FILE" ] && echo 1 || echo 0)" "زمان اعتبار sudo"
    _report_line "$([ -f "$POLKIT_RULE_FILE" ] && echo 1 || echo 0)" "قانون polkit"

    # ---------- شبکه ----------
    echo ""
    echo -e "${BOLD}🌐 شبکه:${NC}"
    local defiface dns
    defiface=$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')
    if [ -n "$defiface" ]; then
        echo "   • اینترفیس پیش‌فرض: $defiface (وضعیت: $(cat /sys/class/net/$defiface/operstate 2>/dev/null))"
    else
        echo -e "   ${RED}✗${NC} هیچ مسیر پیش‌فرضی فعال نیست (بدون اتصال به اینترنت)"
    fi
    if _net_has_internet; then
        echo -e "   ${GREEN}✓${NC} اتصال اینترنت برقرار است."
    else
        echo -e "   ${RED}✗${NC} اتصال اینترنت برقرار نیست! (اگر VPN قطع کرده‌اید: fixnet)"
    fi
    if command -v resolvectl > /dev/null 2>&1; then
        dns=$(resolvectl status 2>/dev/null | grep -m1 "DNS Servers" | sed 's/.*: *//')
    fi
    [ -n "$dns" ] || dns=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    [ -n "$dns" ] && echo "   • DNS فعلی: $dns"

    # ---------- پرمصرف‌ترین برنامه‌ها ----------
    echo ""
    echo -e "${BOLD}🧠 پرمصرف‌ترین برنامه‌ها (RAM):${NC}"
    ps -eo comm,rss --sort=-rss 2>/dev/null | awk 'NR>1 && NR<=4 {printf "   • %-25s %6.0f MB\n", $1, $2/1024}'

    # ---------- آخرین رخدادهای لاگ ----------
    if [ -s "$LOG_FILE" ]; then
        echo ""
        echo -e "${BOLD}📜 آخرین رخدادهای ثبت‌شده (۵ مورد):${NC}"
        grep -E '\] (OK|ERROR|WARN)[[:space:]]' "$LOG_FILE" 2>/dev/null | tail -n 5 | sed 's/^/   /'
    fi

    log_write "INFO" "گزارش وضعیت سیستم نمایش داده شد"
    return 0
}
