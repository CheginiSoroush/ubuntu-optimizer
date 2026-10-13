#!/usr/bin/env bats
# ============================================================
#   test/dnsswitch.bats — tests for the DNS preset switcher
#   (lib/dnsswitch.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The DNS module is exercised at two levels:
#     • CLI level — the real entry script with --dns-list and the
#       --dns parser validation (unknown names are rejected before
#       anything can run).
#     • Function level — lib/common.sh + lib/dnsswitch.sh sourced
#       into the test shell: the preset table, the resolv.conf parser
#       (via the documented UO_DNS_FAKE_RESOLV hook) and the
#       interactive picker validation.
#   Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # Deterministic network tools — the real nmcli/resolvectl of the test
    # machine must never decide which apply mechanism runs. The stub nmcli
    # answers one active ethernet connection and an unset ipv4.dns; the
    # stub resolvectl always fails (drives the flow to nmcli / resolv.conf).
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/nmcli" << 'EOF'
#!/usr/bin/env bash
case " $* " in
    *" -t -f NAME,DEVICE,TYPE con show --active "*)
        printf 'Wired connection 1:eth0:802-3-ethernet\n'
        ;;
    *" -g ipv4.dns connection show "*)
        printf -- '--\n'
        ;;
    *)
        exit 0
        ;;
esac
EOF
    cat > "$STUB_BIN/resolvectl" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STUB_BIN/nmcli" "$STUB_BIN/resolvectl"
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a dns test needs, into the test shell
load_dns() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/dnsswitch.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: the preset table ----------

@test "_dnsswitch_servers maps every known preset to its addresses" {
    load_dns
    run _dnsswitch_servers shecan
    [ "$output" = "178.22.122.100 185.51.200.2" ]
    run _dnsswitch_servers 403online
    [ "$output" = "10.202.10.202 10.202.10.102" ]
    run _dnsswitch_servers radar
    [ "$output" = "10.202.10.10 10.202.10.11" ]
    run _dnsswitch_servers electro
    [ "$output" = "78.157.42.100 78.157.42.101" ]
    run _dnsswitch_servers cloudflare
    [ "$output" = "1.1.1.1 1.0.0.1" ]
    run _dnsswitch_servers google
    [ "$output" = "8.8.8.8 8.8.4.4" ]
    run _dnsswitch_servers quad9
    [ "$output" = "9.9.9.9 149.112.112.112" ]
    run _dnsswitch_servers adguard
    [ "$output" = "94.140.14.14 94.140.15.15" ]
}

@test "_dnsswitch_servers returns empty for auto and unknown names" {
    load_dns
    run _dnsswitch_servers auto
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run _dnsswitch_servers no-such-preset
    [ "$output" = "" ]
}

@test "dnsswitch_preset_valid accepts the nine names and nothing else" {
    load_dns
    local p
    for p in shecan 403online radar electro cloudflare google quad9 adguard auto; do
        dnsswitch_preset_valid "$p"
    done
    run dnsswitch_preset_valid shecanx
    [ "$status" -ne 0 ]
    run dnsswitch_preset_valid ""
    [ "$status" -ne 0 ]
}

@test "_dnsswitch_desc describes every preset (non-empty)" {
    load_dns
    local p
    for p in shecan 403online radar electro cloudflare google quad9 adguard auto; do
        run _dnsswitch_desc "$p"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
    done
}

# ---------- function level: the resolvectl link parser ----------

@test "_dnsswitch_parse_links extracts 'Link N (iface)' lines, skips loopback" {
    load_dns
    run _dnsswitch_parse_links "" << 'EOF'
Global
Link 1 (lo)
Link 2 (eth0)
Link 3 (wlan0)
EOF
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "eth0" ]
    [ "${lines[1]}" = "wlan0" ]
}

@test "_dnsswitch_parse_links puts the default-route interface first" {
    load_dns
    run _dnsswitch_parse_links "wlan0" << 'EOF'
Global
Link 1 (lo)
Link 2 (eth0)
Link 3 (wlan0)
EOF
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "wlan0" ]
    [ "${lines[1]}" = "eth0" ]
}

@test "_dnsswitch_parse_links on an empty listing prints nothing" {
    load_dns
    # stdin MUST be closed — the parser reads the listing from stdin and
    # would otherwise block on the test runner's inherited input
    run _dnsswitch_parse_links "" < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------- function level: the current-resolver detection ----------

@test "dnsswitch_current parses a resolv.conf and skips the localhost stub" {
    load_dns
    cat > "$TEST_HOME/fake-resolv.conf" << 'EOF'
# managed by ubuntu-optimizer (uo --dns)
nameserver 127.0.0.53
options edns0 trust-ad
search lan
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
    # no resolvectl / nmcli on the test PATH is not guaranteed — the
    # resolv.conf path is forced by pointing the hook at the fake file
    # and running with a minimal PATH that lacks both tools
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in awk grep head tail printf tr sed sort cat; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" UO_DNS_FAKE_RESOLV="$TEST_HOME/fake-resolv.conf" run dnsswitch_current
    [ "$status" -eq 0 ]
    [[ "$output" == *"178.22.122.100"* ]]
    [[ "$output" == *"185.51.200.2"* ]]
    [[ "$output" != *"127.0.0.53"* ]]
}

@test "dnsswitch_current stays empty on an unreadable resolv.conf" {
    load_dns
    UO_DNS_FAKE_RESOLV="$TEST_HOME/does-not-exist.conf" run dnsswitch_current
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------- CLI level ----------

@test "cli: --dns-list prints the preset table and the apply hint" {
    run run_uo --dns-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"DNS Presets"* ]]
    [[ "$output" == *"shecan"* ]]
    [[ "$output" == *"178.22.122.100 185.51.200.2"* ]]
    [[ "$output" == *"cloudflare"* ]]
    [[ "$output" == *"auto"* ]]
    [[ "$output" == *"--dns <preset>"* ]]
}

@test "cli: --dns-list marks the currently active preset" {
    # point the current-resolver detection at a fake resolv.conf that
    # contains exactly the shecan pair → the table must flag it
    cat > "$TEST_HOME/shecan-resolv.conf" << 'EOF'
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
    UO_DNS_FAKE_RESOLV="$TEST_HOME/shecan-resolv.conf" run run_uo --dns-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"(current)"* ]]
}

@test "cli: --dns with an unknown preset is rejected up front" {
    run run_uo --dns no-such-preset
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown DNS preset"* ]]
    [[ "$output" == *"Valid presets"* ]]
}

@test "cli: --dns with a valid preset is queued (composable, dry-run safe)" {
    run run_uo --dry-run --dns shecan -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Switch DNS"* ]]
    [[ "$output" == *"178.22.122.100 185.51.200.2"* ]]
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"NetworkManager connection 'Wired connection 1'"* ]]
}

@test "cli: --dns auto is accepted as a valid preset" {
    run run_uo --dry-run --dns auto -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Switch DNS → auto"* ]]
    [[ "$output" == *"DHCP"* ]]
    [[ "$output" == *"NetworkManager connection 'Wired connection 1'"* ]]
}

# ---------- interactive picker ----------

@test "dnsswitch_pick declines an unknown answer without touching anything" {
    load_dns
    ASSUME_YES=0
    run dnsswitch_pick <<< "not-a-preset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unknown preset"* ]]
}

@test "dnsswitch_pick with an empty answer cancels" {
    load_dns
    run dnsswitch_pick <<< ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
}
