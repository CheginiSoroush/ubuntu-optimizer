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
    printf '#!/usr/bin/env bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    printf '# shellcheck shell=bash\nfoo() { :; }\n' > "$SCRIPT_DIR/lib/a.sh"
    printf '# shellcheck shell=bash\nbar() { :; }\n' > "$SCRIPT_DIR/lib/b.sh"
    selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a missing main script" {
    printf '# shellcheck shell=bash\nfoo() { :; }\n' > "$SCRIPT_DIR/lib/a.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a main script with a syntax error" {
    printf '#!/usr/bin/env bash\nif then\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects a broken lib module" {
    printf '#!/usr/bin/env bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    printf 'fi fi (\n' > "$SCRIPT_DIR/lib/broken.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

@test "selfupdate_verify_tree rejects an empty lib directory" {
    printf '#!/usr/bin/env bash\necho hi\n' > "$SCRIPT_DIR/ubuntu-optimizer.sh"
    ! selfupdate_verify_tree "$SCRIPT_DIR"
}

# ---------- selfupdate_fetch_remote_version (stubbed curl) ----------

@test "selfupdate_fetch_remote_version parses the version from the main branch" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    # shellcheck disable=SC2016
    printf '#!/usr/bin/env bash\ncat <<'"'"'EOF'"'"'\nreadonly SCRIPT_VERSION="9.9"\nEOF\n' > "$stub/curl"
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
    printf '#!/usr/bin/env bash\ncase "$*" in *"/main/"*) exit 22 ;; esac\necho '"'"'readonly SCRIPT_VERSION="8.1"'"'"'\n' > "$stub/curl"
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
    printf '#!/usr/bin/env bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$SU_REMOTE_VERSION" ]
}

@test "selfupdate_fetch_remote_version fails when no version line is present" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\necho "not the file you want"\n' > "$stub/curl"
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
    printf '#!/usr/bin/env bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    local rc=0
    PATH="$stub:$PATH" selfupdate_fetch_remote_version || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$SU_REMOTE_VERSION" ]
    [ -z "$SU_REMOTE_BRANCH" ]
}

# ---------- selfupdate_cache_read / selfupdate_cache_write ----------

@test "selfupdate_cache_write then selfupdate_cache_read round-trips the check state" {
    selfupdate_cache_write 1700000000 9.9 main
    selfupdate_cache_read
    [ "$SU_CACHED_TS" = "1700000000" ]
    [ "$SU_CACHED_VERSION" = "9.9" ]
    [ "$SU_CACHED_BRANCH" = "main" ]
}

@test "selfupdate_cache_read fails cleanly on a missing or malformed cache" {
    ! selfupdate_cache_read
    [ -z "$SU_CACHED_VERSION" ]
    mkdir -p "$(dirname -- "$SU_AUTO_CACHE")"
    printf 'garbage-without-tabs\n' > "$SU_AUTO_CACHE"
    ! selfupdate_cache_read
    printf 'not-a-number\t9.9\tmain\n' > "$SU_AUTO_CACHE"
    ! selfupdate_cache_read
    [ -z "$SU_CACHED_VERSION" ]
    [ -z "$SU_CACHED_TS" ]
}

# ---------- selfupdate_auto_check — opt-outs ----------

@test "selfupdate_auto_check: the re-exec guard skips the check entirely" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    UO_AUTO_UPDATE_REEXEC=1
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check --report > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -f "$SU_AUTO_CACHE" ]
    [ ! -s "$out" ]
}

@test "selfupdate_auto_check: AUTO_UPDATE=0 (the --no-update flag) skips the check" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    AUTO_UPDATE=0
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -f "$SU_AUTO_CACHE" ]
    [ ! -s "$out" ]
}

@test "selfupdate_auto_check: UO_AUTO_UPDATE=0 skips the check" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    UO_AUTO_UPDATE=0
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -f "$SU_AUTO_CACHE" ]
    [ ! -s "$out" ]
}

@test "selfupdate_auto_check: a queued --self-update owns the flow (no auto check)" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=("self_update_interactive|self update")
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -f "$SU_AUTO_CACHE" ]
    [ ! -s "$out" ]
}

@test "selfupdate_auto_check: --timer-tick stays silent (scheduled run)" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=("timer_tick|monitor tick")
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -f "$SU_AUTO_CACHE" ]
    [ ! -s "$out" ]
}

# ---------- selfupdate_auto_check — version resolution ----------

@test "selfupdate_auto_check: up to date resolves silently through the cache" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    selfupdate_cache_write "$(date +%s)" "7.5" "main"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -s "$out" ]
}

@test "selfupdate_auto_check: a fresh cache satisfies the check without the network" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\necho CALLED > "%s/curl-called"\nexit 1\n' "$TEST_HOME" > "$stub/curl"
    chmod +x "$stub/curl"
    export PATH="$stub:$PATH"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    grep -q "Update available" "$out"
    grep -q "9.9" "$out"
    [ ! -f "$TEST_HOME/curl-called" ]
}

@test "selfupdate_auto_check: a stale cache triggers a network re-check and refresh" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    selfupdate_cache_write 1000000000 "7.5" "main"
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\necho '"'"'readonly SCRIPT_VERSION="9.9"'"'"'\n' > "$stub/curl"
    chmod +x "$stub/curl"
    export PATH="$stub:$PATH"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    grep -q "Update available" "$out"
    selfupdate_cache_read
    [ "$SU_CACHED_VERSION" = "9.9" ]
}

@test "selfupdate_auto_check: UO_UPDATE_CHECK_TTL=0 forces a network check past a fresh cache" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    UO_UPDATE_CHECK_TTL=0
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\necho '"'"'readonly SCRIPT_VERSION="8.8"'"'"'\n' > "$stub/curl"
    chmod +x "$stub/curl"
    export PATH="$stub:$PATH"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    grep -q "8.8" "$out"
    selfupdate_cache_read
    [ "$SU_CACHED_VERSION" = "8.8" ]
}

@test "selfupdate_auto_check: an unreachable network falls through silently" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    export PATH="$stub:$PATH"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -s "$out" ]
    [ ! -f "$SU_AUTO_CACHE" ]
}

# ---------- selfupdate_auto_check — announcement modes ----------

@test "selfupdate_auto_check: JSON mode keeps stdout pure and notices on stderr" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    JSON_MODE=1
    OUTPUT_FILE=""
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\necho CALLED > "%s/curl-called"\nexit 1\n' "$TEST_HOME" > "$stub/curl"
    chmod +x "$stub/curl"
    export PATH="$stub:$PATH"
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    grep -q "Update available" "$out"
    grep -q "uo --self-update" "$out"
    [ ! -f "$TEST_HOME/curl-called" ]
}

@test "selfupdate_auto_check: a piped run (no tty) only prints the notice" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    ASSUME_YES=0
    JSON_MODE=0
    OUTPUT_FILE=""
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    selfupdate_update_git() { echo "APPLIED-SHOULD-NOT-FIRE"; return 0; }
    selfupdate_reexec() { echo "REEXEC-SHOULD-NOT-FIRE"; }
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check --report > "$out" 2>&1 < /dev/null || rc=$?
    [ "$rc" -eq 0 ]
    grep -q "Update available" "$out"
    ! grep -q "APPLIED-SHOULD-NOT-FIRE" "$out"
    ! grep -q "REEXEC-SHOULD-NOT-FIRE" "$out"
}

# ---------- selfupdate_auto_check — apply and re-exec ----------

@test "selfupdate_auto_check: with -y it applies the update and re-execs with the original args" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    ASSUME_YES=1
    JSON_MODE=0
    OUTPUT_FILE=""
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    mkdir -p "$SCRIPT_DIR/.git"
    selfupdate_update_git() { SU_APPLIED="git"; return 0; }
    selfupdate_reexec() { SU_REEXEC_CALLED=1; SU_REEXEC_ARGS=("$*"); }
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check --report > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "${SU_APPLIED:-}" = "git" ]
    [ "${SU_REEXEC_CALLED:-}" = "1" ]
    [ "${SU_REEXEC_ARGS[*]}" = "--report" ]
}

@test "selfupdate_auto_check: a failed update falls through without the re-exec" {
    SCRIPT_VERSION="7.5"
    CLI_ACTIONS=()
    ASSUME_YES=1
    JSON_MODE=0
    OUTPUT_FILE=""
    warn() { echo "$*"; }
    selfupdate_cache_write "$(date +%s)" "9.9" "main"
    mkdir -p "$SCRIPT_DIR/.git"
    selfupdate_update_git() { return 1; }
    selfupdate_reexec() { echo "REEXEC-SHOULD-NOT-FIRE"; }
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_auto_check --report > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    ! grep -q "REEXEC-SHOULD-NOT-FIRE" "$out"
    grep -q "did not complete" "$out"
}

# ---------- selfupdate_update_git — auto mode guards ----------

@test "selfupdate_update_git: auto mode never touches a dirty working tree" {
    SCRIPT_DIR="$TEST_HOME/proj2"
    mkdir -p "$SCRIPT_DIR"
    git -C "$SCRIPT_DIR" init -q
    git -C "$SCRIPT_DIR" -c user.email=t@t -c user.name=t commit --allow-empty -q -m init
    echo dirty > "$SCRIPT_DIR/untracked.txt"
    SCRIPT_VERSION="7.5"
    SU_REMOTE_VERSION="9.9"
    SU_AUTO=1
    DRY_RUN=0
    warn() { echo "$*"; }
    confirm_action() { echo "PROMPT-SHOULD-NOT-FIRE"; return 0; }
    out="$TEST_HOME/out"
    local rc=0
    selfupdate_update_git > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
    ! grep -q "PROMPT-SHOULD-NOT-FIRE" "$out"
    grep -q "local changes" "$out"
    grep -q "uo --self-update" "$out"
}

# ---------- selfupdate_fetch_remote_version — quiet mode ----------

@test "selfupdate_fetch_remote_version: quiet mode fails silently" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    printf '#!/usr/bin/env bash\nexit 7\n' > "$stub/curl"
    chmod +x "$stub/curl"
    failure() { echo "FAIL-VISIBLE"; }
    out="$TEST_HOME/out"
    PATH="$stub:$PATH" SU_QUIET=1 selfupdate_fetch_remote_version > "$out" 2>&1 || true
    ! grep -q "FAIL-VISIBLE" "$out"
    PATH="$stub:$PATH" selfupdate_fetch_remote_version > "$out" 2>&1 || true
    grep -q "FAIL-VISIBLE" "$out"
}

@test "selfupdate_fetch_remote_version: quiet mode never triggers the curl installer" {
    stub="$TEST_HOME/bin"
    mkdir -p "$stub"
    # No curl anywhere on PATH; a sudo that would loudly record the install
    printf '#!/usr/bin/env bash\necho APT-CALLED > "%s/apt-called"\n' "$TEST_HOME" > "$stub/sudo"
    chmod +x "$stub/sudo"
    out="$TEST_HOME/out"
    local rc=0
    PATH="$stub" SU_QUIET=1 selfupdate_fetch_remote_version > "$out" 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
    [ ! -f "$TEST_HOME/apt-called" ]
    [ ! -s "$out" ]
}
