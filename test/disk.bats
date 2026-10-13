#!/usr/bin/env bats
# ============================================================
#   test/disk.bats — tests for the disk analyzer & cleanup
#   (lib/disk.sh)
#
#   Function level: lib/common.sh + lib/disk.sh sourced into
#   the test shell with a temp HOME; df/du/uname/dpkg-query are
#   PATH stubs (cat-written, never symlinks) so every value is
#   deterministic and offline. The cleanup flow runs EXCLUSIVELY
#   through the documented DRY_RUN=1 sudo wrapper (commands are
#   printed and logged, nothing executed) or the decline path —
#   nothing destructive can ever happen in this suite.
#   CLI level runs the real entry script with --disk.
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

load_disk() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/disk.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

write_df_stub() {
    cat > "$STUB_BIN/df" << 'EOF'
#!/usr/bin/env bash
# Deterministic df stub.
#   --output=avail mode: UO_DF_SEQ="kb1 kb2..." + UO_DF_SEQ_IDX (per-call
#   sequence), or UO_DF_FAIL=1 (failure), or UO_DF_AVAIL_KB (fixed value).
#   human mode (df -h /): fixed 20G/12G/8.0G/60% table.
mode_avail=0
for a in "$@"; do
    [ "$a" = "--output=avail" ] && mode_avail=1
done
if [ "$mode_avail" = "1" ]; then
    if [ -n "$UO_DF_FAIL" ]; then
        printf 'df: /: No such file or directory\n' >&2
        exit 1
    fi
    if [ -n "$UO_DF_SEQ" ]; then
        n=$(cat "$UO_DF_SEQ_IDX" 2>/dev/null || echo 0)
        # shellcheck disable=SC2206  # intentional word split of the sequence
        vals=($UO_DF_SEQ)
        printf '%s\n' "${vals[$n]:-${vals[-1]}}"
        echo $((n + 1)) > "$UO_DF_SEQ_IDX"
        exit 0
    fi
    printf 'Avail\n%s\n' "${UO_DF_AVAIL_KB:-4194304}"
    exit 0
fi
printf 'Filesystem      Size  Used Avail Use%% Mounted on\n'
printf '/dev/sda1        20G   12G  8.0G  60%% /\n'
EOF
    chmod +x "$STUB_BIN/df"
}

write_du_stub() {
    cat > "$STUB_BIN/du" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *"/var/cache/apt/archives"*) printf '512M\t/var/cache/apt/archives\n' ;;
    *"/var/lib/snapd"*)          printf '1.2G\t/var/lib/snapd\n' ;;
    *"/.local"*)                 printf '50M\t%s\n' "${@: -1}" ;;
    *"/var/log"*)                printf '88M\t/var/log\n' ;;
    *"/var/crash"*)              printf '4K\t/var/crash\n' ;;
    *"/opt"*)                    printf '300M\t/opt\n' ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/du"
}

write_uname_stub() {
    cat > "$STUB_BIN/uname" << 'EOF'
#!/usr/bin/env bash
printf '%s' "${UO_UNAME_R:-5.15.0-91-generic}"
EOF
    chmod +x "$STUB_BIN/uname"
}

write_dpkg_query_stub() {
    cat > "$STUB_BIN/dpkg-query" << 'EOF'
#!/usr/bin/env bash
# Modes: kernel abbrev list (UO_KERNEL_ABBREV_FILE), installed-size list
# (UO_DEB_SIZE_FILE), per-package Status (UO_INSTALLED_PKGS word list).
mode="status"
for a in "$@"; do
    case "$a" in
        *db:Status-Abbrev*) mode="abbrev" ;;
        *Installed-Size*)   mode="size" ;;
    esac
done
case "$mode" in
    abbrev) [ -n "${UO_KERNEL_ABBREV_FILE:-}" ] && cat "$UO_KERNEL_ABBREV_FILE"; exit 0 ;;
    size)   [ -n "${UO_DEB_SIZE_FILE:-}" ] && cat "$UO_DEB_SIZE_FILE"; exit 0 ;;
    status)
        name="${*: -1}"
        case " ${UO_INSTALLED_PKGS:-} " in
            *" $name "*) printf 'install ok installed'; exit 0 ;;
        esac
        printf "dpkg-query: no packages found matching %s\n" "$name" >&2
        exit 1 ;;
esac
EOF
    chmod +x "$STUB_BIN/dpkg-query"
}

write_sudo_stub() {
    cat > "$STUB_BIN/sudo" << 'EOF'
#!/usr/bin/env bash
# Pass-through sudo stub — the sourced sudo() function routes here via
# `command sudo`, so the wrapped command runs against the PATH stubs.
exec "$@"
EOF
    chmod +x "$STUB_BIN/sudo"
}

write_kernel_fixtures() {
    UO_KERNEL_ABBREV_FILE="$TEST_HOME/abbrev.txt"
    printf 'ii  linux-image-5.15.0-88-generic\n' >  "$UO_KERNEL_ABBREV_FILE"
    printf 'ii  linux-image-5.15.0-90-generic\n' >> "$UO_KERNEL_ABBREV_FILE"
    printf 'ii  linux-image-5.15.0-91-generic\n' >> "$UO_KERNEL_ABBREV_FILE"
    printf 'ii  linux-image-5.15.0-92-generic\n' >> "$UO_KERNEL_ABBREV_FILE"
    export UO_KERNEL_ABBREV_FILE
}

# ---------- function level: pure helpers ----------

@test "_disk_avail_mb converts 1K blocks to whole MB" {
    load_disk
    write_df_stub
    UO_DF_AVAIL_KB=4194304 PATH="$STUB_BIN:$PATH" run _disk_avail_mb /
    [ "$status" -eq 0 ]
    [ "$output" = "4096" ]
    UO_DF_AVAIL_KB=1023 PATH="$STUB_BIN:$PATH" run _disk_avail_mb /
    [ "$output" = "0" ]
    UO_DF_AVAIL_KB=0 PATH="$STUB_BIN:$PATH" run _disk_avail_mb /
    [ "$output" = "0" ]
}

@test "_disk_avail_mb fails cleanly when df fails or prints garbage" {
    load_disk
    write_df_stub
    UO_DF_FAIL=1 PATH="$STUB_BIN:$PATH" run _disk_avail_mb /
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
    UO_DF_AVAIL_KB="12 MB" PATH="$STUB_BIN:$PATH" run _disk_avail_mb /   # suffixed value is not numeric
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "_old_kernel_pkgs keeps the running and newest kernel and lists the rest" {
    load_disk
    write_uname_stub
    write_dpkg_query_stub
    write_kernel_fixtures
    UO_UNAME_R=5.15.0-91-generic PATH="$STUB_BIN:$PATH" run _old_kernel_pkgs
    [ "$status" -eq 0 ]
    [ "$(grep -c . <<< "$output")" -eq 2 ]
    [[ "$output" == *"linux-image-5.15.0-88-generic"* ]]
    [[ "$output" == *"linux-image-5.15.0-90-generic"* ]]
    [[ "$output" != *"linux-image-5.15.0-91-generic"* ]]   # running kernel
    [[ "$output" != *"linux-image-5.15.0-92-generic"* ]]   # newest kernel
    # No installed kernel packages at all → empty output, still success
    UO_KERNEL_ABBREV_FILE=/dev/null PATH="$STUB_BIN:$PATH" run _old_kernel_pkgs
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ---------- function level: disk_check_install ----------

@test "disk_check_install passes, blocks and skips depending on free space" {
    load_disk
    write_df_stub
    UO_DF_AVAIL_KB=4194304 PATH="$STUB_BIN:$PATH" run disk_check_install 500   # 4096 MB free ≥ 500
    [ "$status" -eq 0 ]
    UO_DF_AVAIL_KB=4194304 PATH="$STUB_BIN:$PATH" run disk_check_install 8192  # 4096 MB < 8192 MB
    [ "$status" -eq 1 ]
    [[ "$output" == *"Insufficient disk space: 4096MB free (need 8192MB)"* ]]
    [[ "$output" == *"--disk-clean"* ]]
    UO_DF_FAIL=1 PATH="$STUB_BIN:$PATH" run disk_check_install 500             # undeterminable → fail open
    [ "$status" -eq 0 ]
    [[ "$output" == *"check skipped"* ]]
}

# ---------- function level: disk_analyze (read-only) ----------

@test "disk_analyze prints the usage line, categories, kernels and largest packages" {
    load_disk
    write_df_stub
    write_du_stub
    write_uname_stub
    write_dpkg_query_stub
    write_sudo_stub
    write_kernel_fixtures
    UO_DEB_SIZE_FILE="$TEST_HOME/debsizes.txt"
    printf '2048\tmybigpkg\n1024\tlilpkg\n' > "$UO_DEB_SIZE_FILE"
    export UO_DEB_SIZE_FILE
    PATH="$STUB_BIN:$PATH" UO_DF_AVAIL_KB=4194304 run disk_analyze
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk Space Analysis"* ]]
    [[ "$output" == *"Total: 20G"*"Used: 12G (60%)"*"Free: 8.0G"* ]]
    [[ "$output" == *"apt cache:"*"512M"* ]]
    [[ "$output" == *"snap:"*"1.2G"* ]]
    [[ "$output" == *"/var/log:"*"88M"* ]]
    [[ "$output" == *"Old kernels:"*"2 (removable)"* ]]
    [[ "$output" == *"Largest deb packages"* ]]
    [[ "$output" == *"mybigpkg"*"2 MB"* ]]
}

@test "disk_analyze warns below 2 GB free and points at --disk-clean" {
    load_disk
    write_df_stub
    write_du_stub
    write_uname_stub
    write_dpkg_query_stub
    write_sudo_stub
    write_kernel_fixtures
    PATH="$STUB_BIN:$PATH" UO_DF_AVAIL_KB=1024000 run disk_analyze   # 1000 MB
    [ "$status" -eq 0 ]
    [[ "$output" == *"Low disk space! (1000 MB free)"* ]]
    [[ "$output" == *"uo --disk-clean"* ]]
}

# ---------- function level: disk_cleanup (safe paths only) ----------

@test "disk_cleanup declines without confirmation and runs nothing" {
    load_disk
    # Recorder stub: any sudo call past the confirmation would land here
    cat > "$STUB_BIN/sudo" << 'EOF'
#!/usr/bin/env bash
printf 'SUDO VIOLATION: %s\n' "$*" >> "${UO_SUDO_LOG:?}"
exit 0
EOF
    chmod +x "$STUB_BIN/sudo"
    decline_cleanup() { disk_cleanup < /dev/null; }
    UO_SUDO_LOG="$TEST_HOME/violations.log" PATH="$STUB_BIN:$PATH" run decline_cleanup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk Cleanup"* ]]
    [[ "$output" == *"Cancelled."* ]]
    [ ! -e "$TEST_HOME/violations.log" ]   # not a single privileged command ran
}

@test "disk_cleanup with DRY_RUN=1 plans the full flow and reports freed space" {
    load_disk
    write_df_stub
    write_uname_stub
    write_dpkg_query_stub
    write_kernel_fixtures
    cat > "$STUB_BIN/journalctl" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/journalctl"
    cat > "$STUB_BIN/snap" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    list)
        printf 'Name       Version    Rev  Tracking  Publisher  Notes\n'
        printf 'core22     20231123   900  latest    canonical  disabled\n'
        printf 'firefox    120.0      100  latest    mozilla    -\n'
        ;;
    remove) exit 0 ;;
esac
EOF
    chmod +x "$STUB_BIN/snap"
    UO_DF_SEQ="1024000 1050624" UO_DF_SEQ_IDX="$TEST_HOME/df-idx" \
        UO_INSTALLED_PKGS="linux-modules-5.15.0-88-generic" \
        DRY_RUN=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run disk_cleanup
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt cache cleaned."* ]]
    [[ "$output" == *"Old kernels removed: linux-image-5.15.0-88-generic linux-image-5.15.0-90-generic"* ]]
    [[ "$output" == *"journald vacuumed."* ]]
    [[ "$output" == *"Old snap revisions removed."* ]]
    [[ "$output" == *"Autoremove completed."* ]]
    [[ "$output" == *"Approximately 26MB freed."* ]]   # 1000 MB → 1026 MB (1050624 KB)
    # Every privileged command only ever went through the dry-run wrapper
    grep -q '\[dry-run\] sudo apt purge -y' "$LOG_FILE"
    grep -q '\[dry-run\] sudo snap remove core22 --revision=900' "$LOG_FILE"
}

# ---------- CLI level ----------

@test "cli: --disk prints the full read-only analysis end-to-end" {
    write_df_stub
    write_du_stub
    write_uname_stub
    write_dpkg_query_stub
    write_sudo_stub
    write_kernel_fixtures
    UO_DEB_SIZE_FILE="$TEST_HOME/debsizes.txt"
    printf '2048\tmybigpkg\n' > "$UO_DEB_SIZE_FILE"
    export UO_DEB_SIZE_FILE UO_DF_AVAIL_KB=4194304
    PATH="$STUB_BIN:$PATH" run run_uo --disk
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk Space Analysis"* ]]
    [[ "$output" == *"Total: 20G"* ]]
    [[ "$output" == *"apt cache:"*"512M"* ]]
    [[ "$output" == *"Old kernels:"*"2 (removable)"* ]]
    [[ "$output" == *"Largest deb packages"* ]]
}
