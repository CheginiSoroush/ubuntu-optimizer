#!/usr/bin/env bats
# ============================================================
#   test/profile.bats — unit tests for lib/profile.sh
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   HOME is redirected to a temp sandbox BEFORE sourcing. The
#   profile composition is asserted through profile_steps() —
#   the single source of truth apply_profile() executes — so
#   these tests pin exactly which optimizer steps each preset
#   runs without touching the system.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # shellcheck source=../lib/profile.sh
    source "$BATS_TEST_DIRNAME/../lib/profile.sh"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

# ---------- name validation ----------

@test "profile_is_valid accepts all four profile names" {
    for p in laptop server gaming minimal; do
        profile_is_valid "$p"
    done
}

@test "profile_is_valid rejects unknown names" {
    ! profile_is_valid "desktop"
    ! profile_is_valid ""
    ! profile_is_valid "LAPTOP"
}

# ---------- profile composition ----------

@test "laptop profile: TLP yes, preload no, Wi-Fi powersave off" {
    local steps
    steps=$(profile_steps laptop)
    grep -qx "install_tlp" <<< "$steps"
    ! grep -qx "install_preload" <<< "$steps"
    grep -qx "disable_wifi_powersave" <<< "$steps"
}

@test "server profile: no Wi-Fi steps, no TLP, no preload" {
    local steps
    steps=$(profile_steps server)
    ! grep -qx "disable_wifi_powersave" <<< "$steps"
    ! grep -qx "install_tlp" <<< "$steps"
    ! grep -qx "install_preload" <<< "$steps"
    grep -qx "disable_extra_services" <<< "$steps"
}

@test "gaming profile: latency steps only, nothing installed" {
    local steps
    steps=$(profile_steps gaming)
    ! grep -qx "set_noatime" <<< "$steps"
    ! grep -qx "install_preload" <<< "$steps"
    ! grep -qx "disable_extra_services" <<< "$steps"
    grep -qx "enable_bbr" <<< "$steps"
    grep -qx "optimize_tcp" <<< "$steps"
}

@test "minimal profile: exactly the conservative core" {
    [ "$(profile_steps minimal)" = "optimize_memory
limit_journal
disable_extra_services" ]
}

@test "apply_profile is defined" {
    declare -F apply_profile > /dev/null
}
