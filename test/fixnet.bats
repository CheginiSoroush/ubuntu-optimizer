#!/usr/bin/env bats
# ============================================================
#   test/fixnet.bats — tests for the VPN-repair script module
#   (lib/fixnet.sh)
#
#   HOME points into a temp sandbox, so ~/fix-network.sh and the
#   shell rc files are written inside the sandbox only. The
#   generated repair script is never executed (it would restart
#   NetworkManager) — it is validated with bash -n and content
#   checks; run_fixnet's exit-status propagation is exercised
#   with throwaway stub scripts at the same path.
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
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_fixnet() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/fixnet.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: script generation ----------

@test "create_fixnet_script writes an executable bilingual repair script" {
    load_fixnet
    run create_fixnet_script
    [ "$status" -eq 0 ]
    [ -x "$HOME/fix-network.sh" ]
    [ "$(head -n 1 "$HOME/fix-network.sh")" = "#!/bin/bash" ]
    grep -q "Fix Network Script v2.2" "$HOME/fix-network.sh"
    grep -q 'MSG_START="Starting network repair process..."' "$HOME/fix-network.sh"
    grep -q 'MSG_SUCCESS="اتصال به اینترنت برقرار است!"' "$HOME/fix-network.sh"
    grep -q "systemctl restart NetworkManager" "$HOME/fix-network.sh"
    [[ "$output" == *"fixnet script created"* ]]
}

@test "the generated fixnet script is syntactically valid bash" {
    load_fixnet
    create_fixnet_script > /dev/null 2>&1
    run bash -n "$HOME/fix-network.sh"
    [ "$status" -eq 0 ]
}

@test "create_fixnet_script registers the fixnet alias once in existing rc files" {
    load_fixnet
    printf '# my bashrc\n' > "$HOME/.bashrc"
    printf '# my zshrc\n' > "$HOME/.zshrc"
    create_fixnet_script > /dev/null 2>&1
    [ "$(grep -c 'alias fixnet=' "$HOME/.bashrc")" -eq 1 ]
    [ "$(grep -c 'alias fixnet=' "$HOME/.zshrc")" -eq 1 ]
    create_fixnet_script > /dev/null 2>&1          # second run must not duplicate
    [ "$(grep -c 'alias fixnet=' "$HOME/.bashrc")" -eq 1 ]
    [ "$(grep -c 'alias fixnet=' "$HOME/.zshrc")" -eq 1 ]
}

# ---------- function level: run_fixnet ----------

@test "run_fixnet without the script fails with creation guidance" {
    load_fixnet
    run run_fixnet
    [ "$status" -eq 1 ]
    [[ "$output" == *"has not been created yet"* ]]
}

@test "run_fixnet propagates the repair script's exit status" {
    load_fixnet
    printf '#!/usr/bin/env bash\necho "network up"\n' > "$HOME/fix-network.sh"
    chmod +x "$HOME/fix-network.sh"
    run run_fixnet
    [ "$status" -eq 0 ]
    [[ "$output" == *"network up"* ]]
    printf '#!/usr/bin/env bash\nexit 3\n' > "$HOME/fix-network.sh"
    run run_fixnet
    [ "$status" -eq 1 ]
    [[ "$output" == *"finished with errors"* ]]
}

# ---------- CLI level ----------

@test "cli: --fixnet creates the script inside the sandbox HOME" {
    run run_uo --fixnet
    [ "$status" -eq 0 ]
    [ -x "$TEST_HOME/fix-network.sh" ]
    grep -q "Fix Network Script v2.2" "$TEST_HOME/fix-network.sh"
    [[ "$output" == *"fixnet script created"* ]]
}
