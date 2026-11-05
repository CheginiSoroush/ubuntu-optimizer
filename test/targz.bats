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

# ---------- AppImage launch-failure hardening (v7.18.1) ----------

@test "appimage_ensure_fuse: passes through when libfuse2 is already present" {
    appimage_has_fuse() { return 0; }
    run appimage_ensure_fuse
    [ "$status" -eq 0 ]
    ! grep -q "sudo apt install" "$SUDO_LOG"
}

@test "appimage_ensure_fuse: refuses honestly when libfuse2 cannot be installed" {
    appimage_has_fuse() { return 1; }   # the apt stub never really installs
    sudo() { printf 'sudo %s\n' "$*" >> "$SUDO_LOG"; return 1; }   # apt fails both times
    run appimage_ensure_fuse
    [ "$status" -eq 1 ]
    [[ "$output" == *"libfuse2 is still missing"* ]]
    grep -q "sudo apt install -y libfuse2t64" "$SUDO_LOG"
    grep -q "sudo apt install -y libfuse2$" "$SUDO_LOG"
}

@test "appimage_print_launch_hint: always tells the user how to see the hidden error" {
    INFO_LOG="$TEST_HOME/info.log"
    info() { printf '%s\n' "$*" >> "$INFO_LOG"; }
    run appimage_print_launch_hint "myapp"
    [ "$status" -eq 0 ]
    grep -q "run it once in a terminal — 'myapp'" "$INFO_LOG"
    # the hint must point at the permanent fix, not just --no-sandbox
    grep -q "uo --fix-appimage-sandbox" "$INFO_LOG"
}

# ---------- AppImage sandbox doctor (v7.18.2) ----------

@test "appimage_userns_profile_body: emits the documented Ubuntu 23.10+ profile" {
    run appimage_userns_profile_body "uo-appimage-zcode" "/opt/zcode/ZCode.AppImage"
    [ "$status" -eq 0 ]
    [[ "$output" == *"abi 4.0,"* ]]
    [[ "$output" == *"include <tunables/global>"* ]]
    [[ "$output" == *"profile uo-appimage-zcode /opt/zcode/ZCode.AppImage flags=(unconfined)"* ]]
    [[ "$output" == *"  userns,"* ]]
    [[ "$output" == *"include if exists <local/uo-appimage-zcode>"* ]]
}

@test "appimage_write_userns_profile: produces the exact profile file" {
    local dest="$TEST_HOME/uo-appimage-test"
    run appimage_write_userns_profile "$dest" "uo-appimage-test" "/x/Test.AppImage"
    [ "$status" -eq 0 ]
    grep -q "profile uo-appimage-test /x/Test.AppImage flags=(unconfined)" "$dest"
    grep -q "  userns," "$dest"
}

@test "appimage_fix_sandbox: rejects missing files and non-AppImage paths" {
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    run appimage_fix_sandbox ""
    [ "$status" -eq 1 ]
    grep -q "Usage: uo --fix-appimage-sandbox" "$MSG_LOG"

    : > "$MSG_LOG"
    run appimage_fix_sandbox "$TEST_HOME/missing.AppImage"
    [ "$status" -eq 1 ]
    grep -q "File not found" "$MSG_LOG"

    : > "$TEST_HOME/notapp.txt"
    : > "$MSG_LOG"
    run appimage_fix_sandbox "$TEST_HOME/notapp.txt"
    [ "$status" -eq 1 ]
    grep -q "Not an AppImage" "$MSG_LOG"
}

@test "appimage_fix_sandbox: installs the profile via sudo (install + parser logged)" {
    sanitize_app_name() { printf '%s' "${1//[^a-zA-Z0-9._-]/-}"; }
    header() { :; }
    info() { :; }
    success() { :; }
    confirm_action() { return 0; }
    local app="$TEST_HOME/ZCode.AppImage"
    : > "$app"
    run appimage_fix_sandbox "$app"
    [ "$status" -eq 0 ]
    grep -q "sudo install -m 0644" "$SUDO_LOG"
    grep -q "sudo apparmor_parser -r -T /etc/apparmor.d/uo-appimage-ZCode" "$SUDO_LOG"
}

@test "appimage_fix_sandbox: dry-run shows the profile but never touches sudo" {
    sanitize_app_name() { printf '%s' "${1//[^a-zA-Z0-9._-]/-}"; }
    header() { :; }
    MSG_LOG="$TEST_HOME/msg.log"
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    warn() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    success() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    local app="$TEST_HOME/Other.AppImage"
    : > "$app"
    DRY_RUN=1 run appimage_fix_sandbox "$app"
    [ "$status" -eq 0 ]
    # the profile body is printed raw to stdout — captured by bats `run`
    [[ "$output" == *"profile uo-appimage-Other $TEST_HOME/Other.AppImage flags=(unconfined)"* ]]
    grep -q "dry-run.*apparmor_parser -r -T /etc/apparmor.d/uo-appimage-Other" "$MSG_LOG"
    [ ! -s "$SUDO_LOG" ]
}

@test "appimage_fix_sandbox: parser failure falls back to honest guidance" {
    sanitize_app_name() { printf '%s' "${1//[^a-zA-Z0-9._-]/-}"; }
    header() { :; }
    info() { :; }
    success() { :; }
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    confirm_action() { return 0; }
    sudo() { return 1; }   # both install and parser fail
    local app="$TEST_HOME/Fail.AppImage"
    : > "$app"
    run appimage_fix_sandbox "$app"
    [ "$status" -eq 1 ]
    grep -q "Could not install the AppArmor profile" "$MSG_LOG"
}

@test "cli: --fix-appimage-sandbox requires a path argument" {
    run run_uo --fix-appimage-sandbox
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a path"* ]]
}

@test "appimage_install_from_file: warns about an ARM-only AppImage on an x86 machine" {
    # minimal aarch64 ELF header (e_machine = 0xB7) — file(1) classifies it
    ARM_ELF="$TEST_HOME/arm-app.AppImage"
    printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00ARM' > "$ARM_ELF"
    file -b "$ARM_ELF" | grep -qi aarch64 || skip "file(1) did not classify the fixture"
    [ "$(uname -m)" = "x86_64" ] || skip "this runner is not x86_64"
    INFO_LOG="$TEST_HOME/info.log"
    : > "$INFO_LOG"
    info() { printf '%s\n' "$*" >> "$INFO_LOG"; }
    warn() { printf '%s\n' "$*" >> "$INFO_LOG"; }
    confirm_action() { return 1; }   # decline the "install anyway" question
    run appimage_install_from_file "$ARM_ELF" "armapp"
    [ "$status" -eq 0 ]
    grep -q "built for ARM" "$INFO_LOG"
    grep -q "Cancelled — nothing was installed" "$INFO_LOG"
}
