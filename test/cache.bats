#!/usr/bin/env bats
# ============================================================
#   test/cache.bats — tests for the TTL cache (lib/cache.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The cache module is exercised both at function level
#   (sourced into the test shell with a temp HOME) and through
#   the real CLI (--cache-stats / --cache-clear / --no-cache and
#   the report flow that stores the connectivity verdict).
#   Everything runs fully offline: network-dependent probes are
#   replaced by stub functions with call counters.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    cp -r "$BATS_TEST_DIRNAME/.." "$TEST_HOME/uo-tree"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
    CACHE_DIR="$TEST_HOME/.local/share/ubuntu-optimizer/cache"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" "$@"
}

# Load only the modules a cache test needs, into the test shell
load_cache() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/cache.sh"
}

# ---------- CLI maintenance actions ----------

@test "--cache-stats on an empty cache exits 0 and reports empty" {
    run run_uo --cache-stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache is empty"* ]]
}

@test "--cache-clear on an empty cache exits 0 and reports 0 entries" {
    run run_uo --cache-clear
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 entries removed"* ]]
}

@test "--cache-clear then --cache-stats compose in one run" {
    run run_uo --cache-clear --cache-stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cache cleared"* ]]
    [[ "$output" == *"Cache is empty"* ]]
}

@test "--report stores the connectivity verdict in the cache" {
    run run_uo --report
    [ "$status" -eq 0 ]
    [ -f "$CACHE_DIR/net:internet" ]
    local expiry
    expiry=$(head -n 1 "$CACHE_DIR/net:internet")
    [[ "$expiry" =~ ^[0-9]+$ ]]
    # expiry must lie in the future (TTL 60–120 s)
    local now
    now=$(date +%s)
    [ "$expiry" -gt "$now" ]
}

@test "a second --report run serves the verdict from the cache" {
    run run_uo --report
    [ "$status" -eq 0 ]
    run run_uo --report --cache-stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hits this session: 1"* ]]
    [[ "$output" == *"⚡ Cache: 1 hit(s)"* ]]
}

@test "--no-cache bypasses reads and writes (nothing is stored)" {
    run run_uo --no-cache --report --cache-stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"Caching is disabled for this run"* ]]
    # the read missed and the write was skipped — the summary counts one miss
    [[ "$output" == *"⚡ Cache: 0 hit(s), 1 miss(es)"* ]]
    # the write is skipped too — the cache dir must not exist afterwards
    [ ! -f "$CACHE_DIR/net:internet" ]
}

@test "UO_NO_CACHE=1 behaves like --no-cache" {
    UO_NO_CACHE=1 run run_uo --report --cache-stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚡ Cache: 0 hit(s), 1 miss(es)"* ]]
    [ ! -f "$CACHE_DIR/net:internet" ]
}

@test "expired entries are skipped by the CLI run" {
    run run_uo --report
    [ "$status" -eq 0 ]
    # force the stored verdict into the past
    local now
    now=$(date +%s)
    sed -i "1s/.*/$((now - 10))/" "$CACHE_DIR/net:internet"
    run run_uo --report --cache-stats
    [ "$status" -eq 0 ]
    # expired → miss (and the probe re-stores a fresh verdict afterwards,
    # so the entry exists again with a future expiry)
    [[ "$output" == *"Hits this session: 0"* ]]
}

# ---------- function level: lookup / set semantics ----------

@test "cache_set + cache_lookup round-trips a multi-line value" {
    load_cache
    local value
    value=$(printf 'alpha\nbeta\ngamma')
    run cache_set "test:multi" "$value" 60
    [ "$status" -eq 0 ]
    cache_lookup "test:multi"
    [ "$?" -eq 0 ]
    [ "$_CACHE_VALUE" = "$value" ]
}

@test "cache_lookup on an unknown key misses with empty _CACHE_VALUE" {
    load_cache
    _CACHE_VALUE="stale-from-elsewhere"
    run cache_lookup "test:nothing"
    [ "$status" -eq 1 ]
    [ -z "$_CACHE_VALUE" ]
    [ "$CACHE_MISSES" -eq 1 ]
    [ "$CACHE_HITS" -eq 0 ]
}

@test "cache_lookup counts a fresh hit in the parent shell" {
    load_cache
    cache_set "test:hit" "v" 60
    cache_lookup "test:hit"
    [ "$CACHE_HITS" -eq 1 ]
    [ "$CACHE_MISSES" -eq 0 ]
}

@test "an expired entry misses and is deleted on read" {
    load_cache
    cache_set "test:old" "v" 60
    local now
    now=$(date +%s)
    sed -i "1s/.*/$((now - 5))/" "$CACHE_DIR/test:old"
    run cache_lookup "test:old"
    [ "$status" -eq 1 ]
    [ ! -f "$CACHE_DIR/test:old" ]
    [ "$CACHE_MISSES" -eq 1 ]
}

@test "unsafe keys are rejected by both set and lookup" {
    load_cache
    run cache_set "../evil" "v" 60
    [ "$status" -eq 1 ]
    run cache_set "a/b" "v" 60
    [ "$status" -eq 1 ]
    run cache_set "" "v" 60
    [ "$status" -eq 1 ]
    run cache_lookup "a/b"
    [ "$status" -eq 1 ]
    # nothing landed on disk outside the cache dir
    [ ! -e "$TEST_HOME/.local/share/ubuntu-optimizer/evil" ]
}

@test "non-positive and non-numeric TTLs are rejected" {
    load_cache
    run cache_set "test:t0" "v" 0
    [ "$status" -eq 1 ]
    run cache_set "test:tneg" "v" -5
    [ "$status" -eq 1 ]
    run cache_set "test:tabc" "v" abc
    [ "$status" -eq 1 ]
    [ ! -d "$CACHE_DIR" ] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]
}

@test "NO_CACHE=1 skips writes but still returns success" {
    load_cache
    NO_CACHE=1
    run cache_set "test:off" "v" 60
    [ "$status" -eq 0 ]
    [ ! -f "$CACHE_DIR/test:off" ]
    run cache_lookup "test:off"
    [ "$status" -eq 1 ]
    [ "$CACHE_MISSES" -eq 1 ]
    [ "$CACHE_WRITES" -eq 0 ]
}

@test "UO_NO_CACHE env var seeds NO_CACHE at source time" {
    UO_NO_CACHE=1 load_cache
    [ "$NO_CACHE" = "1" ]
}

@test "cache_delete removes exactly one entry" {
    load_cache
    cache_set "test:d1" "v" 60
    cache_set "test:d2" "v" 60
    cache_delete "test:d1"
    [ ! -f "$CACHE_DIR/test:d1" ]
    [ -f "$CACHE_DIR/test:d2" ]
    # unsafe keys are ignored, not deleted wildly
    run cache_delete "../evil"
    [ "$status" -eq 0 ]
}

@test "cache_clear wipes everything and cache_entry_count reports it" {
    load_cache
    cache_set "test:c1" "v" 60
    cache_set "test:c2" "v" 60
    [ "$(cache_entry_count)" = "2" ]
    cache_clear
    [ "$(cache_entry_count)" = "0" ]
}

# ---------- function level: wired call sites ----------

@test "update_apt skips the refresh within the TTL and re-runs with NO_CACHE" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/snapflatpak.sh"
    APT_CALLS="$TEST_HOME/apt-calls"
    sudo() {
        if [ "$1" = "apt" ]; then
            echo "apt $2" >> "$APT_CALLS"
            return 0
        fi
        return 0
    }
    : > "$APT_CALLS"
    update_apt > /dev/null 2>&1
    [[ "$(cat "$APT_CALLS")" == *"apt update"* ]]
    # second run within the TTL — the refresh is skipped
    : > "$APT_CALLS"
    update_apt > /dev/null 2>&1
    ! grep -q "apt update" "$APT_CALLS"
    grep -q "apt upgrade" "$APT_CALLS"
    grep -q "apt autoremove" "$APT_CALLS"
    # NO_CACHE forces a fresh refresh
    NO_CACHE=1
    : > "$APT_CALLS"
    update_apt > /dev/null 2>&1
    grep -q "apt update" "$APT_CALLS"
}

@test "update_apt with a failing apt update caches nothing and fails" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/snapflatpak.sh"
    sudo() {
        if [ "$2" = "update" ]; then
            return 100
        fi
        return 0
    }
    run update_apt
    [ "$status" -eq 1 ]
    [ ! -f "$CACHE_DIR/apt:lists" ]
}

@test "the connectivity verdict is cached across two probe calls" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/report.sh"
    PROBE_CALLS="$TEST_HOME/probe-calls"
    _net_has_internet_probe() {
        echo "probe" >> "$PROBE_CALLS"
        return 0
    }
    : > "$PROBE_CALLS"
    _net_has_internet; [ "$?" -eq 0 ]
    _net_has_internet; [ "$?" -eq 0 ]
    [ "$(wc -l < "$PROBE_CALLS")" -eq 1 ]
    [ -f "$CACHE_DIR/net:internet" ]
}

@test "an offline verdict is cached too (short TTL, probe runs once)" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/report.sh"
    PROBE_CALLS="$TEST_HOME/probe-calls"
    _net_has_internet_probe() {
        echo "probe" >> "$PROBE_CALLS"
        return 1
    }
    : > "$PROBE_CALLS"
    _net_has_internet; [ "$?" -eq 1 ]
    _net_has_internet; [ "$?" -eq 1 ]
    [ "$(wc -l < "$PROBE_CALLS")" -eq 1 ]
    # the stored verdict is "0"
    local v
    v=$(tail -n +2 "$CACHE_DIR/net:internet")
    [ "$v" = "0" ]
}

@test "gh_fetch_latest caches release JSON (curl runs once for two calls)" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/github.sh"
    CURL_CALLS="$TEST_HOME/curl-calls"
    curl() {
        echo "call" >> "$CURL_CALLS"
        printf '%s' '{"tag_name": "v9.9.9", "assets": [{"browser_download_url": "https://example.com/app-1.0.tar.gz"}]}'
    }
    : > "$CURL_CALLS"
    gh_fetch_latest "owner/repo" > /dev/null 2>&1
    [ "$?" -eq 0 ]
    [ "$GH_TAG" = "v9.9.9" ]
    # second call must be served from the cache — curl is NOT called again
    curl() {
        echo "must-not-run" >> "$CURL_CALLS"
        return 7
    }
    gh_fetch_latest "owner/repo" > /dev/null 2>&1
    [ "$?" -eq 0 ]
    [ "$GH_TAG" = "v9.9.9" ]
    [ "$(wc -l < "$CURL_CALLS")" -eq 1 ]
}

@test "gh_fetch_latest does not cache API error responses" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/github.sh"
    CURL_CALLS="$TEST_HOME/curl-calls"
    curl() {
        echo "call" >> "$CURL_CALLS"
        printf '%s' '{"message": "Not Found", "documentation_url": "https://docs.github.com"}'
    }
    : > "$CURL_CALLS"
    run gh_fetch_latest "owner/repo"
    [ "$status" -eq 1 ]
    run gh_fetch_latest "owner/repo"
    [ "$status" -eq 1 ]
    # the error response was NOT cached — curl ran twice
    [ "$(wc -l < "$CURL_CALLS")" -eq 2 ]
}

@test "gh_fetch_latest cache keys never collide across repositories" {
    load_cache
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/github.sh"
    # the stub cannot see the real URL, so key the payload off the repo name
    curl() {
        case "$_UO_FAKE_REPO" in
            alpha) printf '%s' '{"tag_name": "v1.0.0", "assets": []}' ;;
            beta)  printf '%s' '{"tag_name": "v2.0.0", "assets": []}' ;;
        esac
    }
    _UO_FAKE_REPO=alpha
    gh_fetch_latest "acme/alpha" > /dev/null 2>&1
    [ "$GH_TAG" = "v1.0.0" ]
    _UO_FAKE_REPO=beta
    gh_fetch_latest "acme/beta" > /dev/null 2>&1
    [ "$GH_TAG" = "v2.0.0" ]
    # both entries exist side by side
    [ -f "$CACHE_DIR/gh:latest:acme::alpha" ]
    [ -f "$CACHE_DIR/gh:latest:acme::beta" ]
    # and a repeat of the first still returns its own tag
    _UO_FAKE_REPO=alpha
    gh_fetch_latest "acme/alpha" > /dev/null 2>&1
    [ "$GH_TAG" = "v1.0.0" ]
}

# ---------- session summary ----------

@test "the session summary shows the cache line after a cached run" {
    run run_uo --report
    [ "$status" -eq 0 ]
    run run_uo --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚡ Cache: 1 hit(s), 0 miss(es)"* ]]
}

@test "the session summary has no cache line when nothing was cached" {
    run run_uo --cache-stats
    [ "$status" -eq 0 ]
    ! grep -q "⚡ Cache:" <<< "$output"
}
