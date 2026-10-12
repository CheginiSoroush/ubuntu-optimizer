#!/usr/bin/env bats
# ============================================================
#   test/autostart.bats — tests for the startup applications
#   manager (lib/autostart.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The autostart module is exercised at two levels:
#     • CLI level — the real entry script with --autostart and
#       --autostart-on/--autostart-off against a fake XDG tree
#       (XDG_CONFIG_HOME + XDG_CONFIG_DIRS pinned into a temp HOME).
#     • Function level — lib/common.sh + lib/autostart.sh sourced
#       into the test shell; the toggle logic (override creation,
#       override removal, force-enable of system-disabled entries,
#       traversal safety) is verified directly on the fake tree.
#   System files are never expected to change — every test asserts
#   that. Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/.config"
    export XDG_CONFIG_DIRS="$TEST_HOME/etc/xdg"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # ── fake XDG autostart tree ─────────────────────────────────────────────
    SYS_DIR="$TEST_HOME/etc/xdg/autostart"
    USR_DIR="$TEST_HOME/.config/autostart"
    mkdir -p "$SYS_DIR" "$USR_DIR"

    cat > "$SYS_DIR/sysapp.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=System App
Exec=system-app --daemon
NoDisplay=false
EOF

    cat > "$SYS_DIR/sysoff.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=System Off
Exec=system-off --quiet
Hidden=true
EOF

    cat > "$USR_DIR/userapp.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=User App
Exec=user-app --flag
X-GNOME-Autostart-enabled=true

[Desktop Action second]
Name=Wrong Name
Exec=wrong-exec
EOF
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules an autostart test needs, into the test shell
load_autostart() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/autostart.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
    ASSUME_YES=1
    LOG_ENABLED=0
}

# ---------- function level: parsing ----------

@test "_autostart_field reads [Desktop Entry] keys and ignores other sections" {
    load_autostart
    run _autostart_field "$USR_DIR/userapp.desktop" "Name"
    [ "$output" = "User App" ]
    run _autostart_field "$USR_DIR/userapp.desktop" "Exec"
    [ "$output" = "user-app --flag" ]
    run _autostart_field "$USR_DIR/userapp.desktop" "NoSuchKey"
    [ "$output" = "" ]
}

@test "_autostart_disabled detects Hidden=true and the enable marker" {
    load_autostart
    run _autostart_disabled "$SYS_DIR/sysapp.desktop"
    [ "$status" -eq 1 ]
    run _autostart_disabled "$SYS_DIR/sysoff.desktop"
    [ "$status" -eq 0 ]
    run _autostart_disabled "$USR_DIR/userapp.desktop"
    [ "$status" -eq 1 ]
}

# ---------- function level: resolution ----------

@test "_autostart_resolve maps the name to its effective file and origin" {
    load_autostart
    run _autostart_resolve "sysapp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SYS_DIR/sysapp.desktop"* ]]
    [[ "$output" == *"system"* ]]
    run _autostart_resolve "userapp.desktop"
    [ "$status" -eq 0 ]
    [[ "$output" == *"user"* ]]
    run _autostart_resolve "ghost"
    [ "$status" -eq 1 ]
}

@test "_autostart_resolve strips path components (no traversal)" {
    load_autostart
    run _autostart_resolve "../../etc/evil"
    [ "$status" -eq 1 ]
    [ ! -f "$TEST_HOME/etc/xdg/autostart/evil.desktop" ]
}

# ---------- function level: toggling ----------

@test "autostart_set off disables a user entry in place" {
    load_autostart
    run autostart_set "userapp" off
    [ "$status" -eq 0 ]
    [ "$(_autostart_field "$USR_DIR/userapp.desktop" "Hidden")" = "true" ]
    [ "$(_autostart_field "$USR_DIR/userapp.desktop" "X-GNOME-Autostart-enabled")" = "false" ]
    [ "$(_autostart_field "$USR_DIR/userapp.desktop" "Name")" = "User App" ]
    [[ "$output" == *"disabled at startup"* ]]
}

@test "autostart_set off leaves exactly one pair of markers (no duplicates)" {
    load_autostart
    autostart_set "userapp" off > /dev/null
    autostart_set "userapp" on  > /dev/null
    autostart_set "userapp" off > /dev/null
    local n
    n=$(grep -c "^Hidden=" "$USR_DIR/userapp.desktop")
    [ "$n" = "1" ]
    n=$(grep -c "^X-GNOME-Autostart-enabled=" "$USR_DIR/userapp.desktop")
    [ "$n" = "1" ]
    # the [Desktop Action] section must stay untouched
    run _autostart_field "$USR_DIR/userapp.desktop" "Name"
    [ "$output" = "User App" ]
}

@test "autostart_set off on a system entry creates a user override" {
    load_autostart
    run autostart_set "sysapp" off
    [ "$status" -eq 0 ]
    [ -f "$USR_DIR/sysapp.desktop" ]
    [ "$(_autostart_field "$USR_DIR/sysapp.desktop" "Hidden")" = "true" ]
    # the system file itself must stay untouched
    [ "$(_autostart_field "$SYS_DIR/sysapp.desktop" "Hidden")" = "" ]
    [[ "$output" == *"override"* ]]
}

@test "autostart_set on removes the override of an enabled system entry" {
    load_autostart
    autostart_set "sysapp" off > /dev/null
    run autostart_set "sysapp" on
    [ "$status" -eq 0 ]
    [ ! -f "$USR_DIR/sysapp.desktop" ]
    [ -f "$SYS_DIR/sysapp.desktop" ]
    [[ "$output" == *"override removed"* ]]
}

@test "autostart_set on force-enables a system entry disabled by default" {
    load_autostart
    run autostart_set "sysoff" on
    [ "$status" -eq 0 ]
    [ -f "$USR_DIR/sysoff.desktop" ]
    [ "$(_autostart_field "$USR_DIR/sysoff.desktop" "X-GNOME-Autostart-enabled")" = "true" ]
    # system default stays Hidden — the override wins
    [ "$(_autostart_field "$SYS_DIR/sysoff.desktop" "Hidden")" = "true" ]
}

@test "autostart_set on an already-enabled entry is a no-op" {
    load_autostart
    run autostart_set "userapp" on
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled"* ]]
    [ "$(_autostart_field "$USR_DIR/userapp.desktop" "Hidden")" = "" ]
}

@test "autostart_set rejects an unknown name" {
    load_autostart
    run autostart_set "ghost" off
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "autostart_set rejects an invalid state" {
    load_autostart
    run autostart_set "userapp" sideways
    [ "$status" -eq 1 ]
    [[ "$output" == *"on or off"* ]]
}

# ---------- function level: listing ----------

@test "autostart_show lists every entry with its state and origin" {
    load_autostart
    run autostart_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Startup Applications"* ]]
    [[ "$output" == *"sysapp.desktop"* ]]
    [[ "$output" == *"sysoff.desktop"* ]]
    [[ "$output" == *"userapp.desktop"* ]]
    [[ "$output" == *"3 startup application(s): 2 enabled, 1 disabled"* ]]
    [[ "$output" == *"(user)"* ]]
    [[ "$output" == *"(system)"* ]]
}

@test "autostart_show is friendly when no entries exist" {
    load_autostart
    rm -f "$SYS_DIR"/*.desktop "$USR_DIR"/*.desktop
    run autostart_show
    [ "$status" -eq 0 ]
    [[ "$output" == *"No autostart entries"* ]]
}

# ---------- CLI level ----------

@test "cli: --autostart lists the fake XDG tree" {
    run run_uo --autostart
    [ "$status" -eq 0 ]
    [[ "$output" == *"Startup Applications"* ]]
    [[ "$output" == *"sysapp.desktop"* ]]
}

@test "cli: --autostart-off disables without touching the system file" {
    load_autostart
    run run_uo --autostart-off sysapp -y
    [ "$status" -eq 0 ]
    [ "$(_autostart_field "$USR_DIR/sysapp.desktop" "Hidden")" = "true" ]
    [ "$(_autostart_field "$SYS_DIR/sysapp.desktop" "Hidden")" = "" ]
}

@test "cli: --autostart-on re-enables through the full round trip" {
    load_autostart
    run run_uo --autostart-off userapp -y
    [ "$status" -eq 0 ]
    run run_uo --autostart-on userapp -y
    [ "$status" -eq 0 ]
    [ "$(_autostart_field "$USR_DIR/userapp.desktop" "X-GNOME-Autostart-enabled")" = "true" ]
}

@test "cli: --autostart-off without a name is rejected" {
    run run_uo --autostart-off
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a name"* ]]
}

@test "cli: --autostart-off ../../etc/evil is safely refused" {
    run run_uo --autostart-off "../../etc/evil" -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}
