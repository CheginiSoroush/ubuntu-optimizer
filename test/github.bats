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
