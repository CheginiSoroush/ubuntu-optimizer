#!/usr/bin/env bats
# ============================================================
#   test/snapflatpak.bats — tests for lib/snapflatpak.sh
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Function level: common/cache/targz/github/snapflatpak are
#   sourced into the test shell with a sandbox HOME (registry +
#   GitHub db + TTL cache all land inside it). `sudo` is
#   overridden to execute the command directly so the snap /
#   flatpak / apt PATH stubs receive the real calls; the stubs
#   log every invocation into per-tool log files.
#   (--snap-clean CLI degradation is covered at CLI level below;
#   update_apt caching is covered by test/cache.bats.)
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

    export SNAP_LOG="$TEST_HOME/snap-calls.log"
    : > "$SNAP_LOG"
    cat > "$STUB_BIN/snap" << 'EOF'
#!/usr/bin/env bash
# snap stub: canned list/refresh/install/remove answers
cmd="$1"; shift || true
case "$cmd" in
    list)
        if [ "${1:-}" = "--all" ]; then
            if [ "${UO_FAKE_NO_DISABLED:-0}" = "1" ]; then
                printf 'Name     Version   Rev   Tracking       Publisher   Notes\n'
                printf 'firefox  125.0     4090  latest/stable  mozilla✓    -\n'
            else
                printf 'Name     Version   Rev   Tracking       Publisher   Notes\n'
                printf 'core22   20240408  1380  latest/stable  canonical✓  base,disabled\n'
                printf 'firefox  125.0     4090  latest/stable  mozilla✓    -\n'
                printf 'snapd    2.63      2329  latest/stable  canonical✓  snapd,disabled\n'
            fi
        else
            printf 'Name     Version   Rev   Tracking       Publisher   Notes\n'
            printf 'firefox  125.0     4090  latest/stable  mozilla✓    -\n'
            printf 'spotify  1.2.30    70    latest/stable  spotify✓    -\n'
        fi ;;
    refresh)
        printf '%s\n' "refresh${*:+ $*}" >> "$SNAP_LOG"
        [ "${SNAP_REFRESH_RC:-0}" = "1" ] && exit 1
        exit 0 ;;
    install)
        printf '%s\n' "install $*" >> "$SNAP_LOG"
        [ "${SNAP_INSTALL_RC:-0}" = "1" ] && exit 1
        exit 0 ;;
    remove)
        printf '%s\n' "remove $*" >> "$SNAP_LOG"
        [ "${SNAP_REMOVE_RC:-0}" = "1" ] && exit 1
        exit 0 ;;
    *) exit 0 ;;
esac
EOF

    export FLATPAK_LOG="$TEST_HOME/flatpak-calls.log"
    : > "$FLATPAK_LOG"
    cat > "$STUB_BIN/flatpak" << 'EOF'
#!/usr/bin/env bash
# flatpak stub: canned list/update/install/uninstall answers
cmd="$1"; shift || true
case "$cmd" in
    list)
        if [ "${1:-}" = "--app" ] && [ "${2:-}" = "--columns=application" ]; then
            printf 'org.mozilla.firefox\n'
            printf 'com.spotify.Client\n'
        elif [ "${1:-}" = "--app" ]; then
            printf 'org.mozilla.firefox\tstable\tflathub\n'
        fi ;;
    update)
        printf '%s\n' "update $*" >> "$FLATPAK_LOG"
        [ "${FLATPAK_UPDATE_RC:-0}" = "1" ] && exit 1
        exit 0 ;;
    install|uninstall)
        printf '%s\n' "$cmd $*" >> "$FLATPAK_LOG"
        [ "${FLATPAK_CMD_RC:-0}" = "1" ] && exit 1
        exit 0 ;;
    *) exit 0 ;;
esac
EOF

    export APT_LOG="$TEST_HOME/apt-calls.log"
    : > "$APT_LOG"
    cat > "$STUB_BIN/apt" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "apt $*" >> "$APT_LOG"
exit 0
EOF
    chmod +x "$STUB_BIN/snap" "$STUB_BIN/flatpak" "$STUB_BIN/apt"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/cache.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/targz.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/github.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/snapflatpak.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
    CACHE_DIR="$TEST_HOME/.local/share/ubuntu-optimizer/cache"
    # REGISTRY_DB / GITHUB_DB are readonly consts from common.sh/github.sh
    # and already point into the sandbox HOME — never re-assign them

    # sudo stub: execute the command directly (no root) so the PATH stubs run
    sudo() { "$@"; }
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# Build a copy-based tool dir WITHOUT snap/flatpak — deterministic absence
make_min_bin() {
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool src
    for tool in bash env du cut find rm ls cat date sed awk grep head tail \
                wc sort tr mkdir chmod readlink dirname basename uname ps \
                locale sleep stty tput; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$MIN_BIN/$tool"
    done
}

# ---------- snap ----------

@test "snap_list_apps degrades without snap and lists snaps when present" {
    make_min_bin
    PATH="$MIN_BIN" run snap_list_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"snap is not installed on this system."* ]]

    PATH="$STUB_BIN:$PATH" run snap_list_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"   firefox  125.0"* ]]
}

@test "update_snap refreshes everything and reports failures with the running-app hint" {
    PATH="$STUB_BIN:$PATH" run update_snap
    [ "$status" -eq 0 ]
    grep -q "^refresh$" "$SNAP_LOG"
    [[ "$output" == *"All snaps updated."* ]]

    SNAP_REFRESH_RC=1 PATH="$STUB_BIN:$PATH" run update_snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to update snaps."* ]]
    [[ "$output" == *"If an app is running (e.g. snap-store), close it and try again."* ]]
}

@test "snap_install_app installs a named snap and cancels on EOF or an empty name" {
    PATH="$STUB_BIN:$PATH" run snap_install_app < <(printf 'spotify\n')
    [ "$status" -eq 0 ]
    grep -q "^install spotify$" "$SNAP_LOG"
    [[ "$output" == *"Snap installed."* ]]

    PATH="$STUB_BIN:$PATH" run snap_install_app < /dev/null
    [ "$status" -eq 1 ]

    PATH="$STUB_BIN:$PATH" run snap_install_app < <(printf '\n')
    [ "$status" -eq 1 ]
    [[ "$output" == *"No name entered."* ]]
}

@test "snap_remove_app validates the exact name and purges after confirmation" {
    PATH="$STUB_BIN:$PATH" run snap_remove_app < <(printf 'notinstalled\n')
    [ "$status" -eq 1 ]
    [[ "$output" == *"This snap is not installed."* ]]
    ! grep -q "^remove" "$SNAP_LOG"

    PATH="$STUB_BIN:$PATH" run snap_remove_app < <(printf 'firefox\ny')
    [ "$status" -eq 0 ]
    grep -q "^remove --purge firefox$" "$SNAP_LOG"
    [[ "$output" == *"Removed."* ]]

    PATH="$STUB_BIN:$PATH" run snap_remove_app < <(printf 'firefox\nn')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled."* ]]
    [ "$(grep -c "^remove --purge" "$SNAP_LOG")" -eq 1 ]
}

@test "snap_clean_revisions removes pinned disabled revisions and survives failures" {
    # nothing disabled → nothing to do
    UO_FAKE_NO_DISABLED=1 PATH="$STUB_BIN:$PATH" run snap_clean_revisions
    [ "$status" -eq 0 ]
    [[ "$output" == *"No old snap revisions to remove."* ]]

    # two disabled revisions → each removed pinned to its exact revision
    PATH="$STUB_BIN:$PATH" run snap_clean_revisions < <(printf 'y')
    [ "$status" -eq 0 ]
    grep -q "^remove core22 --revision=1380$" "$SNAP_LOG"
    grep -q "^remove snapd --revision=2329$" "$SNAP_LOG"
    [[ "$output" == *"core22 (revision 1380) removed."* ]]

    # failing removals are warned about but never abort (status stays 0)
    SNAP_REMOVE_RC=1 ASSUME_YES=1 PATH="$STUB_BIN:$PATH" run snap_clean_revisions
    [ "$status" -eq 0 ]
    [[ "$output" == *"Some revisions could not be removed."* ]]
}

# ---------- flatpak ----------

@test "flatpak list, update and unused-runtime cleanup work end to end" {
    PATH="$STUB_BIN:$PATH" run flatpak_list_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"   org.mozilla.firefox"* ]]

    PATH="$STUB_BIN:$PATH" run update_flatpak
    [ "$status" -eq 0 ]
    grep -q "^update -y$" "$FLATPAK_LOG"
    [[ "$output" == *"All flatpaks updated."* ]]

    FLATPAK_UPDATE_RC=1 PATH="$STUB_BIN:$PATH" run update_flatpak
    [ "$status" -eq 1 ]
    [[ "$output" == *"In an SSH session polkit may deny access — run from the desktop."* ]]

    PATH="$STUB_BIN:$PATH" run flatpak_clean_unused
    [ "$status" -eq 0 ]
    grep -q "^uninstall --unused -y$" "$FLATPAK_LOG"
    [[ "$output" == *"Cleanup complete."* ]]
}

@test "flatpak_remove_app validates the app ID and uninstalls with its data" {
    PATH="$STUB_BIN:$PATH" run flatpak_remove_app < <(printf 'com.unknown.App\n')
    [ "$status" -eq 1 ]
    [[ "$output" == *"This flatpak app is not installed."* ]]
    ! grep -q "^uninstall" "$FLATPAK_LOG"

    PATH="$STUB_BIN:$PATH" run flatpak_remove_app < <(printf 'org.mozilla.firefox\ny')
    [ "$status" -eq 0 ]
    grep -q "^uninstall -y --delete-data org.mozilla.firefox$" "$FLATPAK_LOG"
    [[ "$output" == *"Removed."* ]]
}

@test "clean_snap_flatpak_junk runs both cleanup halves" {
    PATH="$STUB_BIN:$PATH" run clean_snap_flatpak_junk < <(printf 'y')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Clean Old Snap Revisions"* ]]
    [[ "$output" == *"Clean Unused Flatpak Runtimes and Packages"* ]]
    grep -q "^uninstall --unused -y$" "$FLATPAK_LOG"
}

# ---------- app updates ----------

@test "update_targz_apps self-heals stale registry entries and reports an empty registry" {
    # no registry at all → informational, no scan
    PATH="$STUB_BIN:$PATH" CLI_MODE=1 ASSUME_YES=1 run update_targz_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"No apps are registered yet."* ]]

    # one entry whose install dir is gone + one healthy entry
    mkdir -p "$TEST_HOME/opt/demo" "$TEST_HOME/Downloads"
    registry_add stale "" "/nonexistent-dir-xyz" exec desktop source
    registry_add demo "1.0" "$TEST_HOME/opt/demo" exec desktop source
    PATH="$STUB_BIN:$PATH" CLI_MODE=1 ASSUME_YES=1 run update_targz_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"'stale': install directory missing"* ]]
    ! grep -q "^stale|" "$REGISTRY_DB"
    grep -q "^demo|" "$REGISTRY_DB"
    [[ "$output" == *"App: demo (version: 1.0)"* ]]
    [[ "$output" == *"No new file for this app in ~/Downloads."* ]]
}

@test "update_all runs every source to completion and reports the summary" {
    PATH="$STUB_BIN:$PATH" run update_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Update Everything"* ]]
    grep -q "^apt update$" "$APT_LOG"
    grep -q "^apt upgrade -y$" "$APT_LOG"
    grep -q "^apt autoremove -y$" "$APT_LOG"
    grep -q "^refresh$" "$SNAP_LOG"
    grep -q "^update -y$" "$FLATPAK_LOG"
    [[ "$output" == *"apt update complete."* ]]
    [[ "$output" == *"All snaps updated."* ]]
    [[ "$output" == *"All flatpaks updated."* ]]
    [[ "$output" == *"No apps are registered yet."* ]]
    [[ "$output" == *"No GitHub apps installed/tracked yet."* ]]
    [[ "$output" == *"Update cycle complete."* ]]
}

@test "cli: --snap-clean degrades cleanly when snap and flatpak are missing" {
    make_min_bin
    UO_AUTO_UPDATE=0 PATH="$MIN_BIN" run bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log --snap-clean -y
    [ "$status" -eq 0 ]
    # both backends report their absence instead of failing
    [[ "$output" == *"snap is not installed on this system."* ]]
    [[ "$output" == *"flatpak is not installed on this system."* ]]
}
