#!/usr/bin/env bats
# ============================================================
#   test/doctor.bats — tests for the app health check & repair
#   (lib/doctor.sh)
#
#   Function level: lib/common.sh + targz/appmgmt/github +
#   doctor.sh sourced into the test shell with a temp HOME, so
#   REGISTRY_DB/GITHUB_DB and every repair target live in the
#   sandbox. External tools (ldd, file, dpkg, dpkg-query) are
#   PATH stubs; the unfixable flows are chosen so the module
#   never reaches its sudo repair steps (no /usr/local/bin or
#   desktop-file writes outside the temp HOME can happen).
#   CLI level runs the real entry script with --doctor.
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

load_doctor() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/targz.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/appmgmt.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/github.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/doctor.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

make_tool() {   # $1=dir  $2=name  (executable no-op stub)
    mkdir -p "$1"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$1/$2"
    chmod +x "$1/$2"
}

write_ldd_stub() {
    # Keyed on the file basename: *static* → not dynamic, *gui* → GUI libs
    cat > "$STUB_BIN/ldd" << 'EOF'
#!/usr/bin/env bash
case "${1##*/}" in
    *static*) printf '\tnot a dynamic executable\n' ;;
    *gui*)    printf '\tlibX11.so.6 => /usr/lib/x86_64-linux-gnu/libX11.so.6\n' ;;
    *)        printf '\tlibc.so.6 => /usr/lib/x86_64-linux-gnu/libc.so.6\n' ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/ldd"
}

write_file_stub() {
    cat > "$STUB_BIN/file" << 'EOF'
#!/usr/bin/env bash
case "$*" in
    *macho*) printf 'Mach-O 64-bit executable x86_64\n' ;;
    *)       printf 'ELF 64-bit LSB executable, x86-64\n' ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/file"
}

write_dpkg_query_stub() {
    cat > "$STUB_BIN/dpkg-query" << 'EOF'
#!/usr/bin/env bash
name="${*: -1}"
case " ${UO_INSTALLED_PKGS:-} " in
    *" $name "*) printf 'install ok installed'; exit 0 ;;
esac
printf "dpkg-query: no packages found matching %s\n" "$name" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/dpkg-query"
}

write_dpkg_stub() {
    cat > "$STUB_BIN/dpkg" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-L" ]; then
    [ -n "${UO_DPKG_L_FILE:-}" ] && cat "$UO_DPKG_L_FILE"
    exit 0
fi
exit 0
EOF
    chmod +x "$STUB_BIN/dpkg"
}

# ---------- function level: result recording ----------

@test "doctor_result bumps exactly one counter per outcome and reports it" {
    load_doctor
    DOCTOR_TOTAL=0; DOCTOR_OK=0; DOCTOR_FIXED=0; DOCTOR_FAILED=0
    doctor_result ok     tracker "config looks good" > /dev/null 2>&1
    doctor_result fixed  tracker "exec permission"    > /dev/null 2>&1
    doctor_result broken tracker "install directory missing"
    [ "$DOCTOR_TOTAL"  -eq 3 ]
    [ "$DOCTOR_OK"     -eq 1 ]
    [ "$DOCTOR_FIXED"  -eq 1 ]
    [ "$DOCTOR_FAILED" -eq 1 ]
}

# ---------- function level: terminal detection ----------

@test "doctor_terminal_cmd prefers ptyxis, then gnome-terminal, konsole, xterm, else empty" {
    load_doctor
    PTYXIS_BIN="$TEST_HOME/ptyxis-bin";   make_tool "$PTYXIS_BIN" ptyxis
    GNOME_BIN="$TEST_HOME/gnome-bin";     make_tool "$GNOME_BIN" gnome-terminal
    KONSOLE_BIN="$TEST_HOME/konsole-bin"; make_tool "$KONSOLE_BIN" konsole; make_tool "$KONSOLE_BIN" xterm
    EMPTY_BIN="$TEST_HOME/empty-bin";     mkdir -p "$EMPTY_BIN"
    run_ptyxis()  { PATH="$PTYXIS_BIN" doctor_terminal_cmd; }
    run_gnome()   { PATH="$GNOME_BIN" doctor_terminal_cmd; }
    run_konsole() { PATH="$KONSOLE_BIN" doctor_terminal_cmd; }
    run_none()    { PATH="$EMPTY_BIN" doctor_terminal_cmd; }
    run run_ptyxis
    [ "$status" -eq 0 ]
    [ "$output" = "ptyxis --" ]
    run run_gnome
    [ "$output" = "gnome-terminal --" ]
    run run_konsole
    [ "$output" = "konsole -e" ]
    run run_none
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "doctor_terminal_flag classifies TUI/GUI binaries and resolves Electron .bin siblings" {
    load_doctor
    write_ldd_stub
    export PATH="$STUB_BIN:$PATH"
    BINS="$TEST_HOME/bins"; mkdir -p "$BINS"
    printf 'ELF-fake-payload' >  "$BINS/tui-static"    # static non-script → TUI
    printf 'ELF-fake-payload' >  "$BINS/cli-app"       # dynamic, no GUI libs → TUI
    printf 'ELF-fake-payload' >  "$BINS/guiapp"        # dynamic with GUI libs → GUI
    printf '#!/bin/sh\necho hi\n' > "$BINS/pyscript-static"; chmod +x "$BINS/pyscript-static"  # script, static ldd → GUI-safe
    printf '#!/bin/sh\necho hi\n' > "$BINS/launcher";        chmod +x "$BINS/launcher"         # plain script, dynamic ldd → TUI
    printf '#!/bin/sh\necho hi\n' > "$BINS/photoapp";        chmod +x "$BINS/photoapp"         # Electron TUI …
    printf 'ELF-fake-payload' >  "$BINS/photoapp.bin"   # … real binary has no GUI libs
    printf '#!/bin/sh\necho hi\n' > "$BINS/guilaunch";       chmod +x "$BINS/guilaunch"        # Electron GUI …
    printf 'ELF-fake-payload' >  "$BINS/guilaunch.bin"  # … real binary links GUI libs (name contains "gui")
    run doctor_terminal_flag "$BINS/tui-static"
    [ "$output" = "true" ]
    run doctor_terminal_flag "$BINS/cli-app"
    [ "$output" = "true" ]
    run doctor_terminal_flag "$BINS/guiapp"
    [ "$output" = "false" ]
    run doctor_terminal_flag "$BINS/pyscript-static"
    [ "$output" = "false" ]
    run doctor_terminal_flag "$BINS/launcher"
    [ "$output" = "true" ]
    run doctor_terminal_flag "$BINS/photoapp"      # resolves to photoapp.bin → true
    [ "$output" = "true" ]
    run doctor_terminal_flag "$BINS/guilaunch"     # resolves to guilaunch.bin → false
    [ "$output" = "false" ]
}

# ---------- function level: doctor_check_targz (no sudo reached) ----------

@test "doctor_check_targz reports a missing install directory as broken" {
    load_doctor
    run doctor_check_targz myapp 1.0 "$TEST_HOME/absent-dir" \
        "$TEST_HOME/absent-dir/myapp" "$TEST_HOME/myapp.desktop" "$TEST_HOME/src.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" == *"myapp: install directory missing"* ]]
    [[ "$output" == *"reinstall the app"* ]]
}

@test "doctor_check_targz detects Mach-O (macOS) binaries as unfixable" {
    load_doctor
    write_file_stub
    APP_DIR="$TEST_HOME/apps/myapp"; mkdir -p "$APP_DIR"
    printf 'cffaedfe-fake-macho' > "$APP_DIR/macho-binary"; chmod +x "$APP_DIR/macho-binary"
    PATH="$STUB_BIN:$PATH" run doctor_check_targz myapp 1.0 "$APP_DIR" \
        "$APP_DIR/macho-binary" "$TEST_HOME/myapp.desktop" "$TEST_HOME/src.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" == *"macOS format (Mach-O)"* ]]
    [[ "$output" == *"uo --github-install"* ]]
}

# ---------- function level: doctor_check_deb ----------

@test "doctor_check_deb removes a stale tracking entry when the package is gone" {
    load_doctor
    write_dpkg_query_stub
    gh_db_add goneapp owner/repo v1.0.0
    grep -q goneapp "$GITHUB_DB"
    UO_INSTALLED_PKGS="" PATH="$STUB_BIN:$PATH" run doctor_check_deb goneapp
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale tracking entry removed"* ]]
    ! grep -q goneapp "$GITHUB_DB"
}

@test "doctor_check_deb accepts a package via its command or a working desktop entry" {
    load_doctor
    write_dpkg_query_stub
    write_dpkg_stub
    make_tool "$STUB_BIN" happyapp
    export PATH="$STUB_BIN:$PATH"
    # 1) command reachable → healthy
    UO_INSTALLED_PKGS="happyapp" UO_DPKG_L_FILE=/dev/null run doctor_check_deb happyapp
    [ "$status" -eq 0 ]
    [[ "$output" == *"happyapp: healthy"* ]]
    # 2) no standard binary, but a shipped desktop entry with a valid Exec → healthy
    DESK_DIR="$TEST_HOME/deskpkg"; mkdir -p "$DESK_DIR"
    printf '[Desktop Entry]\nExec=happyapp\n' > "$DESK_DIR/desk.desktop"
    UO_DPKG_L_FILE="$TEST_HOME/dpkg-l-desk.txt"
    printf '%s\n' "$DESK_DIR/desk.desktop" > "$UO_DPKG_L_FILE"
    UO_INSTALLED_PKGS="deskpkg" UO_DPKG_L_FILE="$UO_DPKG_L_FILE" run doctor_check_deb deskpkg
    [[ "$output" == *"deskpkg: healthy"* ]]
}

@test "doctor_check_deb flags a desktop entry that points to a missing file" {
    load_doctor
    write_dpkg_query_stub
    write_dpkg_stub
    export PATH="$STUB_BIN:$PATH"
    BROKEN="$TEST_HOME/broken.desktop"
    printf '[Desktop Entry]\nExec=/opt/vanished/binary\n' > "$BROKEN"
    UO_DPKG_L_FILE="$TEST_HOME/dpkg-l-broken.txt"
    printf '%s\n' "$BROKEN" > "$UO_DPKG_L_FILE"
    UO_INSTALLED_PKGS="brokenapp" UO_DPKG_L_FILE="$UO_DPKG_L_FILE" run doctor_check_deb brokenapp
    [ "$status" -eq 0 ]
    [[ "$output" == *"brokenapp: desktop entry points to a missing file"* ]]
}

# ---------- function level: doctor_apps ----------

@test "doctor_apps reports friendly empty state without any tracked app" {
    load_doctor
    run doctor_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"No tracked apps found"* ]]
}

@test "doctor_apps checks a tracked deb app and prints the summary counters" {
    load_doctor
    write_dpkg_query_stub
    make_tool "$STUB_BIN" happyapp
    gh_db_add happyapp owner/repo v2.0.1
    DRY_RUN=1 UO_INSTALLED_PKGS="happyapp" PATH="$STUB_BIN:$PATH" run doctor_apps
    [ "$status" -eq 0 ]
    [[ "$output" == *"Checking: happyapp (deb)"* ]]
    [[ "$output" == *"happyapp: healthy"* ]]
    [[ "$output" == *"Doctor Summary"* ]]
    [[ "$output" == *"Total checked: 1"* ]]
    [[ "$output" == *"Healthy:     1"* ]]
    [[ "$output" == *"Repaired:   0"* ]]
    [[ "$output" == *"Unfixable:   0"* ]]
}

# ---------- CLI level ----------

@test "cli: --doctor on a fresh profile finds no tracked apps and exits 0" {
    run run_uo --doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"No tracked apps found"* ]]
}
