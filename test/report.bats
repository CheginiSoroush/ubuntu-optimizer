#!/usr/bin/env bats
# ============================================================
#   test/report.bats — tests for the status report (lib/report.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Function level: lib/common.sh + lib/cache.sh + lib/report.sh
#   are sourced into the test shell with a sandbox HOME. All
#   system probes are PATH stubs (free/df/systemctl/sysctl/ip/
#   ping/timeout/curl) so the report content is deterministic,
#   fast and fully offline — the /dev/tcp fallback probe is
#   neutralized through a failing `timeout` stub.
#   (--report CLI caching is covered by test/cache.bats.)
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    # Copy ONLY the entry script + lib/ modules: the repo carries ~700MB of
    # website build artifacts (website/node_modules, website/.next), which a
    # full-tree cp would drag into every setup. The CLI entry script sources
    # everything it needs from its own lib/ directory.
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
    export TERM="${TERM:-xterm}"

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"

    # free — canned Mem/Swap lines in bytes (env-tunable)
    cat > "$STUB_BIN/free" << 'EOF'
#!/usr/bin/env bash
printf 'Mem:  %s %s 0 0 0 0\n' "${UO_FAKE_MEM_TOTAL:-8000000000}" "${UO_FAKE_MEM_USED:-2000000000}"
printf 'Swap: %s %s 0\n' "${UO_FAKE_SWAP_TOTAL:-2000000000}" "${UO_FAKE_SWAP_USED:-1000000000}"
EOF

    # df — one root filesystem line (env-tunable use%)
    cat > "$STUB_BIN/df" << 'EOF'
#!/usr/bin/env bash
printf 'Filesystem Type Size Used Avail Use%% Mounted\n'
printf '/dev/sda1 ext4 50G 45G 5G %s /\n' "${UO_FAKE_ROOT_USE:-40%}"
EOF

    # systemctl — only the failed-units view is stubbed
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "--state=failed" ]; then
        case "${UO_FAKE_FAILED:-}" in
            one) printf 'docker.socket    loaded failed failed  Docker Socket\n' ;;
            two) printf 'docker.socket    loaded failed failed  Docker Socket\n'
                 printf 'nginx.service    loaded failed failed  A web server\n' ;;
        esac
        exit 0
    fi
done
exit 0
EOF

    # sysctl -n KEY — canned optimization values (env-tunable)
    cat > "$STUB_BIN/sysctl" << 'EOF'
#!/usr/bin/env bash
[ "$1" = "-n" ] || exit 0
case "$2" in
    net.ipv4.tcp_congestion_control) echo "${UO_FAKE_BBR:-bbr}" ;;
    vm.swappiness)                   echo "${UO_FAKE_SWAPPINESS:-10}" ;;
    vm.vfs_cache_pressure)           echo "${UO_FAKE_VCP:-50}" ;;
    net.ipv4.tcp_notsent_lowat)      echo "16384" ;;
    net.ipv4.tcp_fastopen)           echo "3" ;;
    net.core.rmem_max)               echo "16777216" ;;
    *) exit 0 ;;
esac
EOF

    # ip — default route on eth0 (env-tunable absence)
    cat > "$STUB_BIN/ip" << 'EOF'
#!/usr/bin/env bash
if [ "${UO_FAKE_DEFROUTE:-1}" = "1" ]; then
    printf 'default via 192.168.1.1 dev eth0 proto dhcp metric 100\n'
fi
exit 0
EOF

    # ping / timeout / curl — the connectivity probe is fully stubbed
    # (default: ping answers, /dev/tcp and HTTP probes fail → hermetic & fast)
    cat > "$STUB_BIN/ping" << 'EOF'
#!/usr/bin/env bash
exit "${UO_FAKE_PING_RC:-0}"
EOF
    cat > "$STUB_BIN/timeout" << 'EOF'
#!/usr/bin/env bash
# the raw /dev/tcp probes must never touch a real network in tests
exit "${UO_FAKE_TIMEOUT_RC:-1}"
EOF
    cat > "$STUB_BIN/curl" << 'EOF'
#!/usr/bin/env bash
exit "${UO_FAKE_CURL_RC:-7}"
EOF
    chmod +x "$STUB_BIN/free" "$STUB_BIN/df" "$STUB_BIN/systemctl" \
             "$STUB_BIN/sysctl" "$STUB_BIN/ip" "$STUB_BIN/ping" \
             "$STUB_BIN/timeout" "$STUB_BIN/curl"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/cache.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/report.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
    CACHE_DIR="$TEST_HOME/.local/share/ubuntu-optimizer/cache"
    # LOG_FILE comes from lib/common.sh and already points into the sandbox HOME
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- pure helpers ----------

@test "_report_line renders pass and fail with optional details" {
    run _report_line 1 "BBR" "current: bbr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ BBR — current: bbr"* ]]
    run _report_line 0 "swappiness"
    [[ "$output" == *"✗ swappiness"* ]]
    # a fail line must never contain the pass mark and vice versa
    run _report_line 1 "only-pass"
    [[ "$output" == *"✓"* ]]
    [[ "$output" != *"✗"* ]]
}

@test "_fmt_size uses numfmt when present and falls back to whole MB without it" {
    run _fmt_size 1073741824
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.0G"* ]]
    # a PATH without numfmt → pure-bash whole-MB arithmetic
    EMPTY_BIN="$TEST_HOME/empty-bin"
    mkdir -p "$EMPTY_BIN"
    PATH="$EMPTY_BIN" run _fmt_size 52428800
    [ "$output" = "50 MB" ]
}

# ---------- connectivity probe ----------

@test "_net_has_internet_probe succeeds via ping and fails fast when every method is blocked" {
    # default stubs: ping answers → online
    PATH="$STUB_BIN:$PATH" run _net_has_internet_probe
    [ "$status" -eq 0 ]
    # every method blocked → offline, and the stubs make it instant
    UO_FAKE_PING_RC=1 UO_FAKE_TIMEOUT_RC=1 UO_FAKE_CURL_RC=7 \
        PATH="$STUB_BIN:$PATH" run _net_has_internet_probe
    [ "$status" -eq 1 ]
}

# ---------- full report ----------

@test "system_report prints every section with stubbed system tools" {
    PATH="$STUB_BIN:$PATH" run system_report
    [ "$status" -eq 0 ]
    [[ "$output" == *"System Status Report"* ]]
    [[ "$output" == *"Memory:"* ]]
    [[ "$output" == *"RAM: "* ]]
    [[ "$output" == *"Swap: "* ]]
    [[ "$output" == *"Disks:"* ]]
    [[ "$output" == *"total: 50G"* ]]
    [[ "$output" == *"All system services are healthy."* ]]
    [[ "$output" == *"Optimization status"* ]]
    [[ "$output" == *"✓ BBR — current: bbr"* ]]
    [[ "$output" == *"Network:"* ]]
    [[ "$output" == *"Default interface: eth0"* ]]
    [[ "$output" == *"Internet connection is up."* ]]
    # no critical RAM warning at 25 % usage
    [[ "$output" != *"Critical RAM usage"* ]]
}

@test "system_report surfaces failed units, critical RAM, high swap and a full disk" {
    UO_FAKE_FAILED=two UO_FAKE_MEM_USED=7600000000 UO_FAKE_SWAP_USED=1800000000 \
        UO_FAKE_ROOT_USE=90% PATH="$STUB_BIN:$PATH" run system_report
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 service(s) in a failed state"* ]]
    [[ "$output" == *"docker.socket"* ]]
    [[ "$output" == *"nginx.service"* ]]
    [[ "$output" == *"Critical RAM usage!"* ]]
    [[ "$output" == *"High swap usage"* ]]
    [[ "$output" == *"90%"* ]]
}

@test "system_report reports offline when every probe is blocked and caches the verdict" {
    UO_FAKE_PING_RC=1 UO_FAKE_TIMEOUT_RC=1 UO_FAKE_CURL_RC=7 \
        PATH="$STUB_BIN:$PATH" run system_report
    [ "$status" -eq 0 ]
    [[ "$output" == *"No internet connection!"* ]]
    # the offline verdict is stored with the short TTL for a fast re-check
    [ -f "$CACHE_DIR/net:internet" ]
    local v
    v=$(tail -n +2 "$CACHE_DIR/net:internet")
    [ "$v" = "0" ]
}

@test "system_report logs exactly one INFO line and never OK/ERROR lines" {
    PATH="$STUB_BIN:$PATH" run system_report
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    [ "$(grep -c " INFO " "$LOG_FILE")" -eq 1 ]
    grep -q "INFO  *System status report displayed" "$LOG_FILE"
    [ "$(grep -c " OK " "$LOG_FILE")" -eq 0 ]
    [ "$(grep -c " ERROR " "$LOG_FILE")" -eq 0 ]
}
