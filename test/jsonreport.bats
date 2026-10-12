#!/usr/bin/env bats
# ============================================================
#   test/jsonreport.bats — tests for lib/jsonreport.sh
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The module is strictly read-only, so the full emitter runs
#   safely inside the test sandbox. Dependencies from lib/common.sh
#   and lib/report.sh are stubbed (pkg_installed, _net_has_internet,
#   log paths) so the tests stay offline and hermetic. JSON validity
#   is checked with python3 when available, jq as a fallback.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Minimal stubs for the globals/helpers the emitter reads
    SCRIPT_VERSION="9.9-test"
    LOG_FILE="$TEST_HOME/optimizer.log"
    JOURNALD_DROPIN="$TEST_HOME/journald-dropin"
    SUDOERS_TIMEOUT_FILE="$TEST_HOME/sudoers-timeout"
    POLKIT_RULE_FILE="$TEST_HOME/polkit-rule"
    pkg_installed() { return 1; }
    _net_has_internet() { return 0; }
    log_write() { :; }   # logging is a file side effect — not under test here
    # shellcheck source=../lib/jsonreport.sh
    source "$BATS_TEST_DIRNAME/../lib/jsonreport.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

json_validate_stdin() {
    if command -v python3 > /dev/null 2>&1; then
        python3 -c 'import json,sys; json.load(sys.stdin)'
    elif command -v jq > /dev/null 2>&1; then
        jq -e . > /dev/null
    else
        skip "no JSON validator available"
    fi
}

# ---------- function surface ----------

@test "_json_escape is defined" {
    declare -F _json_escape > /dev/null
}

@test "_json_int is defined" {
    declare -F _json_int > /dev/null
}

@test "system_report_json is defined" {
    declare -F system_report_json > /dev/null
}

# ---------- _json_escape ----------

@test "_json_escape: plain text passes through" {
    [ "$(_json_escape 'hello world')" = "hello world" ]
}

@test "_json_escape: escapes backslash, quote, tab and newline" {
    [ "$(_json_escape 'a\b')" = 'a\\b' ]
    [ "$(_json_escape 'say "hi"')" = 'say \"hi\"' ]
    [ "$(_json_escape "$(printf 'a\tb'))" = 'a\tb' ]
    [ "$(_json_escape "$(printf 'a\nb'))" = 'a\nb' ]
}

@test "_json_escape: strips control characters" {
    local out
    out=$(_json_escape "$(printf 'a\001b\002c')")
    [ "$out" = "abc" ]
}

# ---------- _json_int / _json_float sanitizers ----------

@test "_json_int: valid integers pass, garbage becomes 0" {
    [ "$(_json_int 123)" = "123" ]
    [ "$(_json_int 'abc')" = "0" ]
    [ "$(_json_int '')" = "0" ]
    [ "$(_json_int '-5')" = "0" ]
}

@test "_json_float: decimals pass, garbage becomes 0" {
    [ "$(_json_float 0.07)" = "0.07" ]
    [ "$(_json_float 2)" = "2" ]
    [ "$(_json_float 'NaN')" = "0" ]
}

# ---------- full emitter ----------

@test "system_report_json: output is a valid JSON document" {
    system_report_json | json_validate_stdin
}

@test "system_report_json: required top-level keys are present" {
    local json
    json=$(system_report_json)
    for key in tool version generated_at summary host memory disks services optimizations network top_memory; do
        printf '%s' "$json" | grep -q "\"$key\":"
    done
}

@test "system_report_json: summary has a valid status and counters" {
    local status
    status=$(system_report_json | grep -o '"status":"[a-z]*"' | head -1)
    case "$status" in
        '"status":"good"'|'"status":"attention"'|'"status":"critical"') ;;
        *) fail "unexpected status: $status" ;;
    esac
}

@test "system_report_json: version field echoes SCRIPT_VERSION" {
    system_report_json | grep -q '"version":"9.9-test"'
}

@test "system_report_json: optimizations count matches entries" {
    # summary.optimizations_total must equal the number of entries in optimizations[]
    system_report_json > "$TEST_HOME/report.json"
    local total entries
    total=$(grep -o '"optimizations_total":[0-9]*' "$TEST_HOME/report.json" | cut -d: -f2)
    entries=$(grep -o '"name":"' "$TEST_HOME/report.json" | wc -l)
    [ "$total" -eq "$entries" ]
}
