#!/usr/bin/env bats
# ============================================================
#   test/common.bats — unit tests for lib/common.sh
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   HOME is redirected to a temp sandbox BEFORE sourcing common.sh,
#   so registry/log paths point into the sandbox — the user's real
#   data is never touched.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # shellcheck source=../lib/common.sh
    source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- constants ----------

@test "SCRIPT_VERSION is defined and non-empty" {
    [ -n "$SCRIPT_VERSION" ]
}

# ---------- name/version helpers ----------

@test "normalize_name lowercases and strips non-alphanumerics" {
    run normalize_name "AB-Download Manager"
    [ "$output" = "abdownloadmanager" ]
}

@test "normalize_name is the identity on already-normal input" {
    run normalize_name "lazygit"
    [ "$output" = "lazygit" ]
}

@test "guess_version extracts a dotted version from a .tar.gz name" {
    run guess_version "lazygit_0.65.1_Linux_x86_64.tar.gz"
    [ "$output" = "0.65.1" ]
}

@test "guess_version handles the .tgz suffix" {
    run guess_version "someapp-1.2.3.tgz"
    [ "$output" = "1.2.3" ]
}

@test "guess_version returns empty when the name has no version" {
    run guess_version "someapp.tar.gz"
    [ -z "$output" ]
}

@test "name_from_archive strips version and platform tokens" {
    run name_from_archive "lazygit_0.65.1_Linux_x86_64.tar.gz"
    [ "$output" = "lazygit" ]
}

@test "name_from_archive keeps only the app word" {
    run name_from_archive "bleachbit-6.0.4-linux.tar.gz"
    [ "$output" = "bleachbit" ]
}

@test "name_from_archive strips the v prefix of a version" {
    run name_from_archive "App-v1.2.3-linux-amd64.tar.gz"
    [ "$output" = "app" ]
}

@test "name_from_archive handles the tgz suffix and nested paths" {
    run name_from_archive "/long/path/MyTool-v2.10.1-linux-x64.tar.gz"
    [ "$output" = "mytool" ]
}

@test "name_from_archive strips case-insensitive platform tokens" {
    run name_from_archive "app-1.2.3-STABLE-release.tar.gz"
    [ "$output" = "app" ]
}

# ---------- version comparison ----------

@test "_ver_gt accepts a strictly newer version" {
    run _ver_gt "1.10.0" "1.9.9"
    [ "$status" -eq 0 ]
}

@test "_ver_gt handles multi-digit minor versions correctly" {
    run _ver_gt "2.0" "1.99"
    [ "$status" -eq 0 ]
    run _ver_gt "1.9" "1.10"
    [ "$status" -ne 0 ]
}

@test "_ver_gt rejects equal versions" {
    run _ver_gt "1.2.3" "1.2.3"
    [ "$status" -ne 0 ]
}

@test "_ver_gt rejects an older or empty candidate" {
    run _ver_gt "1.2.2" "1.2.3"
    [ "$status" -ne 0 ]
    run _ver_gt "" "1.2.3"
    [ "$status" -ne 0 ]
    run _ver_gt "1.2.3" ""
    [ "$status" -ne 0 ]
}

@test "derive_install_root strips a trailing bin directory" {
    run derive_install_root "/opt/myapp/bin/myapp"
    [ "$output" = "/opt/myapp" ]
}

@test "derive_install_root keeps a non-bin parent as-is" {
    run derive_install_root "/opt/myapp/myapp"
    [ "$output" = "/opt/myapp" ]
}

# ---------- output helpers ----------

@test "_strip_ansi removes color escape sequences" {
    run _strip_ansi "$(printf 'a\033[31mred\033[0mb')"
    [ "$output" = "aredb" ]
}

@test "success increments LOG_OK_COUNT and writes an OK log line" {
    success "it works"
    [ "$LOG_OK_COUNT" -eq 1 ]
    grep -q '\] OK' "$LOG_FILE"
}

@test "failure increments LOG_FAIL_COUNT and writes an ERROR log line" {
    failure "it broke"
    [ "$LOG_FAIL_COUNT" -eq 1 ]
    grep -q '\] ERROR' "$LOG_FILE"
}

@test "confirm_action auto-confirms under ASSUME_YES" {
    ASSUME_YES=1
    run confirm_action "Proceed?"
    [ "$status" -eq 0 ]
}

# ---------- registry (sandboxed HOME) ----------

@test "registry_add writes a single 6-field line" {
    registry_add myapp 1.2.3 /opt/myapp /opt/myapp/myapp /usr/share/applications/myapp.desktop myapp.tar.gz
    [ "$(wc -l < "$REGISTRY_DB")" -eq 1 ]
    [ "$(awk -F'|' '{print NF}' "$REGISTRY_DB")" -eq 6 ]
    [ "$(awk -F'|' '{print $1}' "$REGISTRY_DB")" = "myapp" ]
}

@test "registry_add replaces an existing entry instead of duplicating" {
    registry_add myapp 1.0 /opt/myapp a b c
    registry_add myapp 2.0 /opt/myapp a b c
    [ "$(grep -c '^myapp|' "$REGISTRY_DB")" -eq 1 ]
    [ "$(awk -F'|' '$1 == "myapp" {print $2}' "$REGISTRY_DB")" = "2.0" ]
}

@test "registry_remove deletes only the named entry" {
    registry_add appA 1.0 /opt/a a a a
    registry_add appB 1.0 /opt/b a a a
    registry_remove appA
    [ "$(wc -l < "$REGISTRY_DB")" -eq 1 ]
    [ "$(awk -F'|' '{print $1}' "$REGISTRY_DB")" = "appB" ]
}

@test "registry_remove on an empty registry is a no-op" {
    run registry_remove ghost
    [ "$status" -eq 0 ]
    [ ! -f "$REGISTRY_DB" ]
}

# ---------- log system ----------

@test "log_write appends a timestamped line with the level" {
    log_write "INFO" "hello world"
    [ -f "$LOG_FILE" ]
    grep -q '\] INFO' "$LOG_FILE"
    grep -q 'hello world' "$LOG_FILE"
}

# ---------- system helpers ----------

@test "pkg_installed accepts an installed package" {
    run pkg_installed bash
    [ "$status" -eq 0 ]
}

@test "pkg_installed rejects a nonexistent package" {
    run pkg_installed definitely-not-a-real-package-xyz
    [ "$status" -ne 0 ]
}

# ---------- dry-run mode ----------

@test "sudo wrapper intercepts mutations in dry-run mode" {
    DRY_RUN=1
    run sudo rm -rf /tmp/uo-dryrun-should-not-exist
    [ "$status" -eq 0 ]
    [ ! -e /tmp/uo-dryrun-should-not-exist ]
    grep -q '\[dry-run\] sudo rm' "$LOG_FILE"
}

# ---------- sudo pre-authentication ----------

@test "sudo_precheck is a no-op in dry-run mode" {
    DRY_RUN=1
    run sudo_precheck
    [ "$status" -eq 0 ]
}
