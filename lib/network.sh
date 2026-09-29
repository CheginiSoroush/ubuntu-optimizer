# shellcheck shell=bash
# ============================================================
#   lib/network.sh — network optimization and network tests
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

# ---------- Optimization ----------

disable_wifi_powersave() {
    header "Disable Wi-Fi Power Management"
    local CONN DEV
    CONN=$(get_active_connection wireless)
    if [ -z "$CONN" ]; then
        failure "No active Wi-Fi connection found."
        return 1
    fi
    DEV=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2 == "wifi" {print $1; exit}')
    info "Active connection: $CONN${DEV:+ (device: $DEV)}"
    info "The network will go down and come back for a few seconds."
    warn "Do not run this over an SSH session!"
    if ! sudo nmcli connection modify "$CONN" 802-11-wireless.powersave 2; then
        failure "Failed to disable power management."
        return 1
    fi
    # Apply by restarting the same connection — not the whole NetworkManager service
    sudo nmcli connection down "$CONN" > /dev/null 2>&1
    if ! sudo nmcli connection up "$CONN" > /dev/null 2>&1; then
        failure "Wi-Fi reconnection failed."
        warn "Check the network state or run fixnet."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] Wi-Fi power management would be disabled."
        return 0
    fi
    # Final verification of the powersave state (when iw is available)
    if [ -n "$DEV" ] && command -v iw > /dev/null 2>&1; then
        if iw dev "$DEV" get power_save 2>/dev/null | grep -q "off"; then
            success "Wi-Fi power management disabled."
        else
            failure "Connection is up but power management is still enabled."
            return 1
        fi
    else
        success "Wi-Fi power management disabled."
    fi
    return 0
}

set_dns() {
    header "Set DNS to 8.8.8.8 and 1.1.1.1"
    local CONN
    # DNS must be set on the physical connection, not a VPN — priority: ethernet → wireless → any
    CONN=$(get_active_connection ethernet)
    [ -z "$CONN" ] && CONN=$(get_active_connection wireless)
    [ -z "$CONN" ] && CONN=$(get_active_connection)
    if [ -z "$CONN" ]; then
        failure "No active connection found."
        return 1
    fi
    info "Active connection: $CONN"
    warn "The connection will drop and reconnect for a few seconds."
    warn "Do not run this over an SSH session!"
    if sudo nmcli connection modify "$CONN" ipv4.dns "8.8.8.8 1.1.1.1" \
       && sudo nmcli connection modify "$CONN" ipv4.ignore-auto-dns yes \
       && sudo nmcli connection down "$CONN" > /dev/null 2>&1 \
       && sudo nmcli connection up "$CONN" > /dev/null 2>&1; then
        success "DNS configured."
        return 0
    else
        failure "Failed to set DNS."
        warn "If the connection is down, use the fixnet script."
        return 1
    fi
}

enable_bbr() {
    header "Enable BBR Congestion Control"
    # Load the module — if it is built-in, the modprobe error is irrelevant
    sudo modprobe tcp_bbr 2>/dev/null
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
        failure "Your kernel does not support BBR."
        return 1
    fi
    set_sysctl net.core.default_qdisc fq
    set_sysctl net.ipv4.tcp_congestion_control bbr
    if ! apply_sysctl; then
        failure "Failed to apply the sysctl settings."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] BBR would be enabled."
        return 0
    fi
    local STATUS
    STATUS=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [ "$STATUS" = "bbr" ]; then
        success "BBR enabled successfully."
        return 0
    else
        failure "BBR was not enabled. Current value: $STATUS"
        return 1
    fi
}

set_mtu() {
    header "Set MTU"
    local IFACE
    # Interface of the default route — correct on systems with docker/VMs
    IFACE=$(ip route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    if [ -z "$IFACE" ]; then
        IFACE=$(ip -br link show 2>/dev/null | awk '$2 == "UP" && $1 != "lo" {print $1; exit}')
    fi
    if [ -z "$IFACE" ]; then
        failure "No active interface found."
        return 1
    fi
    info "Active interface: $IFACE"
    info "Current MTU: $(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)"
    local MTU_VAL
    # In CLI or -y mode no interactive prompt is shown; the default is applied
    if [ "$CLI_MODE" = "1" ] || [ "$ASSUME_YES" = "1" ]; then
        MTU_VAL=1492
        info "Automatic mode: MTU will be set to 1492."
    else
        read -r -p "   MTU value (Enter for default 1492): " MTU_VAL
        MTU_VAL=${MTU_VAL:-1492}
    fi
    if ! [[ "$MTU_VAL" =~ ^[0-9]+$ ]]; then
        failure "Invalid MTU value: $MTU_VAL"
        return 1
    fi
    if sudo ip link set dev "$IFACE" mtu "$MTU_VAL"; then
        success "MTU set to $MTU_VAL. (temporary — reverts after a reboot)"
        info "To make it permanent, set the mtu value in NetworkManager."
        return 0
    else
        failure "Failed to set MTU."
        return 1
    fi
}

optimize_tcp() {
    header "Optimize TCP Parameters"
    # The standard BBR companion set: unsent queue, fastopen, larger buffers
    set_sysctl net.ipv4.tcp_notsent_lowat 16384
    set_sysctl net.ipv4.tcp_fastopen 3
    set_sysctl net.ipv4.tcp_slow_start_after_idle 0
    set_sysctl net.core.rmem_max 16777216
    set_sysctl net.core.wmem_max 16777216
    set_sysctl net.ipv4.tcp_rmem "4096 87380 16777216"
    set_sysctl net.ipv4.tcp_wmem "4096 65536 16777216"
    if ! apply_sysctl; then
        failure "Failed to apply the TCP settings."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] TCP parameters would be optimized."
        return 0
    fi
    # Verify the representative parameter
    local CUR
    CUR=$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null)
    if [ "$CUR" = "16384" ]; then
        success "TCP parameters optimized."
        return 0
    else
        failure "TCP settings could not be verified. Current notsent_lowat: ${CUR:-unknown}"
        return 1
    fi
}

all_network_opts() {
    disable_wifi_powersave
    set_dns
    enable_bbr
    set_mtu
    optimize_tcp
}

# ============================================================
#   Network tests
# ============================================================

test_ping() {
    header "Ping Test to 8.8.8.8"
    # -W: per-reply timeout — avoids long waits on a dead network
    if ping -c 4 -W 3 -i 0.25 8.8.8.8; then
        success "Ping successful."
        return 0
    else
        failure "Ping failed. No connectivity."
        return 1
    fi
}

test_ping_dns() {
    header "DNS Test (ping google.com)"
    if ping -c 4 -W 3 -i 0.25 google.com; then
        success "DNS is working."
        return 0
    else
        failure "DNS is broken."
        return 1
    fi
}

test_speed() {
    header "Internet Speed Test"
    if ! command -v speedtest-cli > /dev/null 2>&1; then
        info "Installing speedtest-cli..."
        if ! sudo apt install -y speedtest-cli > /dev/null 2>&1; then
            failure "Failed to install speedtest-cli."
            return 1
        fi
    fi
    if speedtest-cli; then
        success "Speed test completed."
        return 0
    else
        failure "Speed test failed."
        return 1
    fi
}

show_network_info() {
    header "Network Info"
    echo -e "${BOLD}Interfaces:${NC}"
    ip -br addr
    echo ""
    echo -e "${BOLD}Routing:${NC}"
    ip route
    echo ""
    echo -e "${BOLD}DNS:${NC}"
    if command -v resolvectl > /dev/null 2>&1; then
        resolvectl status 2>/dev/null | sed -n '1,40p'
    else
        grep nameserver /etc/resolv.conf
    fi
    return 0
}

all_tests() {
    test_ping
    test_ping_dns
    test_speed
    show_network_info
}
