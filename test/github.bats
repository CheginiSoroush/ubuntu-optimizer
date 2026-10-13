#!/usr/bin/env bats
# ============================================================
#   test/github.bats — unit tests for the SHA-256 verification
#   helpers in lib/github.sh (added in v7.4)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Fully offline: only the pure detection/parsing functions are
#   exercised (gh_is_checksum_asset, gh_extract_expected_hash);
#   the network-facing gh_verify_checksum is not tested here.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # lib/github.sh builds GITHUB_DB from REGISTRY_DIR at source time
    REGISTRY_DIR="$TEST_HOME/.local/share/ubuntu-optimizer"
    # lib/github.sh expects the shared logging helpers from lib/common.sh —
    # stub them so the offline tests stay quiet and self-contained
    warn()    { :; }
    info()    { :; }
    success() { :; }
    failure() { :; }
    # shellcheck source=../lib/github.sh
    source "$BATS_TEST_DIRNAME/../lib/github.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- gh_is_checksum_asset ----------

@test "gh_is_checksum_asset accepts common checksum file names" {
    for f in SHA256SUMS sha256sums.txt checksums.txt fzf_checksums.txt \
             app-v1.2.tar.gz.sha256 app.deb.sha256sum app.sha256sum.txt app.dgst; do
        gh_is_checksum_asset "$f"
    done
}

@test "gh_is_checksum_asset rejects installable payloads" {
    ! gh_is_checksum_asset "app-1.2.3-amd64.deb"
    ! gh_is_checksum_asset "app.AppImage"
    ! gh_is_checksum_asset "app.tar.gz"
    ! gh_is_checksum_asset "app.tgz"
    ! gh_is_checksum_asset "checksum"          # singular is not a checksum LIST
    ! gh_is_checksum_asset ""
}

@test "gh_is_checksum_asset is case-insensitive" {
    gh_is_checksum_asset "Sha256Sums.TXT"
    gh_is_checksum_asset "PROJECT_CHECKSUMS.txt"
}

# ---------- gh_extract_expected_hash ----------

@test "gh_extract_expected_hash parses sha256sum format (two spaces)" {
    f="$TEST_HOME/ck"
    printf 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  app-1.0.tar.gz\n' > "$f"
    run gh_extract_expected_hash "$f" "app-1.0.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "gh_extract_expected_hash parses binary-marker format (asterisk)" {
    f="$TEST_HOME/ck"
    printf 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 *app-1.0.tar.gz\n' > "$f"
    run gh_extract_expected_hash "$f" "app-1.0.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "gh_extract_expected_hash picks the right entry in a multi-file list" {
    f="$TEST_HOME/ck"
    printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.deb\nbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  app-1.0.tar.gz\ncccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc  third.AppImage\n' > "$f"
    run gh_extract_expected_hash "$f" "app-1.0.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}

@test "gh_extract_expected_hash parses OpenSSL .dgst style (SHA2-256(name)= hash)" {
    f="$TEST_HOME/app.tar.gz.dgst"
    printf 'MD5(app.tar.gz)= 5d41402abc4b2a76b9719d911017c592\nSHA2-256(app.tar.gz)= 1111111111111111111111111111111111111111111111111111111111111111\nSHA2-512(app.tar.gz)= deadbeef\n' > "$f"
    run gh_extract_expected_hash "$f" "app.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "1111111111111111111111111111111111111111111111111111111111111111" ]
}

@test "gh_extract_expected_hash parses a bare single-hash .sha256 file" {
    f="$TEST_HOME/app.tar.gz.sha256"
    printf '2222222222222222222222222222222222222222222222222222222222222222\n' > "$f"
    run gh_extract_expected_hash "$f" "app.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "2222222222222222222222222222222222222222222222222222222222222222" ]
}

@test "gh_extract_expected_hash returns 1 when the target is not listed" {
    f="$TEST_HOME/ck"
    printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.deb\n' > "$f"
    run gh_extract_expected_hash "$f" "app.tar.gz"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "list without the target must NOT fall back to another file's hash" {
    # regression: the bare-hash fallback used to pick the single hex token
    # from a name-based list that simply did not contain our file
    f="$TEST_HOME/ck"
    printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  other.deb\n' > "$f"
    run gh_extract_expected_hash "$f" "app.tar.gz"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "gh_extract_expected_hash rejects malformed hash lengths" {
    f="$TEST_HOME/ck"
    printf '%s  app.tar.gz\n' "$(printf 'a%.0s' {1..63})" > "$f"   # 63 hex chars
    run gh_extract_expected_hash "$f" "app.tar.gz"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "gh_extract_expected_hash matches hash case-insensitively via uppercase input" {
    f="$TEST_HOME/ck"
    printf 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855  app-1.0.tar.gz\n' > "$f"
    run gh_extract_expected_hash "$f" "app-1.0.tar.gz"
    [ "$status" -eq 0 ]
    [ "$output" = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855" ]
}

@test "gh_verify_checksum is defined and honors UO_SKIP_CHECKSUM" {
    declare -F gh_verify_checksum > /dev/null
    UO_SKIP_CHECKSUM=1 gh_verify_checksum "x.tar.gz" "/nonexistent" "$TEST_HOME"
}

# ---------- v7.12: resilient API layer (retry / backoff / rate limit) ----------
# gh_api_get is exercised against a stub curl on PATH that replays a scripted
# sequence of responses (one "code|headers|body" line per call); sleep is
# stubbed to record delays without actually waiting. Every stub script line
# is emitted through its own single-quoted printf argument so no quote
# nesting can leak into the generated script.

@test "gh_backoff_secs doubles per attempt: 1, 2, 4" {
    run gh_backoff_secs 1
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run gh_backoff_secs 2
    [ "$output" = "2" ]
    run gh_backoff_secs 3
    [ "$output" = "4" ]
}

@test "gh_backoff_secs honors the UO_GH_BACKOFF_MAX cap" {
    run env UO_GH_BACKOFF_MAX=3 bash -c 'source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"; gh_backoff_secs 5'
    [ "$output" = "3" ]
    run env UO_GH_BACKOFF_MAX=8 bash -c 'source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"; gh_backoff_secs 10'
    [ "$output" = "8" ]
}

@test "gh_backoff_secs sanitizes junk attempts to the safe minimum 1" {
    run gh_backoff_secs "garbage"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run gh_backoff_secs ""
    [ "$output" = "1" ]
}

@test "gh_retry_after_secs parses integer Retry-After (CRLF-safe)" {
    f="$TEST_HOME/hdrs"
    printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: 7\r\nX-Other: v\r\n' > "$f"
    run gh_retry_after_secs "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "gh_retry_after_secs is case-insensitive and ignores junk values" {
    f="$TEST_HOME/hdrs"
    printf 'RETRY-AFTER: 12\r\n' > "$f"
    run gh_retry_after_secs "$f"
    [ "$output" = "12" ]
    printf 'Retry-After: soon\r\nRetry-After: 3\r\n' > "$f"
    run gh_retry_after_secs "$f"
    [ "$output" = "3" ]
}

@test "gh_retry_after_secs prints 0 when the header is absent" {
    f="$TEST_HOME/hdrs"
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n' > "$f"
    run gh_retry_after_secs "$f"
    [ "$output" = "0" ]
}

@test "gh_rate_limit_wait_secs computes the remaining window" {
    f="$TEST_HOME/hdrs"
    printf 'X-RateLimit-Reset: 1000000100\r\n' > "$f"
    run gh_rate_limit_wait_secs "$f" 1000000030
    [ "$status" -eq 0 ]
    [ "$output" = "70" ]
}

@test "gh_rate_limit_wait_secs clamps past resets to 0" {
    f="$TEST_HOME/hdrs"
    printf 'X-RateLimit-Reset: 1000000100\r\n' > "$f"
    run gh_rate_limit_wait_secs "$f" 1000000200
    [ "$output" = "0" ]
}

@test "gh_rate_limit_wait_secs prints 0 for missing/junk headers" {
    f="$TEST_HOME/hdrs"
    printf 'Server: github.com\r\n' > "$f"
    run gh_rate_limit_wait_secs "$f" 1000000000
    [ "$output" = "0" ]
    printf 'X-RateLimit-Reset: someday\r\n' > "$f"
    run gh_rate_limit_wait_secs "$f" 1000000000
    [ "$output" = "0" ]
}

@test "gh_api_get returns the body and code on HTTP 200" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'printf "X-Ok: 1\r\n\r\n" > "$h"'
        printf '%s\n' 'printf "%s" "{\"tag_name\":\"v9\"}" > "$b"'
        printf '%s\n' 'echo 200'
    } > "$stubdir/curl"
    chmod +x "$stubdir/curl"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest"
        [ "$?" -eq 0 ] && [ "$GH_API_CODE" = "200" ] && [ "$GH_API_BODY" = "{\"tag_name\":\"v9\"}" ] && echo PASS200'
    [ "$status" -eq 0 ]
    grep -q "PASS200" <<< "$output"
}

@test "gh_api_get retries transport failures with recorded backoff" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'echo 1 >> "$STUB_CALLS"; exit 7'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_CALLS="$TEST_HOME/calls" STUB_SLEPT="$TEST_HOME/slept" UO_GH_RETRIES=3 bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest"'
    [ "$status" -eq 1 ]
    [ "$(cat "$TEST_HOME/calls")" = "$(printf '1\n1\n1')" ]
    [ "$(cat "$TEST_HOME/slept")" = "$(printf '1\n2')" ]
}

@test "gh_api_get recovers when a retry succeeds after HTTP 500" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'n=$(cat "$STUB_CALLS" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$STUB_CALLS"'
        printf '%s\n' 'if [ "$n" = "1" ]; then echo 500; else printf "%s" "{\"ok\":1}" > "$b"; echo 200; fi'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_CALLS="$TEST_HOME/calls" STUB_SLEPT="$TEST_HOME/slept" bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest" && echo "RECOVERED:$GH_API_CODE"'
    [ "$status" -eq 0 ]
    grep -q "RECOVERED:200" <<< "$output"
    [ "$(cat "$TEST_HOME/slept")" = "1" ]
}

@test "gh_api_get never retries permanent 404 responses" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'printf "HTTP/1.1 404 Not Found\r\n\r\n" > "$h"'
        printf '%s\n' 'printf "%s" "{\"message\":\"Not Found\"}" > "$b"'
        printf '%s\n' 'echo 404'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_SLEPT="$TEST_HOME/slept" UO_GH_RETRIES=5 bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest"; rc=$?
        echo "CODE:$GH_API_CODE"
        exit "$rc"'
    [ "$status" -eq 1 ]
    grep -q "CODE:404" <<< "$output"
    [ ! -s "$TEST_HOME/slept" ]
}

@test "gh_api_get waits for a near rate-limit reset and recovers" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    reset=$(( $(date +%s) + 3 ))
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'n=$(cat "$STUB_CALLS" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$STUB_CALLS"'
        printf '%s\n' 'if [ "$n" = "1" ]; then'
        printf '%s\n' '  printf "HTTP/1.1 403 Forbidden\r\nX-RateLimit-Reset: %s\r\n\r\n" "$STUB_RESET" > "$h"'
        printf '%s\n' '  printf "%s" "{\"message\":\"API rate limit exceeded\"}" > "$b"; echo 403'
        printf '%s\n' 'else'
        printf '%s\n' '  printf "HTTP/1.1 200 OK\r\n\r\n" > "$h"; printf "%s" "{\"tag_name\":\"v9\"}" > "$b"; echo 200'
        printf '%s\n' 'fi'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_CALLS="$TEST_HOME/calls" STUB_SLEPT="$TEST_HOME/slept" STUB_RESET="$reset" bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest" && echo "OK:$GH_API_CODE"'
    [ "$status" -eq 0 ]
    grep -q "OK:200" <<< "$output"
    # the wait must equal the real reset window (3s minus tick drift), never the backoff table
    slept_val=$(cat "$TEST_HOME/slept")
    [ "$slept_val" -ge 1 ] && [ "$slept_val" -le 3 ]
    # the counter stub records the LATEST call number — exactly 2 calls happened
    [ "$(cat "$TEST_HOME/calls")" = "2" ]
}

@test "gh_api_get fails fast when the rate-limit reset is far away" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    reset=$(( $(date +%s) + 3600 ))
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'printf "HTTP/1.1 403 Forbidden\r\nX-RateLimit-Reset: %s\r\n\r\n" "$STUB_RESET" > "$h"'
        printf '%s\n' 'printf "%s" "{\"message\":\"API rate limit exceeded\"}" > "$b"; echo 403'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_SLEPT="$TEST_HOME/slept" STUB_RESET="$reset" UO_GH_RETRIES=3 bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest"; rc=$?
        echo "CODE:$GH_API_CODE"
        exit "$rc"'
    [ "$status" -eq 1 ]
    grep -q "CODE:403" <<< "$output"
    [ ! -s "$TEST_HOME/slept" ]
}

@test "gh_api_get honors Retry-After on 429 and recovers" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'while [ $# -gt 0 ]; do case "$1" in -D) h="$2"; shift 2;; -o) b="$2"; shift 2;; *) shift;; esac; done'
        printf '%s\n' 'n=$(cat "$STUB_CALLS" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$STUB_CALLS"'
        printf '%s\n' 'if [ "$n" = "1" ]; then'
        printf '%s\n' '  printf "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 2\r\n\r\n" > "$h"'
        printf '%s\n' '  printf "%s" "{}" > "$b"; echo 429'
        printf '%s\n' 'else'
        printf '%s\n' '  printf "HTTP/1.1 200 OK\r\n\r\n" > "$h"; printf "%s" "{\"ok\":1}" > "$b"; echo 200'
        printf '%s\n' 'fi'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_CALLS="$TEST_HOME/calls" STUB_SLEPT="$TEST_HOME/slept" bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest" && echo "OK:$GH_API_CODE"'
    [ "$status" -eq 0 ]
    grep -q "OK:200" <<< "$output"
    [ "$(cat "$TEST_HOME/slept")" = "2" ]
}

@test "gh_api_get clamps UO_GH_RETRIES to 6 attempts" {
    stubdir="$TEST_HOME/bin"
    mkdir -p "$stubdir"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' 'echo 1 >> "$STUB_CALLS"; exit 7'
    } > "$stubdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "$@" >> "$STUB_SLEPT"' > "$stubdir/sleep"
    chmod +x "$stubdir/curl" "$stubdir/sleep"
    GH_CURL_AUTH=()
    run env PATH="$stubdir:$PATH" STUB_CALLS="$TEST_HOME/calls" STUB_SLEPT="$TEST_HOME/slept" UO_GH_RETRIES=99 bash -c '
        source "'"$BATS_TEST_DIRNAME"'/../lib/github.sh"
        info(){ :; }; warn(){ :; }
        GH_CURL_AUTH=(); gh_api_get "https://api.github.com/repos/o/r/releases/latest"'
    [ "$status" -eq 1 ]
    [ "$(wc -l < "$TEST_HOME/calls")" -eq 6 ]
    # capped backoff: 1, 2, 4, 8, 8
    [ "$(cat "$TEST_HOME/slept")" = "$(printf '1\n2\n4\n8\n8')" ]
}
