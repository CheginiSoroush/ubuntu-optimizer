#!/usr/bin/env bats
# ============================================================
#   test/splash.bats — tests for the boot splash repair (lib/splash.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The splash module is exercised at three levels:
#     • Function level — lib/common.sh + lib/splash.sh sourced into the
#       test shell with sandboxed paths (UO_SPLASH_GRUB_FILE /
#       UO_SPLASH_CMDLINE_FILE) and a sudo passthrough stub, so the real
#       mutation code runs against temp files without root.
#     • CLI level — the real entry script with --splash / --fix-splash
#       --dry-run, backed by stubbed update-grub / apt-get / dpkg on PATH
#       and the documented UO_SPLASH_FAKE_GRUB=1 hook.
#     • Degradation — container/WSL paths (no /boot/grub, no apt).
#   Everything runs fully offline; nothing touches the real /etc/default/grub.
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

    # Stub binaries — deterministic package manager + grub answers
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/update-grub" << 'EOF'
#!/usr/bin/env bash
printf 'Sourcing file `/etc/default/grub'"'"'\n'
printf 'Generating grub configuration file ...\n'
printf 'Found linux image: /boot/vmlinuz-7.0.0-38-generic\n'
printf 'done\n'
exit 0
EOF
    cat > "$STUB_BIN/apt-get" << 'EOF'
#!/usr/bin/env bash
# simulate the --force-confmiss conffile restore when the conf file is missing
if [ "${FORCE_CONFMISS_STUB:-0}" = "1" ] && [ -n "${CONFMISS_TARGET:-}" ]; then
    mkdir -p "$(dirname "$CONFMISS_TARGET")"
    printf 'GRUB_DEFAULT=0\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$CONFMISS_TARGET"
fi
printf 'Setting up grub-common ...\n'
exit 0
EOF
    cat > "$STUB_BIN/dpkg" << 'EOF'
#!/usr/bin/env bash
# grub-common is the installed owner package; grub2-common is not
case "${2:-}" in
    grub2-common) exit 1 ;;
    grub-common)  printf 'ii  grub-common  2.14  amd64\n'; exit 0 ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/update-grub" "$STUB_BIN/apt-get" "$STUB_BIN/dpkg"

    # sandboxed paths + a fake /proc/cmdline for every test
    export UO_SPLASH_GRUB_FILE="$TEST_HOME/etc/default/grub"
    export UO_SPLASH_CMDLINE_FILE="$TEST_HOME/proc-cmdline"
    printf 'BOOT_IMAGE=/boot/vmlinuz ro quiet splash root=UUID=x\n' > "$UO_SPLASH_CMDLINE_FILE"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a splash test needs, into the test shell
load_splash() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/splash.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
    # root-less sudo stub: the ticket checks (-n -v / -n true) answer
    # "authenticated", every real command runs as the test user — the
    # sandboxed SPLASH_GRUB_FILE lives inside TEST_HOME (user-writable)
    sudo() {
        case "$1" in
            -n) return 0 ;;
        esac
        "$@"
    }
}

# ---------- function level: the config-file parser ----------

@test "_splash_params_state accepts a healthy config" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    run _splash_params_state
    [ "$status" -eq 0 ]
}

@test "_splash_params_state rejects a config without the parameters" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT=""\n' > "$UO_SPLASH_GRUB_FILE"
    run _splash_params_state
    [ "$status" -ne 0 ]
}

@test "_splash_params_state rejects a missing config file" {
    load_splash
    rm -f "$UO_SPLASH_GRUB_FILE"
    run _splash_params_state
    [ "$status" -ne 0 ]
}

@test "_splash_params_state ignores commented-out parameter lines" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf '# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    run _splash_params_state
    [ "$status" -ne 0 ]
}

@test "_splash_params_state takes the last assignment (grub-mkconfig rule)" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT=""\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    run _splash_params_state
    [ "$status" -eq 0 ]
}

@test "_splash_live_state reads the kernel command line" {
    load_splash
    run _splash_live_state
    [ "$status" -eq 0 ]
    printf 'BOOT_IMAGE=/boot/vmlinuz ro crashkernel=2G-4G:320M root=UUID=x\n' > "$UO_SPLASH_CMDLINE_FILE"
    run _splash_live_state
    [ "$status" -ne 0 ]
}

@test "_splash_owner_pkg picks the installed grub package" {
    load_splash
    PATH="$STUB_BIN:$PATH" run _splash_owner_pkg
    [ "$status" -eq 0 ]
    [ "$output" = "grub-common" ]
}

# ---------- function level: the read-only status ----------

@test "splash_show degrades gracefully outside a grub system" {
    load_splash
    # UO_SPLASH_NO_GRUB forces the "no grub" verdict — deterministic even on
    # hosts that do ship /boot/grub (GitHub runners do)
    UO_SPLASH_NO_GRUB=1 run splash_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"splash check skipped"* ]]
}

@test "splash_show flags the missing config as the known cause" {
    load_splash
    rm -f "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 run splash_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING"* ]]
    [[ "$output" == *"known cause"* ]]
    [[ "$output" == *"--fix-splash"* ]]
}

@test "splash_show reports a healthy system end to end" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 run splash_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"quiet + splash"* ]]
    [[ "$output" == *"everything is healthy"* ]]
}

# ---------- function level: the real repair (root-less sudo passthrough) ----------

@test "splash_fix restores a missing config through the package route" {
    load_splash
    rm -f "$UO_SPLASH_GRUB_FILE"
    FORCE_CONFMISS_STUB=1 CONFMISS_TARGET="$UO_SPLASH_GRUB_FILE" \
        UO_SPLASH_FAKE_GRUB=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" \
        run splash_fix
    [ "$status" -eq 0 ]
    [ -f "$UO_SPLASH_GRUB_FILE" ]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$UO_SPLASH_GRUB_FILE"
    [[ "$output" == *"restored by the package manager"* ]]
    [[ "$output" == *"grub.cfg regenerated"* ]]
    [[ "$output" == *"Done — reboot"* ]]
}

@test "splash_fix falls back to a hand-written config when the package route fails" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    rm -f "$UO_SPLASH_GRUB_FILE"
    # FORCE_CONFMISS_STUB unset — the stub "reinstall" restores nothing
    UO_SPLASH_FAKE_GRUB=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run splash_fix
    [ "$status" -eq 0 ]
    [ -f "$UO_SPLASH_GRUB_FILE" ]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$UO_SPLASH_GRUB_FILE"
    [[ "$output" == *"stock config"* ]]
}

@test "splash_fix repairs missing parameters with a timestamped backup" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT=""\nGRUB_CMDLINE_LINUX="crashkernel=256M"\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run splash_fix
    [ "$status" -eq 0 ]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$UO_SPLASH_GRUB_FILE"
    # GRUB_CMDLINE_LINUX (kdump & co.) must survive untouched
    grep -q 'GRUB_CMDLINE_LINUX="crashkernel=256M"' "$UO_SPLASH_GRUB_FILE"
    # exactly one timestamped backup exists and holds the original content
    local bak
    bak=$(ls "$UO_SPLASH_GRUB_FILE".bak-* 2>/dev/null | wc -l)
    [ "$bak" -eq 1 ]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT=""' "$UO_SPLASH_GRUB_FILE".bak-*
    [[ "$output" == *"Backup saved"* ]]
    [[ "$output" == *"Done — reboot"* ]]
}

@test "splash_fix appends the parameter line when the key is absent" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_DEFAULT=0\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run splash_fix
    [ "$status" -eq 0 ]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$UO_SPLASH_GRUB_FILE"
    grep -q 'GRUB_DEFAULT=0' "$UO_SPLASH_GRUB_FILE"
}

@test "splash_fix is idempotent on a healthy system" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run splash_fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured — nothing to do"* ]]
    [[ "$output" != *"update-grub"* ]] || [[ "$output" != *"Regenerating"* ]]
}

@test "splash_fix honours cancellation (nothing is changed)" {
    load_splash
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT=""\n' > "$UO_SPLASH_GRUB_FILE"
    # ASSUME_YES unset + stdin closed → confirm_action falls back to "no"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run splash_fix < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT=""' "$UO_SPLASH_GRUB_FILE"
}

# ---------- CLI level: --splash and --fix-splash ----------

@test "cli: --splash prints the status and the healthy verdict" {
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run run_uo --splash
    [ "$status" -eq 0 ]
    [[ "$output" == *"Boot Splash Status"* ]]
    [[ "$output" == *"everything is healthy"* ]]
}

@test "cli: --splash on a broken config points at --fix-splash" {
    rm -f "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run run_uo --splash
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING"* ]]
    [[ "$output" == *"--fix-splash"* ]]
}

@test "cli: --fix-splash --dry-run prints the plan and changes nothing" {
    rm -f "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run run_uo --fix-splash --dry-run -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"--force-confmiss"* ]]
    [[ "$output" == *"The repair is planned"* ]]
    [ ! -f "$UO_SPLASH_GRUB_FILE" ]
}

@test "cli: --fix-splash --dry-run plans the sed repair for missing parameters" {
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT=""\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run run_uo --fix-splash --dry-run -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] sudo sed"* ]]
    [[ "$output" == *"Backup saved"* ]]
    [[ "$output" == *"The repair is planned"* ]]
    # dry-run must leave the original content alone
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT=""' "$UO_SPLASH_GRUB_FILE"
}

@test "cli: --fix-splash is a queued action (composable with other flags)" {
    mkdir -p "$(dirname "$UO_SPLASH_GRUB_FILE")"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$UO_SPLASH_GRUB_FILE"
    UO_SPLASH_FAKE_GRUB=1 PATH="$STUB_BIN:$PATH" run run_uo --splash --fix-splash -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Boot Splash Status"* ]]
    [[ "$output" == *"already configured — nothing to do"* ]]
}

@test "cli: --splash degrades outside a grub system (container/WSL)" {
    # UO_SPLASH_NO_GRUB forces the "no grub" verdict — deterministic even on
    # hosts that do ship /boot/grub (GitHub runners do)
    UO_SPLASH_NO_GRUB=1 run run_uo --splash
    [ "$status" -eq 0 ]
    [[ "$output" == *"splash check skipped"* ]]
}
