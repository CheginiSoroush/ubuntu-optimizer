#!/usr/bin/env bats
# ============================================================
#   test/boot.bats — tests for the boot diagnostics (lib/boot.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The boot module is exercised at two levels:
#     • CLI level — the real entry script with --boot, backed by
#       stubbed systemd-analyze / systemctl on PATH and the
#       documented UO_BOOT_FAKE_SYSTEMD=1 hook (so the
#       systemd-present path is deterministic on machines with
#       and without a real systemd bus).
#     • Function level — lib/common.sh + lib/boot.sh sourced
#       into the test shell with a temp HOME; the time-literal
#       parser and the verdict thresholds are pure functions
#       and need no stubs at all.
#   Everything runs fully offline.
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

    # Stub binaries — deterministic systemd answers, no real bus needed
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/systemd-analyze" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    blame)
        printf '5.204s udev.service\n'
        printf '2.871s networkd.service\n'
        printf '1.102s docker.service\n'
        ;;
    critical-chain)
        printf 'The time when unit became active or started is printed after the "@" character.\n'
        printf 'The time the unit spent to start is printed after the "+" character.\n'
        printf 'multi-user.target @7.201s\n'
        printf '+docker.service @6.001s +1.200s\n'
        ;;
    "")
        printf 'Startup finished in 2.584s (kernel) + 4.712s (initrd) + 5.201s (userspace) = 12.497s\n'
        ;;
    *)
        exit 0
        ;;
esac
EOF
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
# only the --failed view is stubbed; everything else answers empty
for arg in "$@"; do
    if [ "$arg" = "--failed" ]; then
        printf 'docker.socket         loaded failed failed  Docker Socket for the API\n'
        printf 'nginx.service         loaded failed failed  A high performance web server\n'
        exit 0
    fi
done
exit 0
EOF
    chmod +x "$STUB_BIN/systemd-analyze" "$STUB_BIN/systemctl"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a boot test needs, into the test shell
load_boot() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/boot.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: time literal parser ----------

@test "_boot_seconds parses plain seconds" {
    load_boot
    run _boot_seconds "9.378s"
    [ "$status" -eq 0 ]
    [ "$output" = "9" ]
}

@test "_boot_seconds parses minutes with seconds" {
    load_boot
    run _boot_seconds "1min 9.378s"
    [ "$output" = "69" ]
}

@test "_boot_seconds parses bare minutes and hours+minutes" {
    load_boot
    run _boot_seconds "2min"
    [ "$output" = "120" ]
    run _boot_seconds "1h 2min"
    [ "$output" = "3720" ]
}

@test "_boot_seconds skips unparsable chunks" {
    load_boot
    run _boot_seconds "abc 3.2s"
    [ "$output" = "3" ]
    run _boot_seconds ""
    [ "$output" = "0" ]
}

# ---------- function level: verdict thresholds ----------

@test "_boot_verdict maps seconds to the four verdicts" {
    load_boot
    run _boot_verdict 7
    [[ "$output" == *"Excellent"* ]]
    run _boot_verdict 25
    [[ "$output" == *"Good"* ]]
    run _boot_verdict 50
    [[ "$output" == *"Slow"* ]]
    run _boot_verdict 120
    [[ "$output" == *"Very slow"* ]]
    run _boot_verdict 0
    [ "$output" = "" ]
}

# ---------- function level: degradation without systemd tools ----------

@test "boot_show degrades gracefully without systemd tools" {
    load_boot
    # PATH without systemd-analyze/systemctl — the guard must catch it
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in awk head tail printf wc grep tr cat sed basename sort uname; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" UO_BOOT_FAKE_SYSTEMD=0 run boot_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"boot analysis skipped"* ]]
}

@test "boot_failed_show degrades gracefully without systemctl" {
    load_boot
    MIN_BIN="$TEST_HOME/min-bin2"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in awk head tail printf wc grep tr cat sed basename sort uname; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" UO_BOOT_FAKE_SYSTEMD=0 run boot_failed_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed System Units"* ]]
    [[ "$output" == *"skipped"* ]]
}

# ---------- CLI level: --boot with stubbed systemd ----------

@test "cli: --boot prints the total boot time and the excellent verdict" {
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run run_uo --boot
    [ "$status" -eq 0 ]
    [[ "$output" == *"Boot Time Analysis"* ]]
    [[ "$output" == *"12.497s"* ]]
    [[ "$output" == *"Excellent"* ]]
}

@test "cli: --boot shows the blame units and the critical chain" {
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run run_uo --boot
    [ "$status" -eq 0 ]
    [[ "$output" == *"udev.service"* ]]
    [[ "$output" == *"docker.service"* ]]
    [[ "$output" == *"Critical chain"* ]]
    [[ "$output" == *"multi-user.target"* ]]
}

@test "cli: --boot reports the failed units with their count" {
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run run_uo --boot
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 failed unit(s)"* ]]
    [[ "$output" == *"docker.socket"* ]]
    [[ "$output" == *"nginx.service"* ]]
}

@test "cli: --boot is a queued action (composable with other flags)" {
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run run_uo --boot -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Boot Time Analysis"* ]]
}

# ---------- CLI level: standalone failed-units entry ----------

@test "cli: boot_failed_show lists failed units under its own header" {
    load_boot
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run boot_failed_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed System Units"* ]]
    [[ "$output" == *"docker.socket"* ]]
}

@test "boot_failed_list reports success when nothing failed" {
    load_boot
    # quiet stub: systemctl never claims --failed
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/systemctl"
    PATH="$STUB_BIN:$PATH" UO_BOOT_FAKE_SYSTEMD=1 run boot_failed_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No failed units"* ]]
}
