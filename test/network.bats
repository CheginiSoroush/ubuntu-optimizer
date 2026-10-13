#!/usr/bin/env bats
# ============================================================
#   test/network.bats — tests for the network optimizers and
#   connectivity tests (lib/network.sh)
#
#   nmcli/ip/ping/speedtest-cli/resolvectl/modinfo are PATH
#   stubs; every mutating flow runs with the documented DRY_RUN=1
#   sudo wrapper (commands are printed and logged, nothing is
#   executed against the real system). Plan lines are asserted
#   via the log file because the dry-run wrapper prints to
#   /dev/tty when one exists. The CLI level exercises --test.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Copy ONLY the entry script + lib/ modules: the repo carries ~700MB of
    # website build artifacts (website/node_modules, website/.next), which a
    # full-tree cp would drag into every setup. The CLI entry script sources
    # everything it needs from its own lib/ directory.
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_network() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/network.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

write_nmcli_stub() {
    cat > "$STUB_BIN/nmcli" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_NMCLI_LOG:-}" ] && printf '%s\n' "$*" >> "$UO_NMCLI_LOG"
kind=""
for a in "$@"; do
    case "$a" in
        NAME,DEVICE,TYPE) kind="con" ;;
        DEVICE,TYPE) [ -z "$kind" ] && kind="dev" ;;
    esac
done
case "$kind" in
    con) [ -n "${UO_NMCLI_CONNS_FILE:-}" ] && cat "$UO_NMCLI_CONNS_FILE" ;;
    dev) [ -n "${UO_NMCLI_DEVICES_FILE:-}" ] && cat "$UO_NMCLI_DEVICES_FILE" ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/nmcli"
}

write_conn_fixtures() {
    UO_NMCLI_CONNS_FILE="$TEST_HOME/conns.txt"
    printf 'ETH0:eth0:802-3-ethernet\nWIFI0:wlp3s0:802-11-wireless\n' > "$UO_NMCLI_CONNS_FILE"
    UO_NMCLI_DEVICES_FILE="$TEST_HOME/devices.txt"
    printf 'eth0:ethernet\nwlp3s0:wifi\n' > "$UO_NMCLI_DEVICES_FILE"
    # The nmcli stub is an external process — the fixture paths must be
    # exported or it would answer with empty output
    export UO_NMCLI_CONNS_FILE UO_NMCLI_DEVICES_FILE
}

write_ip_stub() {
    cat > "$STUB_BIN/ip" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"route show default"*) printf 'default via 192.0.2.1 dev stub0\n' ;;
    *"-br addr"*)           printf 'lo               UNKNOWN        127.0.0.1/8\nstub0            UP             192.0.2.10/24\n' ;;
    *"-br link show"*)      printf 'lo               UNKNOWN\nstub0            UP\n' ;;
    *"route"*)              printf 'default via 192.0.2.1 dev stub0\n192.0.2.0/24 dev stub0\n' ;;
    *"link set"*)           exit 0 ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/ip"
}

write_misc_stubs() {
    cat > "$STUB_BIN/ping" << 'EOF'
#!/usr/bin/env bash
printf '2 packets transmitted, 2 received, 0%% packet loss\n'
[ -n "${UO_PING_RC:-}" ] && exit "$UO_PING_RC"
exit 0
EOF
    chmod +x "$STUB_BIN/ping"
    cat > "$STUB_BIN/speedtest-cli" << 'EOF'
#!/usr/bin/env bash
printf 'Download: 100.00 Mbit/s\nUpload: 50.00 Mbit/s\n'
exit 0
EOF
    chmod +x "$STUB_BIN/speedtest-cli"
    cat > "$STUB_BIN/resolvectl" << 'EOF'
#!/usr/bin/env bash
printf 'Global\n       DNS Servers: 8.8.8.8 1.1.1.1\n'
exit 0
EOF
    chmod +x "$STUB_BIN/resolvectl"
    cat > "$STUB_BIN/modinfo" << 'EOF'
#!/usr/bin/env bash
printf 'filename:       /lib/modules/uo/tcp_bbr.ko\n'
exit 0
EOF
    chmod +x "$STUB_BIN/modinfo"
    cat > "$STUB_BIN/apt" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_APT_LOG:-}" ] && printf '%s\n' "$*" >> "$UO_APT_LOG"
case "$*" in
    *speedtest-cli*)
        printf '#!/usr/bin/env bash\nprintf "Download: 100.00 Mbit/s\\n"\n' > "${UO_STUB_BIN:?}/speedtest-cli"
        chmod +x "${UO_STUB_BIN:?}/speedtest-cli"
        ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/apt"
    cat > "$STUB_BIN/sudo" << 'EOF'
#!/usr/bin/env bash
# Pass-through sudo stub — the sourced sudo() function routes here
# via `command sudo`, so wrapped commands run against the PATH stubs.
exec "$@"
EOF
    chmod +x "$STUB_BIN/sudo"
}

# ---------- function level: optimizers ----------

@test "disable_wifi_powersave fails cleanly without an active Wi-Fi connection" {
    load_network
    write_nmcli_stub
    UO_NMCLI_CONNS_FILE="$TEST_HOME/empty.txt"; : > "$UO_NMCLI_CONNS_FILE"
    UO_NMCLI_DEVICES_FILE="$TEST_HOME/empty2.txt"; : > "$UO_NMCLI_DEVICES_FILE"
    PATH="$STUB_BIN:$PATH" run disable_wifi_powersave
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active Wi-Fi connection found."* ]]
}

@test "disable_wifi_powersave previews modify/down/up on the active connection in dry-run" {
    load_network
    write_nmcli_stub
    write_conn_fixtures
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run disable_wifi_powersave
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] Wi-Fi power management would be disabled."* ]]
    [[ "$output" == *"Active connection: WIFI0 (device: wlp3s0)"* ]]
    # The plan (also written to the log) shows exactly which commands were NOT run
    grep -q 'dry-run. sudo nmcli connection modify WIFI0 802-11-wireless.powersave 2' "$LOG_FILE"
    grep -q 'dry-run. sudo nmcli connection down WIFI0' "$LOG_FILE"
    grep -q 'dry-run. sudo nmcli connection up WIFI0' "$LOG_FILE"
}

@test "set_dns rejects an invalid UO_DNS_SERVERS value before touching nmcli" {
    load_network
    write_nmcli_stub
    UO_NMCLI_LOG="$TEST_HOME/nmcli.log"
    UO_DNS_SERVERS="1.1.1.1; rm -rf /tmp/x" UO_NMCLI_LOG="$UO_NMCLI_LOG" PATH="$STUB_BIN:$PATH" run set_dns
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid UO_DNS_SERVERS value"* ]]
    [ ! -s "$UO_NMCLI_LOG" ]   # nothing was ever sent to nmcli
}

@test "set_dns previews custom resolvers on the active connection in dry-run" {
    load_network
    write_nmcli_stub
    write_conn_fixtures
    DRY_RUN=1 UO_DNS_SERVERS="1.1.1.1 9.9.9.9" PATH="$STUB_BIN:$PATH" run set_dns
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] DNS would be set to: 1.1.1.1 9.9.9.9"* ]]
    # The DNS value is %q-quoted in the plan (space → backslash-space)
    grep -q 'modify ETH0 ipv4.dns' "$LOG_FILE"
    grep -q 'modify ETH0 ipv4.ignore-auto-dns yes' "$LOG_FILE"
}

@test "set_dns prefers the ethernet connection over wireless and any" {
    load_network
    write_nmcli_stub
    write_conn_fixtures
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run set_dns
    [ "$status" -eq 0 ]
    grep -q 'modify ETH0' "$LOG_FILE"
    ! grep -q 'modify WIFI0' "$LOG_FILE"
}

@test "enable_bbr previews without loading the module by probing via modinfo" {
    load_network
    write_misc_stubs
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run enable_bbr
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] BBR would be enabled."* ]]
    grep -q 'dry-run. sudo tee -a /etc/sysctl.d/99-ubuntu-optimizer.conf' "$LOG_FILE"
}

@test "optimize_tcp previews the whole BBR companion sysctl set in dry-run" {
    load_network
    write_misc_stubs
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run optimize_tcp
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] TCP parameters would be optimized."* ]]
    # 7 companion keys land in the config, then sysctl --system is planned
    [ "$(grep -c 'tee -a /etc/sysctl.d/99-ubuntu-optimizer.conf' "$LOG_FILE")" -ge 7 ]
    grep -q 'dry-run. sudo sysctl --system' "$LOG_FILE"
}

@test "set_mtu applies 1492 automatically in CLI mode and rejects non-numeric input" {
    load_network
    write_ip_stub
    # CLI/automatic mode → default 1492, planned through the dry-run wrapper
    DRY_RUN=1 CLI_MODE=1 PATH="$STUB_BIN:$PATH" run set_mtu
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] MTU would be set to 1492."* ]]
    grep -q 'dry-run. sudo ip link set dev stub0 mtu 1492' "$LOG_FILE"
    # Interactive mode with garbage input → rejected before anything runs
    bad_mtu_input() { printf 'abc\n' | set_mtu; }
    CLI_MODE=0 ASSUME_YES=0 PATH="$STUB_BIN:$PATH" run bad_mtu_input
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid MTU value: abc"* ]]
}

# ---------- function level: connectivity tests ----------

@test "test_ping and test_ping_dns report success and failure via the stub" {
    load_network
    write_misc_stubs
    PATH="$STUB_BIN:$PATH" run test_ping
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ping successful."* ]]
    UO_PING_RC=1 PATH="$STUB_BIN:$PATH" run test_ping_dns
    [ "$status" -eq 1 ]
    [[ "$output" == *"DNS is broken."* ]]
}

@test "test_speed runs an installed speedtest-cli or installs it via apt first" {
    load_network
    write_misc_stubs
    PATH="$STUB_BIN:$PATH" run test_speed
    [ "$status" -eq 0 ]
    [[ "$output" == *"Speed test completed."* ]]
    # Without a speedtest-cli on PATH, apt is used — the stub materializes it
    rm -f "$STUB_BIN/speedtest-cli"
    UO_APT_LOG="$TEST_HOME/apt.log" UO_STUB_BIN="$STUB_BIN" PATH="$STUB_BIN:$PATH" run test_speed
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing speedtest-cli..."* ]]
    [[ "$output" == *"Speed test completed."* ]]
    grep -q 'install -y speedtest-cli' "$TEST_HOME/apt.log"
    [ -x "$STUB_BIN/speedtest-cli" ]
}

@test "show_network_info prints interfaces, routes and DNS configuration" {
    load_network
    write_ip_stub
    write_misc_stubs
    PATH="$STUB_BIN:$PATH" run show_network_info
    [ "$status" -eq 0 ]
    [[ "$output" == *"Interfaces:"*"stub0"*"192.0.2.10/24"* ]]
    [[ "$output" == *"Routing:"*"default via 192.0.2.1 dev stub0"* ]]
    [[ "$output" == *"DNS:"*"DNS Servers: 8.8.8.8 1.1.1.1"* ]]
}

@test "all_network_opts runs every optimizer in sequence under dry-run" {
    load_network
    write_nmcli_stub
    write_conn_fixtures
    write_ip_stub
    write_misc_stubs
    DRY_RUN=1 CLI_MODE=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run all_network_opts
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disable Wi-Fi Power Management"* ]]
    [[ "$output" == *"Set DNS Servers"* ]]
    [[ "$output" == *"Enable BBR Congestion Control"* ]]
    [[ "$output" == *"Set MTU"* ]]
    [[ "$output" == *"Optimize TCP Parameters"* ]]
    [[ "$output" == *"[dry-run] Wi-Fi power management would be disabled."* ]]
    [[ "$output" == *"[dry-run] DNS would be set to: 8.8.8.8 1.1.1.1"* ]]
    [[ "$output" == *"[dry-run] BBR would be enabled."* ]]
    [[ "$output" == *"[dry-run] MTU would be set to 1492."* ]]
    [[ "$output" == *"[dry-run] TCP parameters would be optimized."* ]]
}

# ---------- CLI level ----------

@test "cli: --test runs ping, DNS, speed and the info overview offline" {
    write_misc_stubs
    write_ip_stub
    PATH="$STUB_BIN:$PATH" run run_uo --test
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ping successful."* ]]
    [[ "$output" == *"DNS is working."* ]]
    [[ "$output" == *"Speed test completed."* ]]
    [[ "$output" == *"Network Info"* ]]
}
