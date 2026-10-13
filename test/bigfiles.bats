#!/usr/bin/env bats
# ============================================================
#   test/bigfiles.bats — tests for the large-file finder
#   (lib/bigfiles.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   CLI level runs the real entry script with --bigfiles against a
#   fake tree built from SPARSE files (truncate -s), so the suite
#   stays fast and uses no real disk. Function level sources
#   lib/common.sh + lib/bigfiles.sh to test the pure size formatter.
#   Everything runs fully offline — nothing is ever deleted.
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

    # Fake data tree — sparse files of known sizes
    DATA="$TEST_HOME/data"
    mkdir -p "$DATA/videos" "$DATA/music"
    truncate -s 150M "$DATA/videos/movie.mkv"
    truncate -s 120M "$DATA/videos/backup.iso"
    truncate -s 3M  "$DATA/music/song.mp3"
    truncate -s 1M  "$DATA/music/short.mp3"
    echo notes > "$DATA/notes.txt"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_bigfiles() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/bigfiles.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- function level: pure size formatter ----------

@test "_bigfiles_human formats bytes and kilobytes" {
    load_bigfiles
    run _bigfiles_human 512
    [ "$output" = "512 B" ]
    run _bigfiles_human 1023
    [ "$output" = "1023 B" ]
    run _bigfiles_human 1024
    [ "$output" = "1 KB" ]
    run _bigfiles_human 831488
    [ "$output" = "812 KB" ]
}

@test "_bigfiles_human formats megabytes and gigabytes with boundaries" {
    load_bigfiles
    run _bigfiles_human 1048575
    [ "$output" = "1023 KB" ]
    run _bigfiles_human 1048576
    [ "$output" = "1 MB" ]
    run _bigfiles_human 967976960
    [ "$output" = "923 MB" ]
    run _bigfiles_human 1073741823
    [ "$output" = "1023 MB" ]
    run _bigfiles_human 1073741824
    [ "$output" = "1.0 GB" ]
    run _bigfiles_human 1610612736
    [ "$output" = "1.5 GB" ]
    run _bigfiles_human "oops"
    [ "$output" = "?" ]
}

# ---------- CLI level ----------

@test "cli: --bigfiles DIR lists the large files, largest first" {
    run run_uo --bigfiles "$DATA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Large File Finder"* ]]
    [[ "$output" == *"150 MB"*"movie.mkv"* ]]   # present at all
    [[ "$output" == *"movie.mkv"*"backup.iso"* ]] # ...and ordered before
}

@test "cli: the default 100 MB floor filters out the small files" {
    run run_uo --bigfiles "$DATA"
    [ "$status" -eq 0 ]
    [[ "$output" != *"song.mp3"* ]]    # 3 MB — below the floor
    [[ "$output" != *"short.mp3"* ]]   # 1 MB — below the floor
    [[ "$output" != *"notes.txt"* ]]
}

@test "cli: UO_BIGFILES_MIN_MB lowers the size floor" {
    UO_BIGFILES_MIN_MB=2 run run_uo --bigfiles "$DATA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 MB"*"song.mp3"* ]]     # now visible
    [[ "$output" != *"short.mp3"* ]]           # 1 MB still below
}

@test "cli: a nonexistent directory warns friendly and exits 0" {
    run run_uo --bigfiles "$TEST_HOME/does-not-exist"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory not found"* ]]
    [[ "$output" == *"nothing was deleted"* ]]
}

@test "cli: the scan ends with the read-only hint and the --disk-clean pointer" {
    run run_uo --bigfiles "$DATA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"read-only — nothing was deleted"* ]]
    [[ "$output" == *"--disk-clean"* ]]
}

@test "cli: the list is capped at 20 files" {
    MANY="$TEST_HOME/many"
    mkdir -p "$MANY"
    local i
    for i in $(seq 1 25); do
        truncate -s 110M "$MANY/file$i.bin"
    done
    run run_uo --bigfiles "$MANY"
    [ "$status" -eq 0 ]
    local n
    n=$(grep -c '\.bin$' <<< "$output")
    [ "$n" -eq 20 ]
}

@test "cli: --bigfiles without a directory scans \$HOME" {
    run run_uo --bigfiles
    [ "$status" -eq 0 ]
    [[ "$output" == *"movie.mkv"* ]]   # found under $HOME/data/videos
}

@test "cli: an empty directory reports that nothing was found" {
    EMPTY="$TEST_HOME/empty"
    mkdir -p "$EMPTY"
    run run_uo --bigfiles "$EMPTY"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No files larger than 100 MB found"* ]]
}
