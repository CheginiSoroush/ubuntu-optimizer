#!/usr/bin/env bats
# ============================================================
#   test/undo.bats — unit tests for lib/undo.sh
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   HOME is redirected to a temp sandbox BEFORE sourcing, so any
#   state touched by the module stays inside the sandbox — the
#   user's real data is never touched. The undo flow itself needs
#   sudo and a full system, so these tests cover the pieces that
#   are safely testable: the function surface and the fstab
#   root-line detector that guards the backup restore.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # shellcheck source=../lib/undo.sh
    source "$BATS_TEST_DIRNAME/../lib/undo.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- function surface ----------

@test "undo_all_optimizations is defined" {
    declare -F undo_all_optimizations > /dev/null
}

@test "undo_root_has_noatime is defined" {
    declare -F undo_root_has_noatime > /dev/null
}

# ---------- fstab root-line detector ----------

@test "undo_root_has_noatime: no noatime on the root line" {
    local fstab="$TEST_HOME/fstab"
    printf '/dev/sda1  /      ext4  defaults         0 1\n' > "$fstab"
    ! undo_root_has_noatime "$fstab"
}

@test "undo_root_has_noatime: noatime present on the root line" {
    local fstab="$TEST_HOME/fstab"
    printf '/dev/sda1  /      ext4  defaults,noatime 0 1\n' > "$fstab"
    undo_root_has_noatime "$fstab"
}

@test "undo_root_has_noatime: noatime on another mount must not count" {
    local fstab="$TEST_HOME/fstab"
    printf '/dev/sda1  /      ext4  defaults         0 1\n/dev/sda2  /home  ext4  noatime          0 2\n' > "$fstab"
    ! undo_root_has_noatime "$fstab"
}

@test "undo_root_has_noatime: unreadable file counts as no noatime" {
    ! undo_root_has_noatime "$TEST_HOME/does-not-exist"
}
