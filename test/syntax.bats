#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "all shell scripts pass bash -n" {
  for f in "$ROOT"/ubuntu-optimizer.sh "$ROOT"/install.sh "$ROOT"/lib/*.sh "$ROOT"/completions/uo; do
    run bash -n "$f"
    [ "$status" -eq 0 ] || { echo "syntax error in $f: $output"; return 1; }
  done
}

@test "shellcheck reports no warnings" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck -S warning "$ROOT"/ubuntu-optimizer.sh "$ROOT"/install.sh "$ROOT"/lib/*.sh "$ROOT"/completions/uo
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
