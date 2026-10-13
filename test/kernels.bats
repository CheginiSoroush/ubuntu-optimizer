#!/usr/bin/env bats
# ============================================================
#   test/kernels.bats — tests for the old-kernel cleanup
#   (lib/kernels.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The kernel module is exercised at two levels:
#     • CLI level — the real entry script with --kernel-list against a
#       fake /boot built through the documented UO_KERNEL_BOOT_DIR /
#       UO_KERNEL_FAKE_RUNNING hooks.
#     • Function level — lib/common.sh + lib/kernels.sh sourced into
#       the test shell: the version sort, the protected-set logic (the
#       running and the newest kernel can never be candidates) and the
#       keep-count floor.
#   Everything runs fully offline; nothing is purged.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # a fake /boot with four kernels — the running one is second-newest
    BOOT_DIR="$TEST_HOME/fakeboot"
    mkdir -p "$BOOT_DIR"
    touch "$BOOT_DIR/vmlinuz-6.2.0-39-generic"
    touch "$BOOT_DIR/vmlinuz-6.5.0-17-generic"
    touch "$BOOT_DIR/vmlinuz-6.8.0-45-generic"
    touch "$BOOT_DIR/vmlinuz-6.8.0-51-generic"
    export UO_KERNEL_BOOT_DIR="$BOOT_DIR"
    export UO_KERNEL_FAKE_RUNNING="6.8.0-45-generic"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a kernel test needs, into the test shell
load_kernels() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/kernels.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: the installed-kernel listing ----------

@test "_kernels_installed lists every vmlinuz version, oldest first" {
    load_kernels
    run _kernels_installed
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "6.2.0-39-generic" ]
    [ "${lines[1]}" = "6.5.0-17-generic" ]
    [ "${lines[2]}" = "6.8.0-45-generic" ]
    [ "${lines[3]}" = "6.8.0-51-generic" ]
}

@test "_kernels_installed is empty for a missing boot directory" {
    load_kernels
    UO_KERNEL_BOOT_DIR="$TEST_HOME/no-such-boot" run _kernels_installed
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_kernels_newest picks the version-sorted last entry" {
    load_kernels
    run _kernels_newest
    [ "$output" = "6.8.0-51-generic" ]
}

@test "_kernels_keep_count enforces the floor of 2" {
    load_kernels
    UO_KERNEL_KEEP=1 run _kernels_keep_count
    [ "$output" = "2" ]
    UO_KERNEL_KEEP=5 run _kernels_keep_count
    [ "$output" = "5" ]
    UO_KERNEL_KEEP=garbage run _kernels_keep_count
    [ "$output" = "2" ]
    run _kernels_keep_count
    [ "$output" = "2" ]
}

# ---------- function level: the protected-set logic ----------

@test "_kernels_remove_candidates keeps running + newest (default keep=2)" {
    load_kernels
    run _kernels_remove_candidates
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "6.2.0-39-generic" ]
    [ "${lines[1]}" = "6.5.0-17-generic" ]
}

@test "_kernels_remove_candidates honors UO_KERNEL_KEEP=3" {
    load_kernels
    UO_KERNEL_KEEP=3 run _kernels_remove_candidates
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "6.2.0-39-generic" ]
}

@test "_kernels_remove_candidates never selects the running kernel" {
    load_kernels
    # running is the OLDEST kernel — it must still be protected
    UO_KERNEL_FAKE_RUNNING="6.2.0-39-generic" run _kernels_remove_candidates
    [ "$status" -eq 0 ]
    for line in "${lines[@]}"; do
        [ "$line" != "6.2.0-39-generic" ]
    done
    [ "${lines[0]}" = "6.5.0-17-generic" ]
}

@test "_kernels_remove_candidates is empty when everything is protected" {
    load_kernels
    # only two kernels, running = newest → nothing can ever be removed
    rm "$BOOT_DIR/vmlinuz-6.2.0-39-generic" "$BOOT_DIR/vmlinuz-6.5.0-17-generic" "$BOOT_DIR/vmlinuz-6.8.0-45-generic"
    UO_KERNEL_FAKE_RUNNING="6.8.0-51-generic" run _kernels_remove_candidates
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_kernels_packages_for returns nothing without dpkg-query" {
    load_kernels
    # the test environment may have dpkg-query — force the degraded path
    # with a PATH that lacks it; the pure-Bash guard must yield empty
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool
    for tool in awk basename cat grep head printf sed sort tail uname; do
        ln -sf "$(command -v "$tool")" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" run _kernels_packages_for "6.8.0-51-generic"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------- CLI level ----------

@test "cli: --kernel-list marks the running and the newest kernel" {
    run run_uo --kernel-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed Kernels"* ]]
    [[ "$output" == *"6.2.0-39-generic"* ]]
    [[ "$output" == *"6.8.0-51-generic"*"newest"* ]]
    [[ "$output" == *"6.8.0-45-generic"*"running"* ]]
    [[ "$output" == *"2 old kernel(s) could be removed"* ]]
}

@test "cli: --kernel-list reports nothing to clean when all are protected" {
    rm "$BOOT_DIR/vmlinuz-6.2.0-39-generic" "$BOOT_DIR/vmlinuz-6.5.0-17-generic" "$BOOT_DIR/vmlinuz-6.8.0-45-generic"
    UO_KERNEL_FAKE_RUNNING="6.8.0-51-generic" run run_uo --kernel-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No old kernels"* ]]
}

@test "cli: --kernel-clean reports nothing to do when all are protected" {
    rm "$BOOT_DIR/vmlinuz-6.2.0-39-generic" "$BOOT_DIR/vmlinuz-6.5.0-17-generic" "$BOOT_DIR/vmlinuz-6.8.0-45-generic"
    UO_KERNEL_FAKE_RUNNING="6.8.0-51-generic" run run_uo --kernel-clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"No old kernels found"* ]]
}

@test "cli: --kernel-clean refuses to purge /boot files dpkg does not own" {
    # the fake kernels exist in /boot but no packages match them → the
    # purge list stays empty and nothing is removed
    run run_uo --kernel-clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"no matching packages are registered with dpkg"* ]]
    # proof that nothing was executed: the fake /boot is untouched
    [ -f "$BOOT_DIR/vmlinuz-6.2.0-39-generic" ]
    [ -f "$BOOT_DIR/vmlinuz-6.5.0-17-generic" ]
}

@test "cli: --kernel-list on an empty boot directory degrades to a hint" {
    rm "$BOOT_DIR"/vmlinuz-*
    run run_uo --kernel-list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No kernels found"* ]]
}
