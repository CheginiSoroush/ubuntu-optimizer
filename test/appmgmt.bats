#!/usr/bin/env bats
# ============================================================
#   test/appmgmt.bats — unit tests for the shared app helpers
#   (lib/targz.sh, lib/appmgmt.sh, lib/github.sh)
#
#   HOME is redirected to a temp sandbox BEFORE sourcing, so the
#   registry/GitHub db paths point into the sandbox — the user's
#   real data is never touched.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # shellcheck source=../lib/common.sh
    source "$BATS_TEST_DIRNAME/../lib/common.sh"
    # shellcheck source=../lib/targz.sh
    source "$BATS_TEST_DIRNAME/../lib/targz.sh"
    # shellcheck source=../lib/appmgmt.sh
    source "$BATS_TEST_DIRNAME/../lib/appmgmt.sh"
    # shellcheck source=../lib/github.sh
    source "$BATS_TEST_DIRNAME/../lib/github.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- sanitize_app_name (lib/targz.sh) ----------

@test "sanitize_app_name strips characters that are not allowed in paths" {
    run sanitize_app_name "../my app!!"
    [ "$output" = "myapp" ]
}

@test "sanitize_app_name keeps letters digits dashes and underscores" {
    run sanitize_app_name "My-App_42"
    [ "$output" = "My-App_42" ]
}

# ---------- desktop entry escaping (lib/targz.sh + lib/appmgmt.sh) ----------

@test "desktop_escape_path and _desktop_exec_path round-trip spaces and parens" {
    local original="/opt/My App (x64)/bin/my app"
    local escaped desktop
    escaped=$(desktop_escape_path "$original")
    desktop="$TEST_HOME/app.desktop"
    printf 'Exec=%s\n' "$escaped" > "$desktop"
    run _desktop_exec_path "$desktop"
    [ "$output" = "$original" ]
}

# ---------- GitHub app database (lib/github.sh) ----------

@test "gh_db_add registers an app and gh_db_has finds it" {
    gh_db_add myapp "owner/repo" "v1.2.3"
    gh_db_has myapp
    [ "$(wc -l < "$GITHUB_DB")" -eq 1 ]
}

@test "gh_db_add replaces an existing entry instead of duplicating" {
    gh_db_add myapp "owner/repo" "v1.0"
    gh_db_add myapp "owner/repo" "v2.0"
    [ "$(wc -l < "$GITHUB_DB")" -eq 1 ]
    grep -q 'v2.0' "$GITHUB_DB"
}

@test "gh_db_remove deletes only the named entry" {
    gh_db_add appA "owner/repoA" "v1.0"
    gh_db_add appB "owner/repoB" "v1.0"
    gh_db_remove appA
    ! gh_db_has appA
    gh_db_has appB
    [ "$(wc -l < "$GITHUB_DB")" -eq 1 ]
}
