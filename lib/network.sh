# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/network.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Network optimizations (Wi-Fi powersave, DNS, BBR, MTU, TCP tuning) plus
#  connectivity tests. Reached from menu items 1 and 6 and from the CLI flags
#  --network / --optimize (all_network_opts) and --test (all_tests).
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Optimization ───────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# disable_wifi_powersave() — turn Wi-Fi power management off on the active link
#
# Sets 802-11-wireless.powersave 2 on the active Wi-Fi connection and applies
# it by bouncing that one connection — not the whole NetworkManager service.
# Verifies the final state with iw when available. Connectivity is interrupted
# for a few seconds; never run over an SSH session.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — power management disabled (or previewed in dry-run)
#            1 — no Wi-Fi connection, nmcli failed or state not verified
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# set_dns() — pin the connection's DNS to 8.8.8.8 and 1.1.1.1
#
# Applies the two resolvers to the physical connection (priority ethernet →
# wireless → any, so a VPN is never modified), enables ipv4.ignore-auto-dns
# and bounces the connection to activate the change. Connectivity drops for
# a few seconds; never run over an SSH session.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — DNS configured (or previewed in dry-run)
#            1 — no connection found or an nmcli step failed
# ───────────────────────────────────────────────────────────────────────────────
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
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] DNS would be configured."
            return 0
        fi
        success "DNS configured."
        return 0
    else
        failure "Failed to set DNS."
        warn "If the connection is down, use the fixnet script."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# enable_bbr() — switch TCP congestion control to BBR
#
# Loads the tcp_bbr module, sets the fq qdisc and bbr congestion control via
# the shared sysctl helpers, then re-verifies the live sysctl value. In
# dry-run the module is not loaded, so kernel support is probed read-only
# via modinfo instead.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — BBR active (or previewed in dry-run)
#            1 — kernel without BBR, sysctl failure or verification failed
# ───────────────────────────────────────────────────────────────────────────────
enable_bbr() {
    header "Enable BBR Congestion Control"
    # Load the module — if it is built-in, the modprobe error is irrelevant.
    # In dry-run the module is NOT actually loaded (the sudo wrapper only
    # prints the command), so availability is checked read-only via modinfo
    # instead — otherwise every preview on a system without BBR loaded yet
    # would wrongly report "kernel does not support BBR".
    if [ "$DRY_RUN" = "1" ]; then
        if ! modinfo tcp_bbr > /dev/null 2>&1 \
           && ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
            failure "Your kernel does not support BBR."
            return 1
        fi
    else
        sudo modprobe tcp_bbr 2>/dev/null
        if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
            failure "Your kernel does not support BBR."
            return 1
        fi
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

# ───────────────────────────────────────────────────────────────────────────────
# set_mtu() — set the MTU of the default-route interface
#
# Picks the interface of the default route (falls back to the first UP link)
# and applies the chosen MTU with ip link set. The change is temporary — it
# reverts after a reboot. Prompts interactively for the value (default 1492);
# in CLI or -y mode the default is applied without asking.
#
# Globals:   CLI_MODE, ASSUME_YES, DRY_RUN (read)
# Arguments: none
# Returns:   0 — MTU applied (or previewed in dry-run)
#            1 — no interface found, invalid value or ip link failed
# ───────────────────────────────────────────────────────────────────────────────
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
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] MTU would be set to $MTU_VAL."
            return 0
        fi
        success "MTU set to $MTU_VAL. (temporary — reverts after a reboot)"
        info "To make it permanent, set the mtu value in NetworkManager."
        return 0
    else
        failure "Failed to set MTU."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# optimize_tcp() — apply the BBR companion TCP sysctls
#
# Writes the standard BBR companion set (unsent-queue limit, fastopen, no
# slow-start after idle, larger rx/tx buffers) through the shared sysctl
# helpers and verifies the representative key afterwards.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — settings applied and verified (or previewed in dry-run)
#            1 — sysctl application or verification failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# all_network_opts() — run every network optimization in sequence
#
# Entry point of the menu item "Run all of the above" and of the CLI flags
# --network / --optimize. Runs the five optimizers above in order; each one
# reports its own success or failure.
#
# Arguments: none
# Returns:   exit status of the last step (optimize_tcp)
# ───────────────────────────────────────────────────────────────────────────────
all_network_opts() {
    disable_wifi_powersave
    set_dns
    enable_bbr
    set_mtu
    optimize_tcp
}

# ── Network tests ──────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# test_ping() — check raw IP connectivity with ping to 8.8.8.8
#
# Sends four pings with a per-reply timeout and a short interval so a dead
# network fails fast instead of hanging.
#
# Arguments: none
# Returns:   0 — ping succeeded
#            1 — ping failed (no connectivity)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# test_ping_dns() — check name resolution by pinging google.com
#
# Pings a hostname instead of a bare IP, so success proves DNS resolution
# works in addition to raw connectivity.
#
# Arguments: none
# Returns:   0 — hostname resolved and pinged
#            1 — ping failed (DNS broken or no connectivity)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# test_speed() — run an internet speed test via speedtest-cli
#
# Installs speedtest-cli from apt on first use (requires sudo and network
# access), then runs the measurement.
#
# Arguments: none
# Returns:   0 — speed test completed
#            1 — installation or the test itself failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# show_network_info() — print interfaces, routes and DNS configuration
#
# Read-only overview: ip -br addr, ip route and the DNS servers — via
# resolvectl when systemd-resolved is active, otherwise /etc/resolv.conf.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# all_tests() — run the full network test suite
#
# Entry point of the menu item "Run all tests" and of the CLI flag --test:
# ping, DNS, speed test and the info overview in sequence. Each test
# reports its own outcome.
#
# Arguments: none
# Returns:   exit status of the last step (show_network_info)
# ───────────────────────────────────────────────────────────────────────────────
all_tests() {
    test_ping
    test_ping_dns
    test_speed
    show_network_info
}
