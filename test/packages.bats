#!/usr/bin/env bats
# ============================================================
#   test/packages.bats — tests for the apt-based package
#   installs (lib/packages.sh)
#
#   apt/dpkg/apt-cache/dpkg-query/npm/node are PATH stubs that
#   record their invocations into per-test log files; the sudo()
#   helper routes through a pass-through sudo stub, so no real
#   package operation can ever run. Interactive install_deb input
#   is piped through wrapper functions; HOME lives in the sandbox.
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

load_packages() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/packages.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

write_stubs() {
    cat > "$STUB_BIN/sudo" << 'EOF'
#!/usr/bin/env bash
# Pass-through sudo stub — the sourced sudo() function routes here
# via `command sudo`, so wrapped commands run against the PATH stubs.
exec "$@"
EOF
    chmod +x "$STUB_BIN/sudo"
    cat > "$STUB_BIN/apt" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_APT_LOG:-}" ] && printf '%s\n' "$*" >> "$UO_APT_LOG"
[ -n "${UO_APT_RC:-}" ] && exit "$UO_APT_RC"
exit 0
EOF
    chmod +x "$STUB_BIN/apt"
    cat > "$STUB_BIN/dpkg" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_DPKG_LOG:-}" ] && printf '%s\n' "$*" >> "$UO_DPKG_LOG"
[ -n "${UO_DPKG_RC:-}" ] && exit "$UO_DPKG_RC"
exit 0
EOF
    chmod +x "$STUB_BIN/dpkg"
    cat > "$STUB_BIN/apt-cache" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_APT_CACHE_RC:-}" ] && exit "$UO_APT_CACHE_RC"
printf 'Package: unrar\n'
exit 0
EOF
    chmod +x "$STUB_BIN/apt-cache"
    cat > "$STUB_BIN/dpkg-query" << 'EOF'
#!/usr/bin/env bash
name="${*: -1}"
case " ${UO_INSTALLED_PKGS:-} " in
    *" $name "*) printf 'install ok installed'; exit 0 ;;
esac
exit 1
EOF
    chmod +x "$STUB_BIN/dpkg-query"
    cat > "$STUB_BIN/npm" << 'EOF'
#!/usr/bin/env bash
[ -n "${UO_NPM_LOG:-}" ] && printf '%s\n' "$*" >> "$UO_NPM_LOG"
[ -n "${UO_NPM_RC:-}" ] && exit "$UO_NPM_RC"
exit 0
EOF
    chmod +x "$STUB_BIN/npm"
    cat > "$STUB_BIN/node" << 'EOF'
#!/usr/bin/env bash
printf 'v20.11.0\n'
EOF
    chmod +x "$STUB_BIN/node"
    export PATH="$STUB_BIN:$PATH"
}

# ---------- install_essential_tools ----------

@test "install_essential_tools installs the exact tool list via apt; failure propagates" {
    load_packages
    write_stubs
    UO_APT_LOG="$TEST_HOME/apt-ok.log" run install_essential_tools
    [ "$status" -eq 0 ]
    [[ "$output" == *"Essential tools installed."* ]]
    [ "$(cat "$TEST_HOME/apt-ok.log")" = "install -y curl wget git synaptic iw net-tools gnome-tweaks" ]
    UO_APT_RC=1 UO_APT_LOG="$TEST_HOME/apt-bad.log" run install_essential_tools
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to install the tools."* ]]
}

# ---------- install_unrar ----------

@test "install_unrar succeeds, and on failure hints multiverse only when unrar is unavailable" {
    load_packages
    write_stubs
    run install_unrar
    [ "$status" -eq 0 ]
    [[ "$output" == *"Archive tools installed."* ]]
    # Failure + unrar not visible to apt-cache → multiverse hint
    UO_APT_RC=1 UO_APT_CACHE_RC=1 run install_unrar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to install the tools."* ]]
    [[ "$output" == *"enable multiverse"* ]]
    # Failure but unrar exists in the repos → no hint
    UO_APT_RC=1 UO_APT_CACHE_RC=0 run install_unrar
    [ "$status" -eq 1 ]
    [[ "$output" != *"multiverse"* ]]
}

# ---------- install_deb ----------

@test "install_deb installs an existing .deb and rewrites bare names and ~ paths" {
    load_packages
    write_stubs
    PKGS="$TEST_HOME/pkgs"; mkdir -p "$PKGS"
    printf 'deb-payload' > "$PKGS/tool.deb"
    deb_input() { printf '%s\n' "$1" | install_deb; }
    # Absolute path
    UO_APT_LOG="$TEST_HOME/apt1.log" run deb_input "$PKGS/tool.deb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Package installed successfully."* ]]
    grep -qx "install -y $PKGS/tool.deb" "$TEST_HOME/apt1.log"
    # Bare file name → ./ prefix so apt cannot mistake it for a package
    # (./tool.deb only resolves from inside the package directory)
    cd "$PKGS" || fail "cannot cd into $PKGS"
    UO_APT_LOG="$TEST_HOME/apt2.log" run deb_input "tool.deb"
    [ "$status" -eq 0 ]
    grep -qx "install -y ./tool.deb" "$TEST_HOME/apt2.log"
    # Leading ~ expands to (sandbox) HOME
    UO_APT_LOG="$TEST_HOME/apt3.log" run deb_input "~/pkgs/tool.deb"
    [ "$status" -eq 0 ]
    grep -qx "install -y $PKGS/tool.deb" "$TEST_HOME/apt3.log"
}

@test "install_deb rejects missing files, wrong extensions and EOF" {
    load_packages
    write_stubs
    PKGS="$TEST_HOME/pkgs"; mkdir -p "$PKGS"
    printf 'text' > "$PKGS/notadeb.txt"
    deb_input() { printf '%s\n' "$1" | install_deb; }
    run deb_input "$PKGS/absent.deb"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found: $PKGS/absent.deb"* ]]
    run deb_input "$PKGS/notadeb.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must have a .deb extension."* ]]
    deb_eof() { install_deb < /dev/null; }
    run deb_eof
    [ "$status" -eq 1 ]
    [[ "$output" != *"Installing the package..."* ]]   # cancelled before any install
}

@test "install_deb falls back to dpkg -i and repairs dependencies when apt refuses" {
    load_packages
    write_stubs
    PKGS="$TEST_HOME/pkgs"; mkdir -p "$PKGS"
    printf 'deb-payload' > "$PKGS/fallback.deb"
    deb_input() { printf '%s\n' "$1" | install_deb; }
    UO_APT_RC=1 UO_APT_LOG="$TEST_HOME/apt.log" UO_DPKG_LOG="$TEST_HOME/dpkg.log" \
        run deb_input "$PKGS/fallback.deb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"trying dpkg..."* ]]
    [[ "$output" == *"Package installed (with dependencies fixed)."* ]]
    grep -qx "install -y $PKGS/fallback.deb" "$TEST_HOME/apt.log"
    grep -qx -- "-i $PKGS/fallback.deb" "$TEST_HOME/dpkg.log"
    grep -q -- "--fix-broken install -y" "$TEST_HOME/apt.log"
}

# ---------- install_appclean ----------

@test "install_appclean requires node and npm, then installs the pinned version" {
    load_packages
    write_stubs
    # A PATH without node/npm → the node precheck fails with the menu hint
    NONODE_BIN="$TEST_HOME/nonode-bin"; mkdir -p "$NONODE_BIN"
    cp "$STUB_BIN/sudo" "$STUB_BIN/apt" "$STUB_BIN/dpkg" "$STUB_BIN/dpkg-query" "$STUB_BIN/apt-cache" "$NONODE_BIN/"
    PATH="$NONODE_BIN" run install_appclean
    [ "$status" -eq 1 ]
    [[ "$output" == *"nodejs is not installed."* ]]
    # node present but npm missing → the npm precheck fires
    NONPM_BIN="$TEST_HOME/nonpm-bin"; mkdir -p "$NONPM_BIN"
    cp "$STUB_BIN/node" "$NONPM_BIN/"
    PATH="$NONPM_BIN" run install_appclean
    [ "$status" -eq 1 ]
    [[ "$output" == *"npm is not installed."* ]]
    # node + npm available (the stub PATH) → the pinned npm install runs
    UO_NPM_LOG="$TEST_HOME/npm.log" run install_appclean
    [ "$status" -eq 0 ]
    [[ "$output" == *"AppClean installed. Run with: appclean gui"* ]]
    [ "$(cat "$TEST_HOME/npm.log")" = "install -g appclean@2.0.0" ]
    UO_NPM_RC=1 UO_NPM_LOG="$TEST_HOME/npm2.log" run install_appclean
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to install AppClean."* ]]
}

# ---------- install_nodejs ----------

@test "install_nodejs reports versions when present, installs via apt otherwise" {
    load_packages
    write_stubs
    # Already installed → no apt call, versions reported
    UO_INSTALLED_PKGS="nodejs npm" UO_APT_LOG="$TEST_HOME/apt-skip.log" run install_nodejs
    [ "$status" -eq 0 ]
    [[ "$output" == *"nodejs and npm are already installed."* ]]
    [[ "$output" == *"node v20.11.0"* ]]
    [ ! -e "$TEST_HOME/apt-skip.log" ]
    # Fresh install via apt
    UO_INSTALLED_PKGS="" UO_APT_LOG="$TEST_HOME/apt-new.log" run install_nodejs
    [ "$status" -eq 0 ]
    [[ "$output" == *"nodejs and npm installed."* ]]
    grep -qx "install -y nodejs npm" "$TEST_HOME/apt-new.log"
    # apt failure propagates
    UO_INSTALLED_PKGS="" UO_APT_RC=1 run install_nodejs
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to install nodejs."* ]]
}
