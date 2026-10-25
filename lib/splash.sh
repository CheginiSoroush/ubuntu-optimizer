# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/splash.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Boot splash diagnosis & repair. The graphical boot splash (Plymouth logo
#  with the spinner) is controlled by the `quiet splash` parameters on the
#  kernel command line; when /etc/default/grub disappears or loses its
#  GRUB_CMDLINE_LINUX_DEFAULT line, update-grub regenerates a config without
#  them and every boot/shutdown turns into a flood of green [ OK ] systemd
#  status lines. splash_show() reports the state read-only, splash_fix()
#  repairs it: restores the package config file when missing (apt reinstall
#  with --force-confmiss, hand-written fallback) or re-adds the parameters
#  (with a timestamped backup), then regenerates grub.cfg via update-grub.
#
#  Only GRUB_CMDLINE_LINUX_DEFAULT is ever written — GRUB_CMDLINE_LINUX and
#  /etc/default/grub.d/*.cfg (kdump's crashkernel, …) are left untouched, and
#  the repair is fully reversible through the timestamped backup.
#
#  Test hooks (not part of the user-facing configuration):
#      UO_SPLASH_GRUB_FILE      — override the grub default file path
#      UO_SPLASH_CMDLINE_FILE   — override the /proc/cmdline path
#      UO_SPLASH_FAKE_GRUB=1    — force the "grub machine" verdict so the
#                                 repair paths are exercisable on machines
#                                 without /boot/grub (containers, WSL)
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Paths (overridable so the offline test suite can sandbox them) ────────────
SPLASH_GRUB_FILE="${UO_SPLASH_GRUB_FILE:-/etc/default/grub}"
SPLASH_CMDLINE_FILE="${UO_SPLASH_CMDLINE_FILE:-/proc/cmdline}"

# ───────────────────────────────────────────────────────────────────────────────
# _splash_is_grub_system() — is this machine booted through grub?
#
# A real grub install has /boot/grub (Debian-family) or /boot/grub2 (Fedora
# family). Containers, WSL and chroots have neither — the repair there is
# meaningless and degrades to a friendly hint.
#
# Documented disable (test hook): UO_SPLASH_FAKE_GRUB=1 forces the "present"
# verdict so the offline test suite can exercise the repair paths.
#
# Arguments: none
# Returns:   0 — grub environment present · 1 — not present
# ───────────────────────────────────────────────────────────────────────────────
_splash_is_grub_system() {
    if [ -d /boot/grub ] || [ -d /boot/grub2 ]; then
        return 0
    fi
    [ "${UO_SPLASH_FAKE_GRUB:-0}" = "1" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_have_apt() — can we reinstall packages here?
#
# The config-file restoration route goes through apt; without apt/dpkg only
# the hand-written fallback remains.
#
# Arguments: none
# Returns:   0 — apt-get + dpkg available · 1 — not available
# ───────────────────────────────────────────────────────────────────────────────
_splash_have_apt() {
    command -v apt-get > /dev/null 2>&1 && command -v dpkg > /dev/null 2>&1
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_owner_pkg() — which package ships /etc/default/grub
#
# Ubuntu ships it in grub-common, Debian in grub2-common. The choice is made
# from what is actually installed (dpkg), never hardcoded.
#
# Arguments: none
# Returns:   prints "grub2-common" or "grub-common" · 1 — neither installed
# ───────────────────────────────────────────────────────────────────────────────
_splash_owner_pkg() {
    if command -v dpkg > /dev/null 2>&1; then
        if dpkg -l grub2-common 2> /dev/null | grep -q '^ii'; then
            echo "grub2-common"
            return 0
        fi
        if dpkg -l grub-common 2> /dev/null | grep -q '^ii'; then
            echo "grub-common"
            return 0
        fi
    fi
    echo "grub-common"
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_file_state() — does the grub default file exist?
#
# Arguments: none
# Returns:   0 — file exists · 1 — file missing
# ───────────────────────────────────────────────────────────────────────────────
_splash_file_state() {
    [ -f "$SPLASH_GRUB_FILE" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_params_state() — are quiet and splash configured?
#
# Checks the effective GRUB_CMDLINE_LINUX_DEFAULT assignment (last one wins —
# the same rule grub-mkconfig applies) for both tokens. Commented lines are
# ignored.
#
# Arguments: none
# Returns:   0 — both tokens present · 1 — file or tokens missing
# ───────────────────────────────────────────────────────────────────────────────
_splash_params_state() {
    [ -f "$SPLASH_GRUB_FILE" ] || return 1
    local line
    line=$(grep '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$SPLASH_GRUB_FILE" 2> /dev/null | tail -n1) || return 1
    [ -n "$line" ] || return 1
    case "$line" in
        *quiet*) case "$line" in *splash*) return 0 ;; esac ;;
    esac
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_live_state() — did the RUNNING kernel boot with quiet splash?
#
# Reads the real (or test-faked) /proc/cmdline. A "missing" here with a fixed
# config simply means the fix happened after this boot.
#
# Arguments: none
# Returns:   0 — live cmdline has quiet+splash · 1 — not
# ───────────────────────────────────────────────────────────────────────────────
_splash_live_state() {
    [ -r "$SPLASH_CMDLINE_FILE" ] || return 1
    local line
    line=$(cat "$SPLASH_CMDLINE_FILE" 2> /dev/null) || return 1
    case "$line" in
        *quiet*) case "$line" in *splash*) return 0 ;; esac ;;
    esac
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# splash_show() — boot splash status (read-only)
#
# Four views: the live kernel command line, the grub config file state, the
# plymouth package presence and a plain-language verdict with the matching
# repair hint. Diagnostics never fail the session (exit 0 on every path).
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
splash_show() {
    header "🥾 Boot Splash Status"

    if ! _splash_is_grub_system; then
        info "no /boot/grub on this machine (container/WSL?) — splash check skipped"
        return 0
    fi

    # ── 1. the live kernel command line ───────────────────────────────────────
    echo -e "${BOLD}   ── Running kernel command line ──${NC}"
    local live="missing"
    if [ -r "$SPLASH_CMDLINE_FILE" ]; then
        echo "   $(cat "$SPLASH_CMDLINE_FILE" 2> /dev/null)"
        _splash_live_state && live="ok"
    else
        echo "   (not readable)"
    fi
    case "$live" in
        ok)      success "This boot is quiet — the splash screen should be visible" ;;
        missing) warn   "This boot has no quiet/splash — the [ OK ] flood you see is expected" ;;
    esac
    echo ""

    # ── 2. the grub config file ───────────────────────────────────────────────
    echo -e "${BOLD}   ── GRUB config ($SPLASH_GRUB_FILE) ──${NC}"
    if _splash_file_state; then
        if _splash_params_state; then
            success "GRUB_CMDLINE_LINUX_DEFAULT carries quiet + splash — config is healthy"
        else
            warn "GRUB_CMDLINE_LINUX_DEFAULT is missing quiet/splash — the next boot will be verbose"
            info "Fix with: uo --fix-splash"
        fi
    else
        warn "$SPLASH_GRUB_FILE is MISSING — the known cause of the verbose [ OK ] boot"
        info "This is exactly the state after a lost/broken grub-common config file."
        info "Fix with: uo --fix-splash (restores the package file, then runs update-grub)"
    fi
    echo ""

    # ── 3. plymouth packages ──────────────────────────────────────────────────
    echo -e "${BOLD}   ── Plymouth (the splash renderer) ──${NC}"
    if command -v dpkg > /dev/null 2>&1; then
        local ply
        ply=$(dpkg -l 2> /dev/null | grep -c '^ii.*plymouth')
        case "$ply" in
            0) warn "no plymouth packages installed — the graphical splash cannot render" ;;
            *) success "$ply plymouth package(s) installed" ;;
        esac
    else
        info "dpkg not available — plymouth check skipped"
    fi
    echo ""

    # ── 4. the verdict ────────────────────────────────────────────────────────
    if _splash_params_state && [ "$live" = "ok" ]; then
        success "Verdict: everything is healthy — the splash is active on this boot"
    elif _splash_params_state; then
        info "Verdict: config is healthy but this boot predates the fix — reboot to apply"
    else
        warn "Verdict: the boot splash is broken — 'uo --fix-splash' repairs it (backup + update-grub included)"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _splash_write_minimal() — hand-written fallback for /etc/default/grub
#
# Used only when the package reinstall could not restore the file (no apt, or
# the reinstall failed). Writes the stock Ubuntu desktop defaults through the
# sudo wrapper — in dry-run the plan is printed instead.
#
# Arguments: none
# Returns:   0 — written (or planned) · 1 — the write failed
# ───────────────────────────────────────────────────────────────────────────────
_splash_write_minimal() {
    if [ "$DRY_RUN" = "1" ]; then
        sudo tee "$SPLASH_GRUB_FILE" > /dev/null << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`( . /etc/os-release; echo ${NAME:-Ubuntu} ) 2>/dev/null`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
        return 0
    fi
    if ! sudo tee "$SPLASH_GRUB_FILE" > /dev/null << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR=`( . /etc/os-release; echo ${NAME:-Ubuntu} ) 2>/dev/null`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
    then
        failure "Could not write $SPLASH_GRUB_FILE."
        return 1
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# splash_fix() — restore the graphical boot splash (repair)
#
# One of two repairs, chosen by the diagnosis, followed by update-grub:
#   • config file missing  → apt reinstall of the owning package with
#     --force-confmiss (dpkg never recreates deleted conffiles without it);
#     falls back to a hand-written stock config when the reinstall cannot
#   • params missing       → timestamped backup of the file, then the
#     GRUB_CMDLINE_LINUX_DEFAULT line is set to "quiet splash" (replaced when
#     present, appended when not)
# GRUB_CMDLINE_LINUX and every /etc/default/grub.d/*.cfg drop-in are never
# touched, so kdump's crashkernel and vendor drop-ins survive untouched.
# Idempotent: a healthy system is reported and left alone. Every mutation
# runs through the sudo wrapper — --dry-run prints the exact plan.
#
# Globals:   DRY_RUN (read), ASSUME_YES (via confirm), SPLASH_GRUB_FILE
# Arguments: none
# Returns:   0 — repaired or nothing to do · 1 — a step failed
# ───────────────────────────────────────────────────────────────────────────────
splash_fix() {
    header "🥾 Restore Boot Splash"

    if ! _splash_is_grub_system; then
        info "no /boot/grub on this machine (container/WSL?) — nothing to repair here"
        return 0
    fi

    # ── diagnosis ─────────────────────────────────────────────────────────────
    local file_missing=0 params_missing=0
    _splash_file_state || file_missing=1
    _splash_params_state || params_missing=1

    if [ "$file_missing" -eq 0 ] && [ "$params_missing" -eq 0 ]; then
        success "The boot splash is already configured — nothing to do."
        if ! _splash_live_state; then
            info "The running kernel booted before the fix — reboot to see the splash."
        fi
        return 0
    fi

    # ── the plan ──────────────────────────────────────────────────────────────
    if [ "$file_missing" -eq 1 ]; then
        warn "$SPLASH_GRUB_FILE is missing — the package config file will be restored."
        if _splash_have_apt; then
            local pkg
            pkg=$(_splash_owner_pkg) || pkg="grub-common"
            info "Plan: sudo apt-get install --reinstall -o Dpkg::Options::=--force-confmiss $pkg"
        fi
        info "Plan (fallback): write a stock desktop config with GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\""
    else
        warn "quiet/splash are missing from GRUB_CMDLINE_LINUX_DEFAULT."
        info "Plan: back up the file to ${SPLASH_GRUB_FILE}.bak-<timestamp>, then set the parameters."
    fi
    info "Plan: sudo update-grub (regenerates /boot/grub/grub.cfg — dual-boot entries are re-detected, nothing is removed)."
    info "GRUB_CMDLINE_LINUX and /etc/default/grub.d/*.cfg (kdump, vendor drop-ins) are never touched."

    if ! confirm_action "Apply the boot splash repair?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    # ── repair 1: restore the missing config file ─────────────────────────────
    if [ "$file_missing" -eq 1 ]; then
        if _splash_have_apt; then
            local pkg
            pkg=$(_splash_owner_pkg) || pkg="grub-common"
            info "Reinstalling $pkg (the --force-confmiss flag restores deleted config files)…"
            if sudo apt-get install --reinstall -o Dpkg::Options::="--force-confmiss" "$pkg"; then
                if _splash_file_state; then
                    success "$SPLASH_GRUB_FILE restored by the package manager."
                elif [ "$DRY_RUN" = "1" ]; then
                    success "[dry-run] $pkg would be reinstalled — the config file would be restored."
                fi
            fi
        fi
        if ! _splash_file_state; then
            if [ "$DRY_RUN" = "1" ]; then
                info "Fallback plan: write a stock desktop config directly."
                _splash_write_minimal
                success "[dry-run] $SPLASH_GRUB_FILE would be written (stock desktop defaults)."
            else
                warn "The package route did not restore the file — writing a stock config directly."
                _splash_write_minimal || return 1
                success "$SPLASH_GRUB_FILE written (stock desktop defaults)."
            fi
        fi
    fi

    # ── repair 2: fix the parameters in an existing file ──────────────────────
    if [ "$params_missing" -eq 1 ] && [ "$file_missing" -eq 0 ]; then
        local backup
        backup="${SPLASH_GRUB_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
        if sudo cp -a "$SPLASH_GRUB_FILE" "$backup"; then
            success "Backup saved: $backup"
        else
            failure "Could not create the backup $backup — aborted, nothing was changed."
            return 1
        fi
        if grep -q '^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=' "$SPLASH_GRUB_FILE" 2> /dev/null; then
            sudo sed -i 's|^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"|' "$SPLASH_GRUB_FILE"
        else
            printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' | sudo tee -a "$SPLASH_GRUB_FILE" > /dev/null
        fi
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\" would be set now."
        else
            success "GRUB_CMDLINE_LINUX_DEFAULT set to \"quiet splash\"."
        fi
    fi

    # ── regenerate grub.cfg ───────────────────────────────────────────────────
    if command -v update-grub > /dev/null 2>&1; then
        info "Regenerating the grub configuration…"
        if [ "$DRY_RUN" = "1" ]; then
            success "[dry-run] update-grub would run now."
        else
            if ! sudo update-grub; then
                failure "update-grub failed — the parameters are written but grub.cfg is stale."
                return 1
            fi
            success "grub.cfg regenerated."
        fi
    else
        warn "update-grub not found — run 'sudo update-grub' (or grub-mkconfig) manually."
    fi

    # ── verify ────────────────────────────────────────────────────────────────
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] The repair is planned — rerun without --dry-run to apply it."
        return 0
    fi
    if _splash_params_state; then
        success "Done — reboot to see the graphical splash instead of the [ OK ] flood."
        return 0
    fi
    failure "The verification step failed — inspect $SPLASH_GRUB_FILE manually."
    return 1
}
