#!/usr/bin/env bats
# ============================================================
#   test/selfupdate.bats — unit tests for lib/selfupdate.sh
#   (added in v7.6: `uo --self-update`)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Fully offline: the version comparison, tree verification,
#   checkout detection and remote-version parsing are exercised
#   directly; the network-facing update flows are stubbed via a
#   fake curl on PATH where needed.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # CI runners export XDG_* — force HOME-based paths for hermeticity
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    SCRIPT_DIR="$TEST_HOME/fake-project"
    mkdir -p "$SCRIPT_DIR/lib"
    # lib/selfupdate.sh expects the shared helpers from lib/common.sh —
    # stub them so the offline tests stay quiet and self-contained
    warn()    { :; }
    info()    { :; }
    success() { :; }
    failure() { :; }
    ok()      { :; }
    header()  { :; }
    confirm_action() { return 0; }
    # shellcheck source=../lib/selfupdate.sh
    source "$BATS_TEST_DIRNAME/../lib/selfupdate.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- selfupdate_version_newer ----------

@test "selfupdate_version_newer: 7.6 is newer than 7.5" {
    selfupdate_version_newer 7.6 7.5
}

@test "selfupdate_version_newer: 7.10 is newer than 7.9 (numeric, not lexical)" {
    selfupdate_version_newer 7.10 7.9
}

@test "selfupdate_version_newer: 8.0 is newer than 7.9.9" {
    selfupdate_version_newer 8.0 7.9.9
}

@test "selfupdate_version_newer: equal versions are not newer" {
    ! selfupdate_version_newer 7.5 7.5
}

@test "selfupdate_version_newer: older versions are not newer" {
    ! selfupdate_version_newer 7.5 7.6
    ! selfupdate_version_newer 7.9 7.10
}

@test "selfupdate_version_newer: empty input is never newer" {
    ! selfupdate_version_newer "" 7.5
    ! selfupdate_version_newer 7.6 ""
}

# ---------- selfupdate_is_git_checkout ----------

@test "selfupdate_is_git_checkout detects a .git directory" {
    mkdir -p "$SCRIPT_DIR/.git"
    selfupdate_is_git_checkout "$SCRIPT_DIR"
}

@test "selfupdate_is_git_checkout rejects a static copy" {
    ! selfupdate_is_git_checkout "$SCRIPT_DIR"
}

# ---------- selfupdate_verify_tree ----------

@test "selfupdate_verify_tree accepts a healthy tree" {
    printf '#!/bin/bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    printf '# shellcheck shell=bash\nfoo() { :; }\n' > "$SCRIPT_DIR/lib/a.sh"
    printf '# shellcheck shell=bash\nbar() { :; }\n' > "$SCRIPT_DIR/lib/b.sh"
    selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a missing main script" {
    printf '# shellcheck shell=bash\nfoo() { :; }\n' > "$SCRIPT_DIR/lib/a.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a main script with a syntax error" {
    printf '#!/bin/bash\nif then\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a broken lib module" {
    printf '#!/bin/bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    printf 'fi fi (\n' > "$SCRIPT_DIR/lib/broken.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects an empty lib directory" {
    printf '#!/bin/bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

# ---------- selfupdate_fetch_remote_version (stubbed curl) ----------

@test "selfupdate_fetch_remote_version parses the version from the main branch" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    # shellcheck disable=SC2016
    printf '#!/bin/bash\ncat <<'"'"'EOF'"'"'\nreadonly SCRIPT_VERSION="9.9"\nEOF\n' > "$stub/curl"
    chmod +x "$stub/curl"
    # direct call with an errexit-safe rc capture — SU_REMOTE_VERSION/
    # SU_REMOTE_BRANCH are globals that real bats' subshell `run` would hide
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SU_REMOTE_VERSION" = "9.9" ]
    [ "$SU_REMOTE_BRANCH" = "main" ]
}

@test "selfupdate_fetch_remote_version falls back to the master branch" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    # Fail when the URL contains /main/, succeed otherwise (404 simulation)
    printf '#!/bin/bash\ncase "$*" in *"/main/"*) exit 22 ;; esac\necho '"'"'readonly SCRIPT_VERSION="8.1"'"'"'\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 0 ]
    [ "$SU_REMOTE_VERSION" = "8.1" ]
    [ "$SU_REMOTE_BRANCH" = "master" ]
}

@test "selfupdate_fetch_remote_version fails when both branches fail" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/bin/bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$SU_REMOTE_VERSION" ]
}

@test "selfupdate_fetch_remote_version fails when no version line is present" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/bin/bash\necho "not the file you want"\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 1 ]
}

@test "selfupdate_fetch_remote_version never leaks a stale version on failure" {
    SU_REMOTE_VERSION="0.0"
    SU_REMOTE_BRANCH="old"
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/bin/bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$SU_REMOTE_VERSION" ]
    [ -z "$SU_REMOTE_BRANCH" ]
}
