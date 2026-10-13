#!/usr/bin/env bats
# ============================================================
#   test/browserclean.bats — tests for the browser cache cleanup
#   (lib/browserclean.sh — the only writing monitor feature)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   CLI level runs the real entry script with --browser-clean
#   against a fake XDG_CACHE_HOME tree (chromium family, Firefox
#   profile, thumbnails) and a stubbed pgrep, so "which browser is
#   running" is deterministic. DRY_RUN, the running-browser guard,
#   the flatpak variant and the "data is never touched" guarantees
#   are all exercised. Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Targeted copy: ubuntu-optimizer.sh + lib/*.sh only — a full-tree cp
    # would drag website/node_modules (~700 MB when present) and stall tests
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    # Fake cache tree root — the module must never look outside it
    CACHE="$TEST_HOME/xdg-cache"
    export XDG_CACHE_HOME="$CACHE"

    # Stub binaries — by default no browser is running
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    write_pgrep_stub_off
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

write_pgrep_stub_off() {
    cat > "$STUB_BIN/pgrep" << 'EOF'
#!/usr/bin/env bash
# default stub: no browser process is running
exit 1
EOF
    chmod +x "$STUB_BIN/pgrep"
}

# Build the fake browser cache tree — real (non-sparse) bytes so the
# du -sm arithmetic is deterministic
build_cache_tree() {
    mkdir -p "$CACHE/google-chrome/Default/Cache" \
             "$CACHE/google-chrome/Default/Code Cache" \
             "$CACHE/google-chrome/Default/GPUCache" \
             "$CACHE/mozilla/firefox/abc123.default/cache2" \
             "$CACHE/mozilla/firefox/abc123.default/startupCache" \
             "$CACHE/thumbnails"
    dd if=/dev/zero of="$CACHE/google-chrome/Default/Cache/blob.bin" bs=1M count=2 2> /dev/null
    echo x > "$CACHE/google-chrome/Default/Cookies"                 # decoy: user data
    dd if=/dev/zero of="$CACHE/mozilla/firefox/abc123.default/cache2/entry" bs=1M count=2 2> /dev/null
    echo x > "$CACHE/mozilla/firefox/abc123.default/places.sqlite"  # decoy: profile data
    dd if=/dev/zero of="$CACHE/thumbnails/thumb.png" bs=1M count=1 2> /dev/null
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_browserclean() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/browserclean.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- CLI level: the happy path ----------

@test "cli: --browser-clean -y empties the cache contents but keeps the directories" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -d "$CACHE/google-chrome/Default/Cache" ]
    [ -z "$(ls -A "$CACHE/google-chrome/Default/Cache")" ]
    [ -z "$(ls -A "$CACHE/mozilla/firefox/abc123.default/cache2")" ]
    [[ "$output" == *"Total freed"* ]]
}

@test "cli: browser data files and the Firefox profile directory survive" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -f "$CACHE/google-chrome/Default/Cookies" ]
    [ -f "$CACHE/mozilla/firefox/abc123.default/places.sqlite" ]
    [ -d "$CACHE/mozilla/firefox/abc123.default" ]
    [[ "$output" == *"bookmarks, passwords, cookies and history are never touched"* ]]
}

@test "cli: thumbnails are emptied and the directory stays" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -d "$CACHE/thumbnails" ]
    [ -z "$(ls -A "$CACHE/thumbnails")" ]
    [[ "$output" == *"Thumbnails cleaned"* ]]
}

@test "cli: the freed MB is reported per browser and in total" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"google-chrome cleaned — freed 2 MB"* ]]
    [[ "$output" == *"Firefox cleaned — freed 2 MB"* ]]
    [[ "$output" == *"Total freed: 5 MB"* ]]
}

# ---------- CLI level: DRY_RUN ----------

@test "cli: DRY_RUN reports the sizes and deletes nothing" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean --dry-run -y
    [ "$status" -eq 0 ]
    [ -f "$CACHE/google-chrome/Default/Cache/blob.bin" ]
    [ -f "$CACHE/mozilla/firefox/abc123.default/cache2/entry" ]
    [ -f "$CACHE/thumbnails/thumb.png" ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"Nothing has been deleted"* ]]
}

# ---------- CLI level: the running-browser guard ----------

@test "cli: a running chrome is skipped while firefox still gets cleaned" {
    build_cache_tree
    cat > "$STUB_BIN/pgrep" << 'EOF'
#!/usr/bin/env bash
# chrome is "running", everything else is not
for a in "$@"; do
    [ "$a" = "chrome" ] && exit 0
done
exit 1
EOF
    chmod +x "$STUB_BIN/pgrep"
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -f "$CACHE/google-chrome/Default/Cache/blob.bin" ]   # chrome cache untouched
    [ -z "$(ls -A "$CACHE/mozilla/firefox/abc123.default/cache2")" ]
    [[ "$output" == *"running — its cache is skipped for safety"* ]]
}

@test "cli: a missing pgrep skips every browser but thumbnails still get cleaned" {
    build_cache_tree
    # Mirror the standard tool PATH but WITHOUT pgrep: the tools the run
    # actually needs are COPIED into a private bin dir (symlinks are not
    # available in every environment), pgrep alone is left out — so the
    # script runs normally and `command -v pgrep` genuinely fails.
    # Expected: owned caches (chrome, firefox) are skipped — "cannot verify
    # = do not touch" — while thumbnails, which have no owning process to
    # verify in the first place, still get cleaned.
    MIN_BIN="$TEST_HOME/min-bin"
    mkdir -p "$MIN_BIN"
    local tool src
    for tool in bash env du cut find rm ls cat date sed awk grep head tail \
                wc sort tr mkdir chmod readlink dirname basename uname ps \
                locale sleep stty tput; do
        src="$(command -v "$tool" 2> /dev/null)" || continue
        [ -x "$src" ] && cp "$src" "$MIN_BIN/$tool"
    done
    PATH="$MIN_BIN" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -f "$CACHE/google-chrome/Default/Cache/blob.bin" ]
    [ -f "$CACHE/mozilla/firefox/abc123.default/cache2/entry" ]
    [ -d "$CACHE/thumbnails" ]
    [ -z "$(ls -A "$CACHE/thumbnails")" ]
    [[ "$output" == *"google-chrome is running — its cache is skipped for safety"* ]]
    [[ "$output" == *"Firefox is running — its cache is skipped for safety"* ]]
    [[ "$output" == *"Thumbnails cleaned"* ]]
    [[ "$output" == *"Total freed: 1 MB"* ]]
}

# ---------- CLI level: confirmation + edge cases ----------

@test "cli: declining the confirmation deletes nothing" {
    build_cache_tree
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean < /dev/null
    [ "$status" -eq 0 ]
    [ -f "$CACHE/google-chrome/Default/Cache/blob.bin" ]
    [ -f "$CACHE/thumbnails/thumb.png" ]
    [[ "$output" == *"Cancelled"* ]]
}

@test "cli: the flatpak variant cache is cleaned too" {
    build_cache_tree
    FLAT="$TEST_HOME/.var/app/com.google.Chrome/cache/google-chrome/Default/Cache"
    mkdir -p "$FLAT"
    dd if=/dev/zero of="$FLAT/flatblob.bin" bs=1M count=2 2> /dev/null
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [ -d "$FLAT" ]
    [ -z "$(ls -A "$FLAT")" ]
    [[ "$output" == *"google-chrome (flatpak)"* ]]
}

@test "cli: no browser caches at all degrades to an info line" {
    mkdir -p "$CACHE"
    PATH="$STUB_BIN:$PATH" run run_uo --browser-clean -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"No browser cache directories found"* ]]
}
