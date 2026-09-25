# ============================================================
#   lib/network.sh — بهینه‌سازی شبکه و تست‌های شبکه
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
# ============================================================

disable_wifi_powersave() {
    header "غیرفعال کردن Power Management وای‌فای"
    local CONN
    CONN=$(get_active_connection wireless)
    if [ -z "$CONN" ]; then
        failure "هیچ اتصال وای‌فای فعالی پیدا نشد."
        return 1
    fi
    info "اتصال فعال: $CONN"
    info "شبکه چند ثانیه قطع و وصل می‌شود."
    if sudo nmcli connection modify "$CONN" 802-11-wireless.powersave 2; then
        sudo systemctl restart NetworkManager
        success "Power Management وای‌فای غیرفعال شد."
    else
        failure "خطا در غیرفعال کردن Power Management."
    fi
}

set_dns() {
    header "تنظیم DNS روی 8.8.8.8 و 1.1.1.1"
    local CONN
    CONN=$(get_active_connection)
    if [ -z "$CONN" ]; then
        failure "هیچ اتصال فعالی پیدا نشد."
        return 1
    fi
    info "اتصال فعال: $CONN"
    warn "اتصال برای چند ثانیه قطع و دوباره وصل می‌شود."
    warn "اگر از طریق SSH متصل هستید، این گزینه را اجرا نکنید!"
    if sudo nmcli connection modify "$CONN" ipv4.dns "8.8.8.8 1.1.1.1" \
       && sudo nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes \
       && sudo nmcli connection down "$CONN" > /dev/null 2>&1 \
       && sudo nmcli connection up "$CONN" > /dev/null 2>&1; then
        success "DNS تنظیم شد."
    else
        failure "خطا در تنظیم DNS."
        warn "در صورت قطع اتصال، از اسکریپت fixnet استفاده کنید."
    fi
}

enable_bbr() {
    header "فعال‌سازی الگوریتم BBR"
    sudo modprobe tcp_bbr 2>/dev/null
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
        failure "کرنل شما از BBR پشتیبانی نمی‌کند."
        return 1
    fi
    set_sysctl net.core.default_qdisc fq
    set_sysctl net.ipv4.tcp_congestion_control bbr
    if apply_sysctl; then
        local STATUS
        STATUS=$(sysctl -n net.ipv4.tcp_congestion_control)
        if [ "$STATUS" = "bbr" ]; then
            success "BBR با موفقیت فعال شد."
        else
            failure "BBR فعال نشد. وضعیت فعلی: $STATUS"
        fi
    else
        failure "خطا در اعمال تنظیمات sysctl."
    fi
}

set_mtu() {
    header "تنظیم MTU"
    local IFACE
    IFACE=$(ip -br link show 2>/dev/null | grep -v "^lo" | grep "UP" | head -1 | awk '{print $1}')
    if [ -z "$IFACE" ]; then
        failure "اینترفیس فعال پیدا نشد."
        return 1
    fi
    info "اینترفیس فعال: $IFACE"
    info "MTU فعلی: $(cat /sys/class/net/$IFACE/mtu)"
    local MTU_VAL
    read -r -p "   مقدار MTU (Enter برای پیش‌فرض 1492): " MTU_VAL
    MTU_VAL=${MTU_VAL:-1492}
    if sudo ip link set dev "$IFACE" mtu "$MTU_VAL"; then
        success "MTU روی $MTU_VAL تنظیم شد. (موقت — پس از ری‌استارت برمی‌گردد)"
        info "برای دائمی‌کردن، مقدار mtu را در تنظیمات NetworkManager ست کنید."
    else
        failure "خطا در تنظیم MTU."
    fi
}

optimize_tcp() {
    header "بهینه‌سازی پارامترهای TCP"
    set_sysctl net.ipv4.tcp_notsent_lowat 16384
    if apply_sysctl; then
        success "پارامترهای TCP بهینه شدند."
    else
        failure "خطا در اعمال تنظیمات TCP."
    fi
}

all_network_opts() { disable_wifi_powersave; set_dns; enable_bbr; set_mtu; optimize_tcp; }

# ============================================================
#   تست‌های شبکه
# ============================================================

test_ping() {
    header "تست پینگ به 8.8.8.8"
    if ping -c 4 8.8.8.8; then
        success "پینگ موفق."
    else
        failure "پینگ ناموفق. اتصال برقرار نیست."
    fi
}

test_ping_dns() {
    header "تست DNS با پینگ به google.com"
    if ping -c 4 google.com; then
        success "DNS درست کار می‌کند."
    else
        failure "DNS مشکل دارد."
    fi
}

test_speed() {
    header "تست سرعت اینترنت"
    if ! command -v speedtest-cli > /dev/null 2>&1; then
        info "نصب speedtest-cli..."
        sudo apt install -y speedtest-cli > /dev/null 2>&1 || { failure "خطا در نصب speedtest-cli."; return 1; }
    fi
    if speedtest-cli; then
        success "تست سرعت انجام شد."
    else
        failure "خطا در تست سرعت."
    fi
}

show_network_info() {
    header "اطلاعات شبکه"
    echo -e "${BOLD}اینترفیس‌ها:${NC}"
    ip -br addr
    echo ""
    echo -e "${BOLD}مسیریابی:${NC}"
    ip route
    echo ""
    echo -e "${BOLD}DNS:${NC}"
    if command -v resolvectl > /dev/null 2>&1; then
        resolvectl status 2>/dev/null | sed -n '1,40p'
    else
        grep nameserver /etc/resolv.conf
    fi
}

all_tests() { test_ping; test_ping_dns; test_speed; show_network_info; }
