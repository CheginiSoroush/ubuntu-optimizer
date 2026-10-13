#!/usr/bin/env bats
# ============================================================
#   test/health.bats — tests for the health snapshot (lib/health.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The health module is exercised at two levels:
#     • CLI level — the real entry script with --health, backed by
#       stubbed sensors/systemctl/apt on PATH (fast + deterministic)
#       and the documented UO_HEALTH_FAKE_SYSTEMD=1 hook (so the
#       systemd-present path is deterministic on machines with and
#       without a real systemd bus).
#     • Function level — lib/common.sh + lib/health.sh sourced into
#       the test shell with a temp HOME; the percentage/verdict/
#       uptime helpers are pure and need no stubs at all. Degraded
#       paths run against a minimal PATH so "tool absent" is truly
#       simulated, exactly like test/boot.bats does.
#   Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # Stub binaries — deterministic sensors/systemctl/apt answers
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

write_stubs() {
    cat > "$STUB_BIN/sensors" << 'EOF'
#!/bin/bash
printf 'coretemp-isa-0000\n'
printf 'Package id 0:  +45.0°C  (high = +84.0°C)\n'
printf 'Core 0:        +42.0°C\n'
EOF
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/bin/bash
# only the --failed view is stubbed; everything else answers empty
for arg in "$@"; do
    if [ "$arg" = "--failed" ]; then
        printf 'docker.socket         loaded failed failed  Docker Socket for the API\n'
        exit 0
    fi
done
exit 0
EOF
    cat > "$STUB_BIN/apt" << 'EOF'
#!/bin/bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "--upgradable" ]; then
    printf 'Listing... Done\n'
    printf 'curl/jammy-updates,now 7.81.0 amd64 [upgradable from: 7.81.0-1]\n'
    printf 'wget/jammy-updates,now 1.21.2 amd64 [upgradable from: 1.21.2-1]\n'
    exit 0
fi
exit 0
EOF
    chmod +x "$STUB_BIN/sensors" "$STUB_BIN/systemctl" "$STUB_BIN/apt"
}

# Load only the modules a health test needs, into the test shell
load_health() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/health.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: pure helpers ----------

@test "_health_ram_pct computes the used percentage" {
    load_health
    run _health_ram_pct 16000 4000
    [ "$status" -eq 0 ]
    [ "$output" = "75" ]
    run _health_ram_pct 10000 10000
    [ "$output" = "0" ]
    run _health_ram_pct 8000 800
    [ "$output" = "90" ]
}

@test "_health_ram_pct guards zero and unparsable totals" {
    load_health
    run _health_ram_pct 0 0
    [ "$output" = "0" ]
    run _health_ram_pct "" ""
    [ "$output" = "0" ]
    run _health_ram_pct "abc" "5"
    [ "$output" = "0" ]
}

@test "_health_verdict maps the 70/85 boundaries exactly" {
    load_health
    run _health_verdict 69
    [ "$output" = "ok" ]
    run _health_verdict 70
    [ "$output" = "watch" ]
    run _health_verdict 84
    [ "$output" = "watch" ]
    run _health_verdict 85
    [ "$output" = "high" ]
    run _health_verdict 100
    [ "$output" = "high" ]
}

@test "_health_uptime_human renders seconds, minutes and hours" {
    load_health
    run _health_uptime_human 59
    [ "$output" = "59 seconds" ]
    run _health_uptime_human 60
    [ "$output" = "1 minute" ]
    run _health_uptime_human 3600
    [ "$output" = "1 hour" ]
    run _health_uptime_human 3661
    [ "$output" = "1 hour, 1 minute" ]
}

@test "_health_uptime_human renders days (e.g. '3 days, 4 hours')" {
    load_health
    run _health_uptime_human 273600
    [ "$output" = "3 days, 4 hours" ]
    run _health_uptime_human 86400
    [ "$output" = "1 day" ]
    run _health_uptime_human 90061
    [ "$output" = "1 day, 1 hour" ]
    run _health_uptime_human "nonsense"
    [ "$output" = "" ]
}

# ---------- function level: degraded paths (minimal PATH) ----------

@test "health_show degrades gracefully without sensors/ps/df/apt/systemd" {
    load_health
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in awk head tail grep cat tr sed wc sort uname basename readlink dirname; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" UO_HEALTH_FAKE_SYSTEMD=0 run health_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"lm-sensors is not installed"* ]]
    [[ "$output" == *"ps not found"* ]]
    [[ "$output" == *"df not found"* ]]
    [[ "$output" == *"apt not found"* ]]
    [[ "$output" == *"failed-unit check skipped"* ]]
    [[ "$output" == *"No battery found"* ]]
}

# ---------- CLI level: --health with stubs ----------

@test "cli: --health prints every section and exits 0" {
    write_stubs
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=1 run run_uo --health
    [ "$status" -eq 0 ]
    [[ "$output" == *"System Health Snapshot"* ]]
    [[ "$output" == *"Load average:"* ]]
    [[ "$output" == *"RAM:"* ]]
    [[ "$output" == *"45.0°C"* ]]
    [[ "$output" == *"No battery found"* ]]
    [[ "$output" == *"Up for:"* ]]
}

@test "cli: --health counts the failed unit via the stubbed systemctl" {
    write_stubs
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=1 run run_uo --health
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 failed unit(s)"* ]]
}

@test "cli: --health counts pending apt updates" {
    write_stubs
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=1 run run_uo --health
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 package update(s) pending"* ]]
}

@test "cli: --health reports no pending updates when apt lists none" {
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/apt" << 'EOF'
#!/bin/bash
printf 'Listing... Done\n'
exit 0
EOF
    chmod +x "$STUB_BIN/apt"
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=1 run run_uo --health
    [ "$status" -eq 0 ]
    [[ "$output" == *"No package updates pending"* ]]
}

@test "cli: --health skips the systemd section without the fake-systemd hook" {
    write_stubs
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=0 run run_uo --health
    [ "$status" -eq 0 ]
    [[ "$output" == *"failed-unit check skipped"* ]]
}

@test "cli: --health is a queued action (composable with other flags)" {
    write_stubs
    PATH="$STUB_BIN:$PATH" UO_HEALTH_FAKE_SYSTEMD=1 run run_uo --health -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"System Health Snapshot"* ]]
}
