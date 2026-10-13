#!/usr/bin/env bats
# ============================================================
#   test/targz.bats — tests for the tar.gz/AppImage installer
#   (lib/targz.sh)
#
#   Function level: lib/common.sh + lib/disk.sh + lib/targz.sh
#   are sourced into the test shell with a sandbox HOME (the
#   registry lands inside it). Real, tiny tar.gz fixtures are
#   built with the system tar inside the sandbox; df is a PATH
#   stub (deterministic free space) and `sudo` is overridden as
#   a logging stub that NEVER executes — so the /opt,
#   /usr/local/bin and /usr/share/applications destinations of
#   the install flow are only ever reached on paper, and the
#   tests assert the logged commands instead.
#
#   The pure helpers sanitize_app_name / desktop_escape_path /
#   guess_version / name_from_archive are covered by
#   test/appmgmt.bats and test/common.bats — not repeated here.
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

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"

    # df stub — _disk_avail_mb reads the avail column in KB (env-tunable)
    cat > "$STUB_BIN/df" << 'EOF'
#!/usr/bin/env bash
printf 'Avail\n%s\n' "${UO_DF_AVAIL_KB:-4194304}"
EOF
    chmod +x "$STUB_BIN/df"

    SUDO_LOG="$TEST_HOME/sudo-calls.log"
    : > "$SUDO_LOG"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/disk.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/targz.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"

    # sudo stub: logs every privileged call, executes nothing, always succeeds
    sudo() {
        printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
        return 0
    }
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Build a real tar.gz fixture: a single top-level folder with a working
# executable script, a readme and an icon (the archive is created in place)
make_fixture() {   # $1=parent dir  $2=top-level folder name
    mkdir -p "$1/$2"
    printf '#!/usr/bin/env bash\necho hello-from-fixture\n' > "$1/$2/mytool"
    chmod +x "$1/$2/mytool"
    printf 'readme\n' > "$1/$2/README.md"
    printf '\x89PNG\r\n' > "$1/$2/icon.png"
    (cd "$1" && tar czf "$2.tar.gz" "$2")
}

# ---------- pick_executable ----------

@test "pick_executable prefers an AppImage then an exact name match" {
    local pkg="$TEST_HOME/pkg1" rc=0
    mkdir -p "$pkg"
    printf 'x' > "$pkg/tool.bin";        chmod +x "$pkg/tool.bin"
    printf 'x' > "$pkg/MyTool.AppImage"; chmod +x "$pkg/MyTool.AppImage"
    # direct call (not `run`) so the SELECTED_EXEC side effect stays observable
    pick_executable "$pkg" "mytool" > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SELECTED_EXEC" = "$pkg/MyTool.AppImage" ]

    pkg="$TEST_HOME/pkg2"
    mkdir -p "$pkg"
    printf 'x' > "$pkg/helper"; chmod +x "$pkg/helper"
    printf 'x' > "$pkg/mytool"; chmod +x "$pkg/mytool"
    rc=0
    pick_executable "$pkg" "mytool" > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SELECTED_EXEC" = "$pkg/mytool" ]
}

@test "pick_executable falls back to the only candidate and fails when none exists" {
    local pkg="$TEST_HOME/pkg3" rc=0
    mkdir -p "$pkg/sub"
    printf 'x' > "$pkg/data.txt"                      # not executable
    printf 'x' > "$pkg/sub/only-run"; chmod +x "$pkg/sub/only-run"
    pick_executable "$pkg" "somethingelse" > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SELECTED_EXEC" = "$pkg/sub/only-run" ]

    # nothing executable in the package at all → cancel with empty result
    pkg="$TEST_HOME/pkg4"
    mkdir -p "$pkg"
    printf 'x' > "$pkg/readme.md"
    SELECTED_EXEC="stale-from-elsewhere"
    rc=0
    pick_executable "$pkg" "mytool" > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$SELECTED_EXEC" ]
}

@test "pick_executable resolves ambiguity interactively or via UO_AUTO" {
    local pkg="$TEST_HOME/pkg5" rc=0
    mkdir -p "$pkg"
    printf 'x' > "$pkg/alpha"; chmod +x "$pkg/alpha"
    printf 'x' > "$pkg/beta";  chmod +x "$pkg/beta"

    # UO_AUTO=1 picks the first sorted candidate
    UO_AUTO=1 pick_executable "$pkg" "mytool" > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SELECTED_EXEC" = "$pkg/alpha" ]

    # interactive: the user picks number 2
    rc=0
    pick_executable "$pkg" "mytool" < <(printf '2\n') > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SELECTED_EXEC" = "$pkg/beta" ]

    # EOF (Ctrl+D) cancels
    rc=0
    pick_executable "$pkg" "mytool" < /dev/null > /dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
}

# ---------- lib_pkg_candidates ----------

@test "lib_pkg_candidates maps known missing libraries to deb candidates" {
    run lib_pkg_candidates libfuse.so.2
    [ "$output" = "libfuse2t64 libfuse2" ]
    run lib_pkg_candidates libwebkit2gtk-4.1.so.0
    [ "$output" = "libwebkit2gtk-4.1-0" ]
    run lib_pkg_candidates libgtk-3.so.0
    [ "$output" = "libgtk-3-0t64 libgtk-3-0" ]
    # an unknown library maps to nothing
    run lib_pkg_candidates libtotally-unknown.so.9
    [ -z "$output" ]
}

# ---------- targz_install_from_file (the shared engine) ----------

@test "targz_install_from_file installs a real fixture with every privileged step intercepted" {
    make_fixture "$TEST_HOME/fixtures" "MyTool-1.2.3"
    local fixture="$TEST_HOME/fixtures/MyTool-1.2.3.tar.gz"

    PATH="$STUB_BIN:$PATH" run targz_install_from_file "$fixture" "mytool" < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Extracted."* ]]
    [[ "$output" == *"Main executable: "* ]]
    [[ "$output" == *"mytool installed/updated."* ]]

    # every privileged step was logged, never executed
    grep -q "^sudo mv .*MyTool-1.2.3 /opt/mytool$" "$SUDO_LOG"
    grep -q "^sudo ln -sf /opt/mytool/mytool /usr/local/bin/mytool$" "$SUDO_LOG"
    grep -q "^sudo tee /usr/share/applications/mytool.desktop" "$SUDO_LOG"
    grep -q "^sudo chown -R" "$SUDO_LOG"

    # the registry row is complete (version guessed from the file name)
    grep -q "^mytool|1.2.3|/opt/mytool|/opt/mytool/mytool|/usr/share/applications/mytool.desktop|MyTool-1.2.3.tar.gz$" "$REGISTRY_DB"

    # nothing leaked outside the sandbox
    [ ! -e /opt/mytool ]
    [ ! -e /usr/local/bin/mytool ]
}

@test "targz_install_from_file rejects an invalid name and a corrupt archive" {
    make_fixture "$TEST_HOME/fixtures" "MyTool-1.2.3"
    local fixture="$TEST_HOME/fixtures/MyTool-1.2.3.tar.gz"

    # a name that sanitizes to nothing never reaches the extraction
    PATH="$STUB_BIN:$PATH" run targz_install_from_file "$fixture" "!!!"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid app name."* ]]
    ! grep -q "^sudo mv" "$SUDO_LOG"

    # a broken archive fails with a clear message
    printf 'definitely not a tar archive\n' > "$TEST_HOME/broken.tar.gz"
    PATH="$STUB_BIN:$PATH" run targz_install_from_file "$TEST_HOME/broken.tar.gz" "mytool"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to extract:"* ]]
}

@test "targz_install_from_file aborts before extraction when disk space is short" {
    make_fixture "$TEST_HOME/fixtures" "MyTool-1.2.3"
    # 102400 KB = 100 MB free — below the 500 MB install guard
    UO_DF_AVAIL_KB=102400 PATH="$STUB_BIN:$PATH" \
        run targz_install_from_file "$TEST_HOME/fixtures/MyTool-1.2.3.tar.gz" "mytool"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Insufficient disk space: 100MB free (need 500MB)."* ]]
    # the guard fires before any extraction work
    [[ "$output" != *"Extracting..."* ]]
}

# ---------- install_targz / install_targz_cli ----------

@test "install_targz validates path extension and name before installing" {
    make_fixture "$TEST_HOME/fixtures" "MyTool-1.2.3"
    local fixture="$TEST_HOME/fixtures/MyTool-1.2.3.tar.gz"

    # EOF at the path prompt cancels quietly
    PATH="$STUB_BIN:$PATH" run install_targz < /dev/null
    [ "$status" -eq 1 ]

    # a non-archive extension is rejected
    : > "$TEST_HOME/notarchive.txt"
    PATH="$STUB_BIN:$PATH" run install_targz < <(printf '%s\n' "$TEST_HOME/notarchive.txt" "mytool")
    [ "$status" -eq 1 ]
    [[ "$output" == *"The file extension must be .tar.gz or .tgz."* ]]

    # a name that sanitizes to nothing is rejected
    PATH="$STUB_BIN:$PATH" run install_targz < <(printf '%s\n' "$fixture" "!!!")
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid app name (only letters, digits, - and _)."* ]]
    ! grep -q "^sudo mv" "$SUDO_LOG"
}

@test "install_targz_cli derives the app name from the archive file name" {
    # "mytool-1.2.3-linux-amd64.tar.gz" → derived name "mytool"
    make_fixture "$TEST_HOME/dl" "mytool-1.2.3-linux-amd64"
    local fixture="$TEST_HOME/dl/mytool-1.2.3-linux-amd64.tar.gz"
    PATH="$STUB_BIN:$PATH" run install_targz_cli "$fixture" "" < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Name derived from the file: mytool"* ]]
    [[ "$output" == *"mytool installed/updated."* ]]
    grep -q "^mytool|" "$REGISTRY_DB"

    # an archive whose name carries no app word is a hard error with the hint
    make_fixture "$TEST_HOME/dl2" "1.2.3-linux-amd64"
    PATH="$STUB_BIN:$PATH" run install_targz_cli "$TEST_HOME/dl2/1.2.3-linux-amd64.tar.gz" "" < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"The app name could not be derived from the file name."* ]]
    [[ "$output" == *"Specify it explicitly: --install-targz <file> <name>"* ]]
}

# ---------- CLI level ----------

@test "cli: --install-targz rejects bad input before anything privileged" {
    # the parser itself refuses a missing file
    run run_uo --install-targz "$TEST_HOME/missing.tar.gz"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found:"* ]]

    # an existing file with a wrong extension fails in the CLI front-end
    : > "$TEST_HOME/notarchive.zip"
    run run_uo --install-targz "$TEST_HOME/notarchive.zip"
    [ "$status" -eq 1 ]
    [[ "$output" == *"The file extension must be .tar.gz or .tgz."* ]]
}
