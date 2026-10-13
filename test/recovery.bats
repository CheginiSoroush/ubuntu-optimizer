#!/usr/bin/env bats
# ============================================================
#   test/recovery.bats — tests for the rescue tools (lib/recovery.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Every function here is destructive by design (apt/dpkg
#   repair, desktop reinstall, the VEET installer), so the
#   module is exercised at function level in a sandbox HOME
#   with `sudo` overridden as a logging stub that never
#   executes (configurable per-command failures) and a fake
#   git/go toolchain plus a real make for the VEET flow.
#
#   Known hermetic limit (documented in the worklog): the final
#   verification of install_veet checks the real /usr/local/bin/veet,
#   so only its failure path is asserted — never the root install.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # CI runners export XDG_* — force HOME-based paths so tests stay hermetic
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

    SUDO_LOG="$TEST_HOME/sudo-calls.log"
    : > "$SUDO_LOG"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/recovery.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"

    # sudo stub: logs every call, never executes; a first word listed in
    # UO_SUDO_FAIL returns 1 instead
    sudo() {
        printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
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

# ---------- fix_broken / fix_dpkg_configure ----------

@test "fix_broken runs both repair steps and reports success" {
    run fix_broken
    [ "$status" -eq 0 ]
    grep -q "sudo apt --fix-broken install -y" "$SUDO_LOG"
    grep -q "sudo dpkg --configure -a" "$SUDO_LOG"
    [[ "$output" == *"Repair completed."* ]]
}

@test "fix_broken stays honest when dpkg fails" {
    UO_SUDO_FAIL="dpkg" run fix_broken
    [ "$status" -eq 1 ]
    # dpkg was still attempted after the apt step
    grep -q "sudo dpkg --configure -a" "$SUDO_LOG"
    [[ "$output" == *"Repair incomplete."* ]]
}

@test "fix_dpkg_configure reports success and failure" {
    run fix_dpkg_configure
    [ "$status" -eq 0 ]
    grep -q "sudo dpkg --configure -a" "$SUDO_LOG"
    [[ "$output" == *"Package configuration completed."* ]]
    UO_SUDO_FAIL="dpkg" run fix_dpkg_configure
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to configure packages."* ]]
}

# ---------- reinstall_desktop ----------

@test "reinstall_desktop declined installs nothing" {
    run reinstall_desktop < <(printf 'n')
    [ "$status" -eq 0 ]
    ! grep -q "apt install" "$SUDO_LOG"
    [[ "$output" == *"Cancelled."* ]]
}

@test "reinstall_desktop reinstalls the full GNOME stack when confirmed" {
    ASSUME_YES=1 run reinstall_desktop
    [ "$status" -eq 0 ]
    # every package of the GNOME stack is part of the single reinstall call
    local reinstall_line pkg
    reinstall_line=$(grep -- "--reinstall" "$SUDO_LOG")
    [[ "$reinstall_line" == *"sudo apt install --reinstall -y"* ]]
    for pkg in ubuntu-desktop ubuntu-desktop-minimal gnome-shell gdm3 nautilus gnome-terminal; do
        [[ "$reinstall_line" == *"$pkg"* ]]
    done
    [[ "$output" == *"Desktop environment reinstalled."* ]]
    [[ "$output" == *"Please reboot the system."* ]]
}

# ---------- install_veet ----------

@test "install_veet declined does nothing dangerous" {
    run install_veet < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled."* ]]
    [ ! -e "$TEST_HOME/veet" ]
}

@test "install_veet installs missing golang, clones and builds; verification fails without a real root install" {
    # no `go` on the host PATH — the golang install branch is exercised for real
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/git" << 'EOF'
#!/usr/bin/env bash
# git clone stub: materialize a fake veet checkout with a working Makefile
for a in "$@"; do
    if [ "$a" = "clone" ]; then
        mkdir -p "$HOME/veet/.git"
        printf 'build:\n\ttouch veet\n\tchmod +x veet\ninstall:\n\t@true\n' > "$HOME/veet/Makefile"
        exit 0
    fi
done
exit 0
EOF
    chmod +x "$STUB_BIN/git"
    # Host-independent: GitHub runners ship a Go toolchain, so a plain
    # PATH-prefix would let `command -v go` succeed and skip the golang
    # install branch. Copy the tools the flow needs into a go-less dir
    # (copy-based, per the suite convention) and use it as the ONLY PATH.
    GOLESS_BIN="$TEST_HOME/goless-bin"
    mkdir -p "$GOLESS_BIN"
    for tool in make bash sh env mkdir touch chmod cp rm mv cat grep sed awk                 uname dirname basename readlink sleep printf ls date; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$GOLESS_BIN/$tool"
    done
    # git comes from STUB_BIN (first), make is real, go is ABSENT everywhere
    PATH="$STUB_BIN:$GOLESS_BIN" ASSUME_YES=1 run install_veet
    [ "$status" -eq 1 ]
    grep -q "sudo apt install -y golang" "$SUDO_LOG"
    [ -x "$TEST_HOME/veet/veet" ]
    # the make-based install went through the sudo stub (never executed),
    # so the /usr/local/bin verification fails honestly
    [[ "$output" == *"The VEET binary was not built/installed."* ]]
}

@test "install_veet reports a broken build and stops" {
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/git" << 'EOF'
#!/usr/bin/env bash
for a in "$@"; do
    if [ "$a" = "clone" ]; then
        mkdir -p "$HOME/veet/.git"
        printf 'build:\n\t@exit 1\ninstall:\n\t@true\n' > "$HOME/veet/Makefile"
        exit 0
    fi
done
exit 0
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/go"
    chmod +x "$STUB_BIN/git" "$STUB_BIN/go"
    PATH="$STUB_BIN:$PATH" ASSUME_YES=1 run install_veet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to build VEET."* ]]
    [ ! -x /usr/local/bin/veet ]
}
