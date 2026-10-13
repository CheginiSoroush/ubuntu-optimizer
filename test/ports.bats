#!/usr/bin/env bats
# ============================================================
#   test/ports.bats — tests for the listening-port report
#   (lib/ports.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   CLI level runs the real entry script with --ports against a
#   stubbed `ss` (and, for the fallback test, a stubbed `netstat`),
#   printing known LISTEN lines — no real network involved. The
#   "tool absent" path runs at function level with a minimal PATH,
#   exactly like test/boot.bats. Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Targeted copy: ubuntu-optimizer.sh + lib/*.sh only — a full-tree cp
    # would drag website/node_modules (~700 MB when present) and stall tests
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # Stub binaries — a fixed, well-understood socket table
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    write_ss_stub
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

write_ss_stub() {
    cat > "$STUB_BIN/ss" << 'EOF'
#!/usr/bin/env bash
# emulate: ss -tulnpH
printf 'tcp   LISTEN 0      128        0.0.0.0:22       0.0.0.0:*    users:(("sshd",pid=800,fd=3))\n'
printf 'tcp   LISTEN 0      5          127.0.0.1:631    0.0.0.0:*    users:(("cupsd",pid=900,fd=6))\n'
printf 'tcp   LISTEN 0      511        [::]:80          [::]:*       users:(("nginx",pid=1))\n'
EOF
    chmod +x "$STUB_BIN/ss"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_ports() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/ports.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: pure classifier ----------

@test "_ports_is_exposed flags the all-interface binds" {
    load_ports
    local addr
    for addr in "0.0.0.0" "::" "*" "[::]"; do
        run _ports_is_exposed "$addr"
        [ "$status" -eq 0 ]
    done
}

@test "_ports_is_exposed passes loopback, LAN and specific IPv6" {
    load_ports
    local addr
    for addr in "127.0.0.1" "192.168.1.5" "[::1]" "10.0.0.2"; do
        run _ports_is_exposed "$addr"
        [ "$status" -eq 1 ]
    done
}

# ---------- CLI level: --ports with a stubbed ss ----------

@test "cli: --ports lists the listeners with their processes" {
    PATH="$STUB_BIN:$PATH" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"Listening Ports"* ]]
    [[ "$output" == *"0.0.0.0:22"* ]]
    [[ "$output" == *"sshd"* ]]
    [[ "$output" == *"127.0.0.1:631"* ]]
    [[ "$output" == *"cupsd"* ]]
    [[ "$output" == *"[::]:80"* ]]
    [[ "$output" == *"nginx"* ]]
}

@test "cli: exposed listeners get the ⚠ marker, loopback does not" {
    PATH="$STUB_BIN:$PATH" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$(grep -F '0.0.0.0:22' <<< "$output")" == *"⚠"* ]]
    [[ "$(grep -F '[::]:80'  <<< "$output")" == *"⚠"* ]]
    [[ "$(grep -F '127.0.0.1:631' <<< "$output")" != *"⚠"* ]]
}

@test "cli: the summary counts the exposed sockets and hints at ufw" {
    PATH="$STUB_BIN:$PATH" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 of 3 listening socket(s) bind all interfaces"* ]]
    [[ "$output" == *"--security"* ]]
    [[ "$output" == *"ufw"* ]]
}

@test "cli: netstat is used when ss is missing" {
    # ss must be genuinely ABSENT: a private bin dir with copies of the tools
    # the run needs (symlinks are not available in every environment) plus the
    # netstat stub — and no ss anywhere on PATH.
    NETSTUB="$TEST_HOME/stub-netstat"
    mkdir -p "$NETSTUB"
    cat > "$NETSTUB/netstat" << 'EOF'
#!/usr/bin/env bash
# emulate: netstat -tulnp
printf 'Active Internet connections (only servers)\n'
printf 'Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name\n'
printf 'tcp        0      0 0.0.0.0:22       0.0.0.0:*      LISTEN      800/sshd\n'
printf 'tcp        0      0 127.0.0.1:631    0.0.0.0:*      LISTEN      900/cupsd\n'
printf 'udp        0      0 0.0.0.0:68       0.0.0.0:*                  500/dhclient\n'
EOF
    chmod +x "$NETSTUB/netstat"
    local tool src
    for tool in bash env du cut find rm ls cat date sed awk grep head tail \
                wc sort tr mkdir chmod readlink dirname basename uname ps \
                locale sleep stty tput; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$NETSTUB/$tool"
    done
    PATH="$NETSTUB" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"Listening Ports"* ]]
    [[ "$output" == *"0.0.0.0:22"* ]]
    [[ "$output" == *"sshd"* ]]
    [[ "$output" == *"dhclient"* ]]                  # udp socket listed too
    [[ "$(grep -F '0.0.0.0:68' <<< "$output")" == *"⚠"* ]]
    [[ "$output" == *"2 of 3 listening socket(s) bind all interfaces"* ]]
}

@test "cli: udp sockets are listed and exposure-checked" {
    cat > "$STUB_BIN/ss" << 'EOF'
#!/usr/bin/env bash
printf 'tcp   LISTEN 0      128        0.0.0.0:22       0.0.0.0:*    users:(("sshd",pid=800,fd=3))\n'
printf 'udp   UNCONN 0      0          0.0.0.0:68       0.0.0.0:*\n'
EOF
    chmod +x "$STUB_BIN/ss"
    PATH="$STUB_BIN:$PATH" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$(grep -F '0.0.0.0:68' <<< "$output")" == *"⚠"* ]]
    [[ "$(grep -F '0.0.0.0:68' <<< "$output")" == *"-"* ]]   # no process info
    [[ "$output" == *"2 of 2 listening socket(s) bind all interfaces"* ]]
}

@test "cli: --ports exits 0 with empty tool output" {
    cat > "$STUB_BIN/ss" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/ss"
    PATH="$STUB_BIN:$PATH" run run_uo --ports
    [ "$status" -eq 0 ]
    [[ "$output" == *"No listening sockets found"* ]]
}

# ---------- function level: degraded path (minimal PATH) ----------

@test "ports_show degrades gracefully without ss and netstat" {
    load_ports
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in sed head tail grep awk cat tr sort uname basename readlink dirname; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" run ports_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Listening Ports"* ]]
    [[ "$output" == *"install iproute2"* ]]
}
