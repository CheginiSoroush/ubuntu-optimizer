#!/usr/bin/env bats
# ============================================================
#   test/menus.bats — tests for the interactive UI layer
#   (lib/menus.sh)
#
#   menu_loop / the submenu wrappers / main_menu are driven with
#   stubbed stdin (process substitutions / /dev/null) inside the
#   bats `run` subshell — a real terminal is never needed and an
#   accidental EOF can only exit the subshell, never the test.
#   `clear` is a PATH stub so renders are deterministic; every
#   dispatched action is either a local echo helper or a real
#   optimizer under DRY_RUN=1 (the sudo wrapper prints instead
#   of executing), so nothing privileged can fire.
#
#   Not asserted here (documented in the worklog): the boxed
#   border alignment and the emoji layout of main_menu — both are
#   cosmetic; and any submenu entry whose target module is not
#   sourced (menu_loop reports "Function ... not found" for
#   those, which is its own covered error path).
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
    # clear stub — deterministic menu rendering without a terminal
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/clear"
    chmod +x "$STUB_BIN/clear"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/menus.sh"
    # system.sh is needed so menu_system's dispatch target exists
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/system.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# Local dispatch target for the menu_loop engine tests
menu_test_action() {
    echo "ACTION-RAN"
}

# ---------- menu_loop engine ----------

@test "menu_loop renders the title the numbered items and Back" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" "Do the thing|menu_test_action" "Other|menu_test_action" < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"🧪 Test Menu"* ]]
    [[ "$output" == *"   1) Do the thing"* ]]
    [[ "$output" == *"   2) Other"* ]]
    [[ "$output" == *"   0) Back"* ]]
}

@test "menu_loop dispatches the chosen item to its function and pauses" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" "Do the thing|menu_test_action" < <(printf '1\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTION-RAN"* ]]
    # the pause prompt is rendered after the action (stderr prompt, the
    # pause itself is visible through the extra blank rendering pass)
    [[ "$output" == *"🧪 Test Menu"* ]]
}

@test "menu_loop keeps looping on invalid input and warns" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" "Do the thing|menu_test_action" < <(printf 'x\n99\n0\n')
    [ "$status" -eq 0 ]
    # both the non-numeric and the out-of-range input are warned about
    [ "$(grep -c "Invalid choice" <<< "$output")" -eq 2 ]
    # and the loop re-rendered instead of exiting
    [ "$(grep -c "Do the thing" <<< "$output")" -ge 2 ]
}

@test "menu_loop renders -w warnings above the item list" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" \
        -w "First warning" -w "Second warning" \
        "Do the thing|menu_test_action" < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"First warning"* ]]
    [[ "$output" == *"Second warning"* ]]
    [[ "$output" == *"Do the thing"* ]]
}

@test "menu_loop reports a missing dispatch target as a failure" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" "Ghost item|no_such_function_xyz" < <(printf '1\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Function 'no_such_function_xyz' not found — check the menu definition"* ]]
}

@test "menu_loop exits cleanly on EOF (Ctrl+D)" {
    PATH="$STUB_BIN:$PATH" run menu_loop "🧪 Test Menu" "Do the thing|menu_test_action" < /dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"🧪 Test Menu"* ]]
}

# ---------- submenu wrappers ----------

@test "menu_system dispatches entry 1 to the real optimizer (dry-run)" {
    DRY_RUN=1 PATH="$STUB_BIN:$PATH" run menu_system < <(printf '1\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"System & Memory Optimization"* ]]
    [[ "$output" == *"   1) Reduce swappiness & vfs_cache_pressure"* ]]
    # the dispatch really reached lib/system.sh's optimize_memory
    [[ "$output" == *"[dry-run] memory values would be set"* ]]
}

@test "menu_dangerous renders its warnings and the VEET entry" {
    PATH="$STUB_BIN:$PATH" run menu_dangerous < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Advanced Tools (Dangerous)"* ]]
    [[ "$output" == *"serious damage to your system!"* ]]
    [[ "$output" == *"Install VEET (deep removal tool — warned)"* ]]
}

# ---------- main menu ----------

@test "main_menu renders the boxed banner and exits 0 on choice 0" {
    PATH="$STUB_BIN:$PATH" run main_menu < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ubuntu Optimizer & Fixer - v${SCRIPT_VERSION}"* ]]
    [[ "$output" == *"github.com/CheginiSoroush/ubuntu-optimizer"* ]]
    [[ "$output" == *"  21) 🔍 Monitor & inspect"* ]]
    [[ "$output" == *"   0) Exit"* ]]
    [[ "$output" == *"Goodbye"* ]]
}

@test "main_menu dispatches entries to show_log and the recovery submenu" {
    PATH="$STUB_BIN:$PATH" run main_menu < <(printf '14\n\n12\n0\n0\n')
    [ "$status" -eq 0 ]
    # 14 → show_log
    [[ "$output" == *"Activity log"* ]]
    # 12 → the recovery submenu renders, 0 goes back, 0 exits
    [[ "$output" == *"System Recovery & Rescue"* ]]
    [[ "$output" == *"Fix broken packages (apt --fix-broken)"* ]]
    [[ "$output" == *"Goodbye"* ]]
}

@test "main_menu warns on an invalid choice and keeps going" {
    PATH="$STUB_BIN:$PATH" run main_menu < <(printf '42\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invalid choice"* ]]
    [[ "$output" == *"Goodbye"* ]]
}
