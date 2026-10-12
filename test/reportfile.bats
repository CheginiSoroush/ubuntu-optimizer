#!/usr/bin/env bats
# ============================================================
#   test/reportfile.bats — tests for the --output/--append flags
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The report destination flags live in the main script parser
#   (ubuntu-optimizer.sh), so these tests execute the real CLI
#   with a copied tree in a temp HOME. Everything exercised here
#   is read-only (--report family), so the runs are safe and
#   fully offline; JSON validity is checked with python3 when
#   available, jq as a fallback.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Fresh copy of the whole toolkit — the main script requires lib/ beside it
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
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

run_uo() {
    bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# ---------- validation ----------

@test "--output without --report is rejected" {
    run run_uo --output "$TEST_HOME/out.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--output is only valid together with --report."* ]]
}

@test "--append without --output is rejected" {
    run run_uo --append
    [ "$status" -eq 1 ]
    [[ "$output" == *"--append is only valid together with --output."* ]]
}

@test "--output with a missing file argument is rejected" {
    run run_uo --report --output
    [ "$status" -eq 1 ]
    [[ "$output" == *"--output requires a file path"* ]]
}

@test "--output pointing into a non-writable directory is rejected" {
    local rodir="$TEST_HOME/ro"
    mkdir -p "$rodir"
    chmod 555 "$rodir"
    run run_uo --report --json --output "$rodir/out.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot write to file"* ]]
    [ ! -e "$rodir/out.json" ]
}

# ---------- writing ----------

@test "--report --json --output writes one valid JSON document, stdout stays clean" {
    local out="$TEST_HOME/out.json"
    run run_uo --report --json --output "$out"
    [ "$status" -eq 0 ]
    # JSON mode must keep stdout pure (only a stderr hint about the file)
    [ -z "$output" ]
    [ -s "$out" ]
    json_validate_stdin < "$out"
    grep -q '"tool":"ubuntu-optimizer"' "$out"
    grep -q '"generated_at"' "$out"
}

@test "--report (plain text) --output writes the human report to the file" {
    local out="$TEST_HOME/report.txt"
    run run_uo --report --output "$out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Report saved to: $out"* ]]
    [ -s "$out" ]
    grep -q "System Status Report" "$out"
}

@test "--output truncates by default: two runs leave exactly one document" {
    local out="$TEST_HOME/out.json"
    run run_uo --report --json --output "$out"
    [ "$status" -eq 0 ]
    run run_uo --report --json --output "$out"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$out")" -eq 1 ]
}

@test "--append builds a JSONL time-series: one line per run, each valid JSON" {
    local out="$TEST_HOME/report-log.jsonl"
    run run_uo --report --json --append --output "$out"
    [ "$status" -eq 0 ]
    run run_uo --report --json --append --output "$out"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$out")" -eq 2 ]
    # every line is a self-contained report document
    while IFS= read -r line; do
        printf '%s' "$line" | json_validate_stdin
        printf '%s' "$line" | grep -q '"generated_at"'
    done < "$out"
    # timestamps are monotonic — the sleep between the two runs guarantees
    # the second document is strictly newer
    local t1 t2
    t1=$(sed -n '1p' "$out" | grep -o '"generated_at":"[^"]*"' | cut -d'"' -f4)
    t2=$(sed -n '2p' "$out" | grep -o '"generated_at":"[^"]*"' | cut -d'"' -f4)
    [[ "$t2" > "$t1" ]]
}

@test "--append never truncates existing content (plain file untouched)" {
    local out="$TEST_HOME/keep.jsonl"
    printf 'PRECIOUS\n' > "$out"
    run run_uo --report --json --append --output "$out"
    [ "$status" -eq 0 ]
    head -n 1 "$out" | grep -q "PRECIOUS"
}
