#!/usr/bin/env bats
# ============================================================
#   test/swap.bats — tests for the swap manager (lib/swap.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The swap module is exercised at two levels:
#     • CLI level — the real entry script with --swap against fake
#       /proc/swaps / swappiness / meminfo files built through the
#       documented UO_SWAP_FAKE_* hooks.
#     • Function level — lib/common.sh + lib/swap.sh sourced into the
#       test shell: the /proc/swaps parser, the swapfile detection, the
#       swappiness descriptions and the size recommendation table.
#   Everything runs fully offline; nothing is swapped on or off.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # a fake /proc/swaps: one swapfile + one partition
    SWAPS_FILE="$TEST_HOME/fake-swaps"
    cat > "$SWAPS_FILE" << 'EOF'
Filename                                Type            Size    Used    Priority
/swapfile                               file            2097148 1024    -2
/dev/sda2                               partition       4194300 0       -3
EOF
    export UO_SWAP_FAKE_SWAPS="$SWAPS_FILE"
    export UO_SWAP_FAKE_SWAPPINESS="60"

    # a fake meminfo: 4 GB RAM
    MEMINFO_FILE="$TEST_HOME/fake-meminfo"
    cat > "$MEMINFO_FILE" << 'EOF'
MemTotal:        4140000 kB
MemFree:         3000000 kB
SwapTotal:        2097148 kB
EOF
    export UO_SWAP_FAKE_MEMINFO="$MEMINFO_FILE"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a swap test needs, into the test shell
load_swap() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/swap.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: the /proc/swaps parser ----------

@test "_swap_status_mb sums the size column over both devices" {
    load_swap
    run _swap_status_mb
    [ "$status" -eq 0 ]
    [ "$output" = "6143" ]
}

@test "_swap_status_mb is 0 without any swap device" {
    load_swap
    printf 'Filename\t\t\t\tType\t\tSize\tUsed\tPriority\n' > "$TEST_HOME/empty-swaps"
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/empty-swaps" run _swap_status_mb
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "_swap_status_mb is 0 for a missing swaps file" {
    load_swap
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/no-such-swaps" run _swap_status_mb
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "_swap_has_file detects the swapfile and ignores the partition" {
    load_swap
    # the setup's fake /proc/swaps lists /swapfile → active
    run _swap_has_file
    [ "$status" -eq 0 ]
    # only the partition listed → no swapfile
    printf 'Filename\t\t\t\tType\t\tSize\tUsed\tPriority\n/dev/sda2  partition  4194300  0  -3\n' > "$TEST_HOME/part-only"
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/part-only" run _swap_has_file
    [ "$status" -ne 0 ]
}

@test "_swap_has_file on a header-only swaps file is false" {
    load_swap
    printf 'Filename\t\t\t\tType\t\tSize\tUsed\tPriority\n' > "$TEST_HOME/header-only"
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/header-only" run _swap_has_file
    [ "$status" -ne 0 ]
}

# ---------- function level: swappiness + recommendation ----------

@test "_swap_swappiness reads the value from the hook" {
    load_swap
    run _swap_swappiness
    [ "$output" = "60" ]
    UO_SWAP_FAKE_SWAPPINESS=10 run _swap_swappiness
    [ "$output" = "10" ]
}

@test "_swap_swappiness_desc maps the important ranges" {
    load_swap
    run _swap_swappiness_desc 10
    [[ "$output" == *"desktop"* ]]
    run _swap_swappiness_desc 60
    [[ "$output" == *"Ubuntu default"* ]]
    run _swap_swappiness_desc 100
    [[ "$output" == *"server"* ]]
    run _swap_swappiness_desc 42
    [[ "$output" == *"custom"* ]]
}

@test "_swap_recommend_mb applies the classic RAM table" {
    load_swap
    # 4 GB RAM → equal swap
    run _swap_recommend_mb
    [ "$output" = "4042" ]
    # 2 GB RAM → double
    printf 'MemTotal:        2048000 kB\n' > "$TEST_HOME/mem-2g"
    UO_SWAP_FAKE_MEMINFO="$TEST_HOME/mem-2g" run _swap_recommend_mb
    [ "$output" = "4000" ]
    # 16 GB RAM → flat 4096
    printf 'MemTotal:       16384000 kB\n' > "$TEST_HOME/mem-16g"
    UO_SWAP_FAKE_MEMINFO="$TEST_HOME/mem-16g" run _swap_recommend_mb
    [ "$output" = "4096" ]
    # unreadable meminfo → 2048 → doubled
    UO_SWAP_FAKE_MEMINFO="$TEST_HOME/no-such-meminfo" run _swap_recommend_mb
    [ "$output" = "4096" ]
}

# ---------- CLI level ----------

@test "cli: --swap lists the devices, total and swappiness" {
    run run_uo --swap
    [ "$status" -eq 0 ]
    [[ "$output" == *"Swap Status"* ]]
    [[ "$output" == *"/swapfile"* ]]
    [[ "$output" == *"Total swap: 6143 MB"* ]]
    [[ "$output" == *"vm.swappiness = 60"* ]]
    [[ "$output" == *"Ubuntu default"* ]]
}

@test "cli: --swap warns and recommends when no swap exists" {
    printf 'Filename\t\t\t\tType\t\tSize\tUsed\tPriority\n' > "$TEST_HOME/empty-swaps"
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/empty-swaps" run run_uo --swap
    [ "$status" -eq 0 ]
    [[ "$output" == *"No swap is active"* ]]
    [[ "$output" == *"swapfile (uo --swap-on)"* ]]
}

@test "cli: --swap-on with an invalid size is rejected up front" {
    run run_uo --swap-on abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid swap size"* ]]
}

@test "cli: --swap-on in dry-run prints the plan and changes nothing" {
    # the swapfile must NOT already be active for the create flow to run;
    # GitHub runners ship a pre-existing /swapfile, so only the unchanged
    # before/after state is asserted — a dry-run never creates or removes it
    local existed=0
    [ -e /swapfile ] && existed=1
    printf 'Filename\t\t\t\tType\t\tSize\tUsed\tPriority\n/dev/sda2  partition  4194300  0  -3\n' > "$TEST_HOME/part-only"
    UO_SWAP_FAKE_SWAPS="$TEST_HOME/part-only" run run_uo --dry-run --swap-on 2048 -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"2048 MB"* ]]
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"would be enabled"* ]]
    # proof that nothing was executed: the before/after state is identical
    if [ "$existed" = "0" ]; then
        [ ! -e /swapfile ]
    else
        [ -e /swapfile ]
    fi
}

@test "cli: --swappiness validation rejects out-of-range values" {
    run run_uo --swappiness 0
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid swappiness"* ]]
    run run_uo --swappiness 101
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid swappiness"* ]]
    run run_uo --swappiness
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a value"* ]]
}

@test "cli: --swappiness in dry-run prints the write plan" {
    run run_uo --dry-run --swappiness 10 -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Swappiness → 10"* ]]
    [[ "$output" == *"desktop"* ]]
    [[ "$output" == *"would be set"* ]]
}

@test "cli: --swap-off in dry-run never touches the filesystem" {
    # dry-run only prints — with or without an existing /swapfile the
    # run must report the plan (or nothing-to-remove) and exit 0
    local existed=0
    [ -e /swapfile ] && existed=1
    run run_uo --dry-run --swap-off -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to remove"* ]] || [[ "$output" == *"dry-run"* ]]
    # proof that nothing was executed: the before/after state is identical
    if [ "$existed" = "0" ]; then
        [ ! -e /swapfile ]
    else
        [ -e /swapfile ]
    fi
}
