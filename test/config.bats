#!/usr/bin/env bats
# ============================================================
#   test/config.bats — tests for the config file system
#   (--config / --no-config / --config-show / --config-example)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The config loader lives in lib/config.sh and is wired into
#   the main parser (ubuntu-optimizer.sh), so these tests execute
#   the real CLI with a temp HOME. --config-show is read-only,
#   so every scenario is safe and fully offline. Precedence is
#   the core contract: defaults < config file < environment
#   (UO_DNS_SERVERS) < explicit CLI flags.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # CI runners export XDG_CONFIG_HOME (=/home/runner/.config) — it would
    # override HOME-based resolution inside lib/config.sh and break hermeticity
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    # Targeted copy: ubuntu-optimizer.sh + lib/*.sh only — a full-tree cp
    # would drag website/node_modules (~700 MB when present) and stall tests
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
    CONFIG_DIR="$TEST_HOME/.config/uo"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" "$@"
}

write_config() {
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$1" > "$CONFIG_DIR/config.conf"
}

# ---------- --config-show basics ----------

@test "--config-show exits 0 and lists every tracked key" {
    run run_uo --config-show
    [ "$status" -eq 0 ]
    for key in ASSUME_YES NO_COLOR NO_LOG DRY_RUN DNS_SERVERS; do
        [[ "$output" == *"$key="* ]]
    done
}

@test "--config-show without a config file reports 'not found' and defaults" {
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found — defaults in use"* ]]
    [[ "$output" == *"ASSUME_YES=0 (default)"* ]]
    [[ "$output" == *"DNS_SERVERS=8.8.8.8 1.1.1.1 (default)"* ]]
}

@test "XDG_CONFIG_HOME overrides the config directory" {
    # the documented XDG support: when set, it wins over $HOME/.config
    local xdg="$TEST_HOME/xdg"
    mkdir -p "$xdg/uo"
    printf '%s\n' 'ASSUME_YES=1' > "$xdg/uo/config.conf"
    # the HOME-based location stays empty on purpose — only XDG can find it
    run env XDG_CONFIG_HOME="$xdg" bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"$xdg/uo/config.conf (applied)"* ]]
    [[ "$output" == *"ASSUME_YES=1 (config)"* ]]
}

@test "--config-show reports the applied path and source 'config'" {
    write_config 'ASSUME_YES=1'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"$CONFIG_DIR/config.conf (applied)"* ]]
    [[ "$output" == *"ASSUME_YES=1 (config)"* ]]
}

# ---------- precedence: config file ----------

@test "config file values apply: booleans and quoted DNS are accepted" {
    write_config 'ASSUME_YES=1
NO_LOG=1
DNS_SERVERS="1.1.1.1 9.9.9.9"'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASSUME_YES=1 (config)"* ]]
    [[ "$output" == *"NO_LOG=1 (config)"* ]]
    [[ "$output" == *"DNS_SERVERS=1.1.1.1 9.9.9.9 (config)"* ]]
}

@test "comments, blank lines and indented KEY=VALUE are handled" {
    write_config '# a comment

   DRY_RUN=1'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY_RUN=1 (config)"* ]]
}

# ---------- precedence: CLI flags beat config ----------

@test "explicit -y beats the config file (source cli, value 1)" {
    write_config 'ASSUME_YES=1'
    run run_uo --config-show -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASSUME_YES=1 (cli)"* ]]
}

@test "-y applies (source cli) even when no config file exists" {
    run run_uo --config-show -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASSUME_YES=1 (cli)"* ]]
}

# ---------- precedence: environment beats config ----------

@test "exported UO_DNS_SERVERS beats the DNS_SERVERS config key" {
    write_config 'DNS_SERVERS="1.1.1.1 9.9.9.9"'
    UO_DNS_SERVERS="9.9.9.9" run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"DNS_SERVERS=9.9.9.9 (env)"* ]]
}

# ---------- --no-config / --config FILE ----------

@test "--no-config ignores the config file entirely" {
    write_config 'ASSUME_YES=1'
    run run_uo --config-show --no-config
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled with --no-config"* ]]
    [[ "$output" == *"ASSUME_YES=0 (default)"* ]]
}

@test "--config FILE uses the alternative file" {
    local alt="$TEST_HOME/alt.conf"
    printf 'DRY_RUN=1\n' > "$alt"
    run run_uo --config-show --config "$alt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$alt (applied)"* ]]
    [[ "$output" == *"DRY_RUN=1 (config)"* ]]
}

@test "--config with a missing file is rejected" {
    run run_uo --config-show --config "$TEST_HOME/missing.conf"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Config file not found"* ]]
}

@test "--config without an argument is rejected" {
    run run_uo --config
    [ "$status" -eq 1 ]
    [[ "$output" == *"--config requires a file path"* ]]
}

# ---------- validation and error reporting ----------

@test "unknown keys are warned about and skipped, run still exits 0" {
    write_config 'BOGUS_KEY=1
ASSUME_YES=1'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid value for BOGUS_KEY"* ]]
    [[ "$output" == *"ASSUME_YES=1 (config)"* ]]
}

@test "malformed lines report the line number and are skipped" {
    write_config 'this is not KEY=VALUE'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"config: skipping line 1 (not KEY=VALUE)"* ]]
}

@test "invalid boolean values are rejected (not silently applied)" {
    write_config 'ASSUME_YES=yes
DRY_RUN=maybe'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid value for ASSUME_YES: yes"* ]]
    [[ "$output" == *"invalid value for DRY_RUN: maybe"* ]]
    [[ "$output" == *"ASSUME_YES=0 (default)"* ]]
    [[ "$output" == *"DRY_RUN=0 (default)"* ]]
}

@test "invalid DNS_SERVERS values are rejected" {
    write_config 'DNS_SERVERS="not an ip"'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid value for DNS_SERVERS"* ]]
    [[ "$output" == *"DNS_SERVERS=8.8.8.8 1.1.1.1 (default)"* ]]
}

# ---------- functional effect ----------

@test "NO_LOG=1 from the config really suppresses the log file" {
    write_config 'NO_LOG=1'
    run run_uo --report
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_HOME/.local/state/ubuntu-optimizer" ]
}

# ---------- --config-example ----------

@test "--config-example prints an annotated, fully commented template" {
    run run_uo --config-example
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASSUME_YES=0"* ]]
    [[ "$output" == *"DNS_SERVERS="* ]]
    [[ "$output" == *"$XDG_CONFIG_HOME"* || "$output" == *"XDG_CONFIG_HOME"* ]]
    # Every content line is a comment — redirecting it cannot change behavior
    while IFS= read -r line; do
        [ -z "$line" ] || [[ "$line" == \#* ]] || fail "uncommented line in template: $line"
    done <<< "$output"
}

@test "--config-example exits before doing anything else (safe with other flags)" {
    run run_uo --config-example
    [ "$status" -eq 0 ]
    [[ "$output" == *"user configuration"* ]]
}
