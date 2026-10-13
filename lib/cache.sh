# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/cache.sh
# ───────────────────────────────────────────────────────────────────────────────
#  A tiny TTL cache for costly operations. Some steps are expensive and
#  their result does not change within minutes: probing internet
#  connectivity (up to ~10 s of timeouts), refreshing apt lists (~seconds)
#  or asking the GitHub API for release metadata (60 requests/hour per IP
#  without a token). This module stores those results on disk with an
#  expiry timestamp so repeated runs within the TTL skip the cost.
#
#  Design:
#    • One file per key under $CACHE_DIR; line 1 is the expiry epoch,
#      lines 2+ hold the cached value (multi-line values are preserved).
#    • Every write is atomic (tmp file + mv) — a concurrent reader never
#      sees a half-written entry.
#    • Reads go through cache_lookup, which returns the value in the
#      _CACHE_VALUE variable instead of on stdout. Command substitution
#      $(cache_get …) would run the reader in a subshell and silently
#      lose the hit/miss session counters — the variable contract keeps
#      every counter update in the caller's shell.
#    • Only the toolkit's own observations are cached, and only when the
#      producing command itself succeeded. Nothing here ever changes
#      system state — a stale entry can only cost one redundant refresh,
#      never a wrong action.
#    • Deliberately NOT cached: package installation state (pkg_installed
#      answers change the moment this tool installs something, and the
#      invalidation surface would span every install site).
#
#  Control:
#    • CLI:      --no-cache | --cache-clear | --cache-stats
#    • Config:   NO_CACHE=0|1 in ~/.config/uo/config.conf
#    • Env:      UO_NO_CACHE=1 (same effect, per invocation)
#    Precedence follows lib/config.sh: defaults < config < env < CLI.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

CACHE_DIR="$REGISTRY_DIR/cache"
CACHE_HITS=0     # session statistics for the session summary
CACHE_MISSES=0
CACHE_WRITES=0
# Environment seed — the config file (lib/config.sh) only fills the gap
# when UO_NO_CACHE is unset, and an explicit --no-cache always wins.
NO_CACHE="${UO_NO_CACHE:-0}"

# ───────────────────────────────────────────────────────────────────────────────
# _cache_key_is_safe() — allow only a conservative cache-key charset
#
# Keys become file names. Restricting them to letters, digits and . _ - :
# makes path traversal and shell metacharacters impossible by construction.
#
# Arguments: $1 — cache key
# Returns:   0 — safe; 1 — rejected
# ───────────────────────────────────────────────────────────────────────────────
_cache_key_is_safe() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]
}

# ───────────────────────────────────────────────────────────────────────────────
# _cache_now() — current epoch seconds, pure Bash
#
# Arguments: none
# Returns:   0 — epoch is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
_cache_now() {
    printf '%(%s)T' -1
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_lookup() — read a fresh cached value into _CACHE_VALUE
#
# Reads the entry file when caching is enabled and compares the expiry
# epoch on line 1 against the current time. On a hit the value (everything
# after line 1) is exported through the _CACHE_VALUE global so callers in
# the parent shell can use it WITHOUT command substitution — wrapping this
# function in $(…) would run it in a subshell and lose the session's
# hit/miss counters. An expired entry is deleted immediately so the cache
# never accumulates stale files.
#
# Globals:   CACHE_DIR, NO_CACHE, CACHE_HITS, CACHE_MISSES (read/write)
#            _CACHE_VALUE (written — "" on every miss)
# Arguments: $1 — cache key
# Returns:   0 — hit; _CACHE_VALUE holds the value
#            1 — miss (disabled, unknown, expired or unreadable)
# ───────────────────────────────────────────────────────────────────────────────
cache_lookup() {
    _CACHE_VALUE=""
    if [ "$NO_CACHE" = "1" ] || ! _cache_key_is_safe "$1"; then
        CACHE_MISSES=$((CACHE_MISSES + 1))
        return 1
    fi
    local file="$CACHE_DIR/$1" expiry
    if [ ! -r "$file" ]; then
        CACHE_MISSES=$((CACHE_MISSES + 1))
        return 1
    fi
    expiry=$(head -n 1 "$file" 2>/dev/null)
    if ! [[ "$expiry" =~ ^[0-9]+$ ]] || [ "$expiry" -le "$(_cache_now)" ]; then
        rm -f "$file" 2>/dev/null
        CACHE_MISSES=$((CACHE_MISSES + 1))
        return 1
    fi
    CACHE_HITS=$((CACHE_HITS + 1))
    _CACHE_VALUE=$(tail -n +2 "$file" 2>/dev/null)
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_set() — store a value under a key with a time-to-live
#
# Writes atomically: the payload (expiry line + value) first lands in a
# unique temp file inside the cache directory, then replaces the entry
# with a single mv. Writes are skipped entirely when caching is disabled
# (--no-cache / NO_CACHE=1) so a bypassed run leaves no traces behind.
# An empty value is valid — callers may cache "nothing to report".
#
# Globals:   CACHE_DIR, NO_CACHE, CACHE_WRITES (read/write)
# Arguments: $1 — cache key;  $2 — value (may be multi-line/empty)
#            $3 — TTL in seconds (positive integer)
# Returns:   0 — stored (or skipped by design when disabled)
#            1 — invalid key or TTL, or the cache dir is not writable
# ───────────────────────────────────────────────────────────────────────────────
cache_set() {
    if ! _cache_key_is_safe "$1"; then
        warn "cache: rejecting unsafe key: $1"
        return 1
    fi
    if ! [[ "$3" =~ ^[1-9][0-9]*$ ]]; then
        warn "cache: rejecting non-positive TTL: $3"
        return 1
    fi
    [ "$NO_CACHE" = "1" ] && return 0
    if ! mkdir -p "$CACHE_DIR" 2>/dev/null || [ ! -w "$CACHE_DIR" ]; then
        return 1
    fi
    local file="$CACHE_DIR/$1" tmp="$CACHE_DIR/$1.tmp.$$" now expiry
    now=$(_cache_now)
    expiry=$((now + $3))
    { printf '%s\n' "$expiry"; printf '%s' "$2"; } > "$tmp" 2>/dev/null || {
        rm -f "$tmp" 2>/dev/null
        return 1
    }
    if ! mv -f "$tmp" "$file" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        return 1
    fi
    CACHE_WRITES=$((CACHE_WRITES + 1))
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_delete() — drop a single entry
#
# Arguments: $1 — cache key
# Returns:   0 — always (a missing entry counts as deleted)
# ───────────────────────────────────────────────────────────────────────────────
cache_delete() {
    _cache_key_is_safe "$1" || return 0
    rm -f "$CACHE_DIR/$1" 2>/dev/null
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_clear() — remove every cache entry
#
# Deletes the whole cache directory; the next cache_set recreates it.
# Cache files are pure optimization artifacts, so this is always safe —
# at worst the next runs re-pay one apt update / connectivity probe.
#
# Globals:   CACHE_DIR (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
cache_clear() {
    rm -rf "$CACHE_DIR" 2>/dev/null
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_entry_count() — number of stored entries
#
# Arguments: none
# Returns:   0 — the count is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
cache_entry_count() {
    local n=0
    # find instead of ls|grep (SC2010): counts every entry that is not a tmp part
    [ -d "$CACHE_DIR" ] && n=$(find "$CACHE_DIR" -maxdepth 1 -mindepth 1 ! -name '*.tmp.*' 2>/dev/null | wc -l) || true
    printf '%s' "$n"
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_maintenance_clear() — CLI action behind --cache-clear
#
# Clears the cache and reports how many entries were removed. Queued like
# any other action, so it composes: `uo --cache-clear --update-apt`
# force-refreshes the apt lists in one run.
#
# Globals:   CACHE_DIR (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
cache_maintenance_clear() {
    header "Clear the TTL Cache"
    local n word="entries"
    n=$(cache_entry_count)
    [ "$n" = "1" ] && word="entry"
    cache_clear
    success "Cache cleared — $n $word removed."
    info "Cache location: $CACHE_DIR"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# cache_maintenance_stats() — CLI action behind --cache-stats
#
# Read-only introspection: lists every entry with its size and the time
# left before expiry, then the session's hit/miss counters. Never creates
# the cache directory — with no cache the answer is simply "empty".
#
# Globals:   CACHE_DIR, NO_CACHE, CACHE_HITS, CACHE_MISSES (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
cache_maintenance_stats() {
    header "TTL Cache Statistics"
    if [ "$NO_CACHE" = "1" ]; then
        info "Caching is disabled for this run (--no-cache)."
    fi
    if [ ! -d "$CACHE_DIR" ]; then
        info "Cache is empty — no entries yet."
        info "Cache location: $CACHE_DIR"
        return 0
    fi
    local file base expiry now size left total=0
    now=$(_cache_now)
    printf '   %-28s %8s %12s\n' "ENTRY" "BYTES" "EXPIRES IN"
    for file in "$CACHE_DIR"/*; do
        [ -f "$file" ] || continue
        base=$(basename "$file")
        [[ "$base" == *.tmp.* ]] && continue
        expiry=$(head -n 1 "$file" 2>/dev/null)
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total=$((total + size))
        if [[ "$expiry" =~ ^[0-9]+$ ]] && [ "$expiry" -gt "$now" ]; then
            left=$((expiry - now))
            if [ "$left" -ge 3600 ]; then
                printf '   %-28s %8s %9sm\n' "$base" "$size" "$((left / 60))"
            else
                printf '   %-28s %8s %9ss\n' "$base" "$size" "$left"
            fi
        else
            printf '   %-28s %8s %12s\n' "$base" "$size" "expired"
        fi
    done
    printf '   %-28s %8s\n' "total" "$total"
    echo ""
    info "Hits this session: $CACHE_HITS · misses: $CACHE_MISSES"
    info "Force-refresh a run: uo --no-cache · wipe: uo --cache-clear"
    return 0
}
# REWRITE-TEST
