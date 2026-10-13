#!/usr/bin/env bats
# ============================================================
#   test/fzf.bats — tests for the fzf launcher (lib/fzf.sh)
#
#   The launcher is exercised at three levels:
#     • Pure helper — _fzf_actions emits "label|key" lines and is
#       checked against the real lib/ modules (every key must be a
#       defined function, so menu wiring drift fails the suite).
#     • Function level — run_cli_fzf with a stub fzf on PATH that
#       swallows the action list, records its argv and replays a
#       fixed selection (UO_FZF_STUB_CHOICE) and exit code
#       (UO_FZF_STUB_RC); plus a copy-based minimal PATH that lacks
#       fzf entirely (deterministic even on hosts that have fzf).
#     • CLI / menu level — the real entry script with --fzf and the
#       main-menu entry 23 driven over stubbed stdin.
#   Hermetic: temp HOME, no network, only read-only dispatch
#   targets (show_log); teardown removes the mktemp sandbox only.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    unset UO_FZF_BIN UO_FZF_STUB_CHOICE UO_FZF_STUB_RC UO_FZF_STUB_ARGS
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
    # fzf stub: swallows the action list from stdin, records its argv and
    # replays a fixed selection (UO_FZF_STUB_CHOICE) with a fixed exit code
    # (UO_FZF_STUB_RC) — mimicking "user picked this line" / Esc (rc 130)
    cat > "$STUB_BIN/fzf" << 'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf '%s\n' "$@" > "${UO_FZF_STUB_ARGS:-/dev/null}"
printf '%s\n' "${UO_FZF_STUB_CHOICE:-}"
exit "${UO_FZF_STUB_RC:-0}"
EOF
    chmod +x "$STUB_BIN/fzf"
    # clear stub — deterministic menu rendering without a terminal
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/clear"
    chmod +x "$STUB_BIN/clear"

    # Copy-based minimal PATH WITHOUT fzf — deterministic on every host,
    # including machines where fzf IS installed (copies, not symlinks; the
    # tool list mirrors the proven health.bats NOSYS_BIN set)
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    cp "$STUB_BIN/clear" "$MIN_BIN/clear"
    local tool src
    for tool in bash env du cut find rm ls cat date sed awk grep head tail \
                wc sort tr mkdir chmod readlink dirname basename uname ps \
                locale sleep stty tput nproc; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$MIN_BIN/$tool"
    done

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/fzf.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# ---------- pure helper: the action list ----------

@test "_fzf_actions emits label|key lines for the main tools" {
    run _fzf_actions
    [ "$status" -eq 0 ]
    [ "$(grep -c '|' <<< "$output")" -ge 40 ]
    # a representative slice of the reused menu labels/keys
    [[ "$output" == *"System health snapshot|health_show"* ]]
    [[ "$output" == *"Disk cleanup|disk_cleanup"* ]]
    [[ "$output" == *"Boot time analysis (slowest units + verdict)|boot_show"* ]]
    [[ "$output" == *"Update everything (apt + snap + flatpak + tar.gz + github)|update_all"* ]]
    # every line carries the label|key shape
    local line
    while IFS= read -r line; do
        [[ "$line" == *"|"* ]] || fail "malformed line: $line"
    done <<< "$output"
    # no duplicate action keys
    [ -z "$(cut -d'|' -f2 <<< "$output" | sort | uniq -d)" ]
    # the warned dangerous tools stay behind their menu warning screens
    [[ "$output" != *"install_veet"* ]]
    [[ "$output" != *"reinstall_desktop"* ]]
}

@test "_fzf_actions keys all resolve to real dispatch targets" {
    # Source every module exactly like the entry script does (common.sh and
    # fzf.sh are already loaded by setup — sourcing them twice would trip
    # their readonly constants), so this check covers the real surface
    local f
    for f in "$TEST_HOME/uo-tree"/lib/*.sh; do
        case "${f##*/}" in
            common.sh|fzf.sh) continue ;;
        esac
        # shellcheck source=/dev/null
        source "$f"
    done
    local label key
    while IFS='|' read -r label key; do
        [ -n "$key" ] || fail "empty action key in: $label"
        declare -F "$key" > /dev/null || fail "action key is not a function: $key"
    done < <(_fzf_actions)
}

# ---------- function level: graceful absence & override ----------

@test "run_cli_fzf prints the install hint and exits 0 when fzf is missing" {
    # MIN_BIN has everything the toolkit needs EXCEPT fzf
    PATH="$MIN_BIN" run run_cli_fzf
    [ "$status" -eq 0 ]
    # exactly ONE friendly message with the exact install hint — no spam
    [ "$(grep -c "sudo apt install fzf" <<< "$output")" -eq 1 ]
    [[ "$output" != *"✗"* ]]
    [[ "$output" != *"not found"* ]]
}

@test "UO_FZF_BIN overrides the binary used by the launcher" {
    # fzf is absent from PATH entirely — only the override can find it
    UO_FZF_BIN="$STUB_BIN/fzf" \
    UO_FZF_STUB_CHOICE="Activity log|show_log" \
    PATH="$MIN_BIN" run run_cli_fzf
    [ "$status" -eq 0 ]
    # the real show_log ran: its header line, and the log-path branch the
    # header's own SECTION logging deterministically produces
    [[ "$output" == *"Activity log (last 60 lines)"* ]]
    [[ "$output" == *"Full path:"* ]]
}

# ---------- function level: the fzf UI contract ----------

@test "run_cli_fzf runs the picked read-only action via the menu dispatch" {
    UO_FZF_STUB_CHOICE="Activity log|show_log" PATH="$STUB_BIN:$PATH" run run_cli_fzf
    [ "$status" -eq 0 ]
    # the real show_log (lib/common.sh) ran — the same function the menu calls
    [[ "$output" == *"Activity log (last 60 lines)"* ]]
    [[ "$output" == *"Full path:"* ]]
}

@test "run_cli_fzf passes a helpful header to fzf" {
    UO_FZF_STUB_ARGS="$TEST_HOME/fzf-args" \
    UO_FZF_STUB_CHOICE="Activity log|show_log" \
    PATH="$STUB_BIN:$PATH" run run_cli_fzf
    [ "$status" -eq 0 ]
    local args
    args="$(cat "$TEST_HOME/fzf-args")"
    [[ "$args" == *"--header="* ]]
    [[ "$args" == *"Enter=run"* ]]
    [[ "$args" == *"Esc=cancel"* ]]
}

@test "run_cli_fzf cancels cleanly on Esc and on an empty selection" {
    # Esc: fzf exits 130 with no selection — clean exit 0, no output
    UO_FZF_STUB_RC=130 PATH="$STUB_BIN:$PATH" run run_cli_fzf
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    # empty selection with exit 0 — equally clean
    UO_FZF_STUB_RC=0 PATH="$STUB_BIN:$PATH" run run_cli_fzf
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "run_cli_fzf reports an unknown action key instead of guessing" {
    UO_FZF_STUB_CHOICE="Ghost entry|no_such_function_xyz" PATH="$STUB_BIN:$PATH" run run_cli_fzf
    [ "$status" -eq 0 ]
    [[ "$output" == *"Function 'no_such_function_xyz' not found — check the menu definition"* ]]
    # and nothing was executed
    [[ "$output" != *"Nothing has been logged yet"* ]]
}

# ---------- CLI level: uo --fzf ----------

@test "cli: --fzf dispatches the picked action (read-only show_log)" {
    UO_FZF_STUB_CHOICE="Activity log|show_log" \
    PATH="$STUB_BIN:$PATH" run run_uo --fzf
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI mode"* ]]
    [[ "$output" == *"Nothing has been logged yet"* ]]
    [[ "$output" == *"Finished — all requested tasks completed."* ]]
}

@test "cli: --fzf without fzf prints the hint and exits 0" {
    # MIN_BIN has everything the entry script needs EXCEPT fzf —
    # deterministic even on hosts that do have fzf installed
    PATH="$MIN_BIN" run run_uo --fzf
    [ "$status" -eq 0 ]
    [ "$(grep -c "sudo apt install fzf" <<< "$output")" -eq 1 ]
    # zero errors — the clean exit is proven by the success closing line
    [[ "$output" == *"Finished — all requested tasks completed."* ]]
}

@test "cli: --fzf cancels cleanly on Esc (no action runs)" {
    UO_FZF_STUB_RC=130 PATH="$STUB_BIN:$PATH" run run_uo --fzf
    [ "$status" -eq 0 ]
    [[ "$output" != *"Nothing has been logged yet"* ]]
    [[ "$output" != *"not found"* ]]
}

# ---------- menu level: main-menu entry 23 ----------

@test "menu entry 23 opens the fzf launcher and runs the picked action" {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/menus.sh"
    UO_FZF_STUB_CHOICE="Activity log|show_log" \
    PATH="$STUB_BIN:$PATH" run main_menu < <(printf '23\n\n0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"  23) 🚀 Interactive fzf menu (if installed)"* ]]
    [[ "$output" == *"Activity log (last 60 lines)"* ]]
    [[ "$output" == *"Goodbye"* ]]
}

@test "menu entry 23 with fzf missing prints the hint and returns to the menu" {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/menus.sh"
    PATH="$MIN_BIN" run main_menu < <(printf '23

0
')
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo apt install fzf"* ]]
    # the menu survived: back in the loop and exited normally on 0
    [[ "$output" == *"Goodbye"* ]]
}

# ---------- wiring: docs & completions ----------

@test "usage documents --fzf with UO_FZF_BIN and the install hint" {
    PATH="$STUB_BIN:$PATH" run run_uo --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fzf"* ]]
    [[ "$output" == *"UO_FZF_BIN"* ]]
    [[ "$output" == *"sudo apt install fzf"* ]]
}

@test "both completions list --fzf as a plain flag" {
    grep -q -- '--fzf' "$BATS_TEST_DIRNAME/../completions/uo"
    grep -q -- '--fzf' "$BATS_TEST_DIRNAME/../completions/_uo"
}
