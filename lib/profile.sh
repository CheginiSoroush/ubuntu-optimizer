# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/profile.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Curated optimization presets: `uo --profile laptop|server|gaming|minimal`.
#  A profile is a safe, ordered subset of the existing optimizer steps — it
#  never invents new system changes, it only picks the steps that make sense
#  for a scenario (and skips the ones that do not, e.g. no preload on a
#  server, no TLP outside laptops).
#
#  The plan is printed and confirmed first (-y auto-confirms); every step is
#  dry-run capable through the usual sudo wrapper. `profile_steps()` is the
#  single source of truth for what each profile runs, so the bats tests can
#  assert the exact composition without touching the system.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

readonly PROFILE_NAMES=(laptop server gaming minimal)

# ───────────────────────────────────────────────────────────────────────────────
# profile_is_valid() — check whether $1 is a known profile name
#
# Arguments: $1 — candidate profile name
# Returns:   0 — valid
#            1 — unknown name
# ───────────────────────────────────────────────────────────────────────────────
profile_is_valid() {
    local p
    for p in "${PROFILE_NAMES[@]}"; do
        [ "$1" = "$p" ] && return 0
    done
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# profile_steps() — print the step function names a profile runs, in order
#
# Single source of truth for profile composition; apply_profile() executes
# this list and the unit tests assert on it.
#
# Rationale:
#   laptop  — battery + responsiveness: memory tuning, noatime, TLP,
#             low-latency network (BBR/TCP), Wi-Fi power management off
#   server  — throughput & predictable memory: no preload, no TLP,
#             no Wi-Fi steps; services like cups-browsed/whoopsie off
#   gaming  — latency only: BBR/TCP + Wi-Fi power management off;
#             nothing that touches services or adds daemons
#   minimal — the conservative core: memory tuning, journal cap, unneeded
#             desktop services off; installs nothing
#
# Arguments: $1 — profile name (must be valid)
# Returns:   0 — prints one step function name per line
# ───────────────────────────────────────────────────────────────────────────────
profile_steps() {
    case "$1" in
        laptop)
            echo optimize_memory
            echo set_noatime
            echo install_tlp
            echo enable_bbr
            echo optimize_tcp
            echo disable_wifi_powersave
            echo limit_journal
            ;;
        server)
            echo optimize_memory
            echo set_noatime
            echo limit_journal
            echo enable_bbr
            echo optimize_tcp
            echo disable_extra_services
            ;;
        gaming)
            echo optimize_memory
            echo enable_bbr
            echo optimize_tcp
            echo disable_wifi_powersave
            echo limit_journal
            ;;
        minimal)
            echo optimize_memory
            echo limit_journal
            echo disable_extra_services
            ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# profile_describe() — print the one-line intent of a profile
#
# Arguments: $1 — profile name (must be valid)
# Returns:   0 — prints the description
# ───────────────────────────────────────────────────────────────────────────────
profile_describe() {
    case "$1" in
        laptop)  echo "Balanced battery life and responsiveness for portable machines." ;;
        server)  echo "Throughput and predictable memory — no desktop niceties, no extra daemons." ;;
        gaming)  echo "Lowest latency: network tuning only, nothing else is touched." ;;
        minimal) echo "The conservative core: safe cleanups only, installs nothing." ;;
    esac
}

# ── Menu wrappers (menu_loop dispatches by function name) ──────────────────────

profile_run_laptop()  { apply_profile laptop; }
profile_run_server()  { apply_profile server; }
profile_run_gaming()  { apply_profile gaming; }
profile_run_minimal() { apply_profile minimal; }

# ───────────────────────────────────────────────────────────────────────────────
# apply_profile() — show the plan for a profile and run its steps
#
# Flow: validate the name → print intent + numbered plan → confirm
# (auto-confirmed with -y) → sudo_precheck → run each step in order. Every
# step reports its own status through the shared logging helpers, so the
# end-of-run session summary and exit code stay meaningful. Steps are
# executed one by one; a failing step is reported but does not stop the
# remaining ones (matching --optimize behavior).
#
# Globals:   DRY_RUN (read); ASSUME_YES (read via confirm_action)
# Arguments: $1 — profile name
# Returns:   0 — all steps completed (or previewed in dry-run)
#            1 — unknown profile name, declined, or at least one step failed
# ───────────────────────────────────────────────────────────────────────────────
apply_profile() {
    local name="$1"
    header "Optimization Profile: ${name:-?}"

    if ! profile_is_valid "$name"; then
        failure "Unknown profile: '${name}'."
        info "Valid profiles: ${PROFILE_NAMES[*]}"
        info "Preview one first: uo --profile laptop --dry-run -y"
        return 1
    fi

    info "Intent: $(profile_describe "$name")"
    if [ "$DRY_RUN" = "1" ]; then
        info "Profile: $name — nothing is executed in dry-run mode."
    fi

    # Build the plan from the single source of truth
    local steps=() step
    while IFS= read -r step; do
        [ -n "$step" ] && steps+=("$step")
    done < <(profile_steps "$name")

    echo -e "${BOLD}   The ${name} profile runs these ${#steps[@]} steps:${NC}"
    local i=1
    for step in "${steps[@]}"; do
        echo "     $i) $step"
        i=$((i + 1))
    done
    echo ""

    if ! confirm_action "Apply the «$name» profile now?"; then
        info "Cancelled — the profile was not applied."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    local rc=0
    for step in "${steps[@]}"; do
        if ! "$step"; then
            rc=1
        fi
    done

    if [ "$rc" -eq 0 ]; then
        success "Profile «$name» applied — review the steps above for details."
        info "Revert anytime with: uo --undo"
    else
        warn "Profile «$name» finished with errors — see the messages above."
    fi
    return "$rc"
}
