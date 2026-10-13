#!/usr/bin/env bats
# ============================================================
#   test/system.bats — tests for the system/security/time
#   optimizations (lib/system.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Function level: lib/common.sh + lib/system.sh sourced into
#   the test shell with a sandbox HOME. `sudo` is overridden as
#   a logging stub that never executes (configurable failures),
#   and sysctl/systemctl/timedatectl/dpkg-query/sed are PATH
#   stubs, so no test ever touches /etc. The dry-run CLI flows
#   run the real entry script — the dry-run sudo wrapper itself
#   guarantees nothing is executed there.
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

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"

    SUDO_LOG="$TEST_HOME/sudo-calls.log"
    : > "$SUDO_LOG"

    # sysctl -n KEY — canned applied values (env-tunable)
    cat > "$STUB_BIN/sysctl" << 'EOF'
#!/usr/bin/env bash
[ "$1" = "-n" ] || exit 0
case "$2" in
    vm.swappiness)       echo "${UO_FAKE_SWAPPINESS:-10}" ;;
    vm.vfs_cache_pressure) echo "${UO_FAKE_VCP:-50}" ;;
    *) exit 0 ;;
esac
EOF

    # systemctl — canned unit-file list and active units (env-tunable)
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    list-unit-files)
        for u in ${UO_FAKE_UNITS:-}; do printf '%s.service static -\n' "$u"; done
        exit 0 ;;
    is-active)
        shift
        for a in "$@"; do
            case "$a" in --*) continue ;; esac
            for u in ${UO_FAKE_ACTIVE:-}; do
                [ "$a" = "$u" ] && exit 0
            done
        done
        exit 3 ;;
    *) exit 0 ;;
esac
EOF

    # timedatectl — NTPSynchronized answer (env-tunable)
    cat > "$STUB_BIN/timedatectl" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    show)
        for a in "$@"; do
            if [ "$a" = "NTPSynchronized" ]; then
                echo "${UO_FAKE_NTP_SYNC:-yes}"
                exit 0
            fi
        done
        exit 0 ;;
    status)
        printf '               Local time: Sat 2025-01-01 00:00:00 UTC\n'
        printf '       System clock synchronized: yes\n' ;;
    *) exit 0 ;;
esac
EOF

    # dpkg-query — pkg_installed answers from UO_FAKE_INSTALLED
    cat > "$STUB_BIN/dpkg-query" << 'EOF'
#!/usr/bin/env bash
# dpkg-query -W -f='${Status}' PKG
for p in ${UO_FAKE_INSTALLED:-}; do
    if [ "$3" = "$p" ]; then
        printf 'install ok installed\n'
        exit 0
    fi
done
exit 1
EOF

    # sed — the fstab stub for set_noatime: the root line never has
    # noatime and the in-place edit never sticks (hermetic failure branch)
    cat > "$STUB_BIN/sed" << 'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    case "$a" in
        -n) printf '/dev/sda1 / ext4 defaults 0 1\n'; exit 0 ;;
        -i) exit 0 ;;
    esac
done
exit 0
EOF
    chmod +x "$STUB_BIN/sysctl" "$STUB_BIN/systemctl" "$STUB_BIN/timedatectl" \
             "$STUB_BIN/dpkg-query" "$STUB_BIN/sed"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/system.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"

    # sudo stub: log everything, execute nothing
    sudo() {
        printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
        case "$1" in
            # `sudo test -f $SUDOERS_TIMEOUT_FILE` must report "not configured yet"
            test) return 1 ;;
            visudo) return "${VISUDO_RC:-0}" ;;
        esac
        local a
        for a in ${UO_SUDO_FAIL:-}; do
            [ "$1" = "$a" ] && return 1
        done
        return 0
    }
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# ---------- system & memory ----------

@test "optimize_memory previews in dry-run and verifies the applied values" {
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run optimize_memory
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] memory values would be set"* ]]

    # the sysctl stub answers 10 / 50 → verification succeeds
    PATH="$STUB_BIN:$PATH" run optimize_memory
    [ "$status" -eq 0 ]
    [[ "$output" == *"Memory values set: swappiness=10 | vfs_cache_pressure=50"* ]]

    # a stubborn kernel value → honest failure
    UO_FAKE_SWAPPINESS=60 PATH="$STUB_BIN:$PATH" run optimize_memory
    [ "$status" -eq 1 ]
    [[ "$output" == *"Values could not be verified"* ]]
}

@test "set_noatime previews safely in dry-run and fails loudly when the edit does not stick" {
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run set_noatime
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] noatime would be added to the root entry"* ]]

    # the sed stub never applies the edit → the verification fails honestly;
    # nothing outside the sudo stub was touched
    PATH="$STUB_BIN:$PATH" run set_noatime
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to edit /etc/fstab."* ]]
    grep -q "sudo cp /etc/fstab /etc/fstab.bak" "$SUDO_LOG"
    grep -q "noatime" <(grep "sudo sed" "$SUDO_LOG")
}

@test "disable_extra_services disables only the units that exist" {
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run disable_extra_services
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] these services would be disabled"* ]]

    UO_FAKE_UNITS="cups-browsed whoopsie" PATH="$STUB_BIN:$PATH" run disable_extra_services
    [ "$status" -eq 0 ]
    grep -q "sudo systemctl disable --now cups-browsed" "$SUDO_LOG"
    grep -q "sudo systemctl disable --now whoopsie" "$SUDO_LOG"
    [[ "$output" == *"avahi-daemon does not exist on this system."* ]]
    [[ "$output" == *"2 services disabled in total."* ]]
}

@test "install_tlp removes the conflicting daemon only after confirmation" {
    UO_FAKE_INSTALLED="power-profiles-daemon" ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run install_tlp
    [ "$status" -eq 0 ]
    grep -q "sudo apt remove -y power-profiles-daemon" "$SUDO_LOG"
    grep -q "sudo apt install -y tlp tlp-rdw" "$SUDO_LOG"
    grep -q "sudo systemctl enable tlp" "$SUDO_LOG"
    [[ "$output" == *"tlp installed and enabled."* ]]

    # declining the conflict question cancels the whole install
    UO_FAKE_INSTALLED="power-profiles-daemon" PATH="$STUB_BIN:$PATH" run install_tlp < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled — tlp was not installed."* ]]
    [ "$(grep -c "apt install -y tlp tlp-rdw" "$SUDO_LOG")" -eq 1 ]
}

@test "limit_journal writes the cap and reports exactly which step failed" {
    PATH="$STUB_BIN:$PATH" run limit_journal
    [ "$status" -eq 0 ]
    grep -q "sudo mkdir -p /etc/systemd/journald.conf.d" "$SUDO_LOG"
    grep -q "sudo tee /etc/systemd/journald.conf.d/99-optimizer.conf" "$SUDO_LOG"
    grep -q "sudo systemctl restart systemd-journald" "$SUDO_LOG"
    [[ "$output" == *"Journal size limited to 100M."* ]]

    UO_SUDO_FAIL="mkdir" PATH="$STUB_BIN:$PATH" run limit_journal
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to create journald.conf.d."* ]]
}

@test "extend_sudo_timeout writes the drop-in and rolls it back when visudo rejects it" {
    PATH="$STUB_BIN:$PATH" run extend_sudo_timeout
    [ "$status" -eq 0 ]
    grep -q "sudo tee /etc/sudoers.d/99-optimizer-timeout" "$SUDO_LOG"
    grep -q "sudo chmod 440 /etc/sudoers.d/99-optimizer-timeout" "$SUDO_LOG"
    [[ "$output" == *"sudo password timeout extended to 120 minutes."* ]]

    VISUDO_RC=1 PATH="$STUB_BIN:$PATH" run extend_sudo_timeout
    [ "$status" -eq 1 ]
    [[ "$output" == *"The file was invalid and has been removed. sudoers is untouched."* ]]
    grep -q "sudo rm -f /etc/sudoers.d/99-optimizer-timeout" "$SUDO_LOG"
}

@test "setup_polkit_rule can be declined, confirmed and reports restart failures" {
    PATH="$STUB_BIN:$PATH" run setup_polkit_rule < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled."* ]]
    ! grep -q "polkit-1" "$SUDO_LOG"

    ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run setup_polkit_rule
    [ "$status" -eq 0 ]
    grep -q "sudo tee /etc/polkit-1/rules.d/10-disable-password-timeout.rules" "$SUDO_LOG"
    [[ "$output" == *"polkit rule created and polkit restarted."* ]]

    UO_SUDO_FAIL="systemctl" ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run setup_polkit_rule
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to restart polkit."* ]]
}

@test "fix_time syncs via chrony and degrades gracefully when NTP never syncs" {
    UO_FAKE_INSTALLED="chrony" UO_FAKE_ACTIVE="chrony" PATH="$STUB_BIN:$PATH" run fix_time
    [ "$status" -eq 0 ]
    grep -q "sudo chronyc makestep" "$SUDO_LOG"
    grep -q "sudo hwclock --systohc" "$SUDO_LOG"
    [[ "$output" == *"System time synchronized."* ]]

    # minimal PATH: chrony absent, systemctl absent → both sync methods
    # are skipped, the warning is shown and the run still succeeds
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool src
    for tool in bash env date sed awk grep cat mkdir rm cp ls head tail wc sort tr uname; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" run fix_time
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTP sync could not be completed right now."* ]]
    [[ "$output" == *"chrony keeps retrying in the background."* ]]
}

@test "show_time_status renders the timedatectl view and the chrony block when active" {
    UO_FAKE_ACTIVE="chrony" PATH="$STUB_BIN:$PATH" run show_time_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"System Time Status"* ]]
    [[ "$output" == *"System clock synchronized: yes"* ]]

    PATH="$STUB_BIN:$PATH" run show_time_status
    [ "$status" -eq 0 ]
    [[ "$output" != *"chrony status:"* ]]
}

# ---------- CLI dry-run integration ----------

@test "cli: --system/--security/--time dry-run previews everything and changes nothing" {
    run run_uo --system --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN: commands are printed, nothing is executed"* ]]
    [[ "$output" == *"[dry-run] memory values would be set"* ]]
    [[ "$output" == *"[dry-run] these services would be disabled"* ]]
    [[ "$output" == *"[dry-run] journal size would be limited to 100M."* ]]
    [[ "$output" == *"noatime"* ]]
    [[ "$output" == *"Finished — all requested tasks completed."* ]]

    run run_uo --security --dry-run -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] sudo password timeout would be extended to 120 minutes."* ]]
    [[ "$output" == *"[dry-run] the polkit rule would be created (local active sessions only)."* ]]

    run run_uo --time --dry-run -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] chrony would be enabled and the time synchronized."* ]]
}
