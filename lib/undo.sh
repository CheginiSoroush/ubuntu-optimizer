# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/undo.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Reverses every optimization this tool applied: removes the drop-in files
#  (sysctl, journald, sudoers, polkit), restores /etc/fstab from the backup
#  created by set_noatime, re-enables the services that were disabled and
#  resets the NetworkManager overrides (DNS, Wi-Fi power management).
#
#  The plan is detected read-only first, shown to the user and only applied
#  after confirmation (-y auto-confirms). Every mutating step goes through
#  the sudo wrapper, so --dry-run prints the exact plan without executing.
#  Packages installed as part of optimization (preload, tlp, chrony) are
#  deliberately left in place — only a removal hint is printed.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# undo_root_has_noatime() — check the root line of an fstab file for noatime
#
# Same root-line pattern set_noatime() uses, so detection and restore always
# agree on what "the root entry" means.
#
# Arguments: $1 — path to an fstab-style file
# Returns:   0 — the root line contains noatime
#            1 — it does not (or the file is unreadable)
# ───────────────────────────────────────────────────────────────────────────────
undo_root_has_noatime() {
    sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' "$1" 2>/dev/null | grep -q "noatime"
}

# ───────────────────────────────────────────────────────────────────────────────
# undo_all_optimizations() — reverse every optimization applied by this tool
#
# Flow: detect → show plan → confirm → apply → report. Detection is purely
# read-only. Files are removed only when they exist; the fstab backup is
# restored only when it predates the noatime edit (backup lacks noatime,
# current fstab has it) so later manual fstab edits are never lost. The
# optional NetworkManager reset (DNS + Wi-Fi powersave) restarts the Wi-Fi
# connection and is therefore preceded by the same SSH warning the
# optimizers show. In dry-run mode the sudo wrapper prints each step and
# nothing is executed.
#
# Globals:   DRY_RUN (read); ASSUME_YES (read via confirm_action);
#            SYSCTL_CONF, JOURNALD_DROPIN, SUDOERS_TIMEOUT_FILE,
#            POLKIT_RULE_FILE (read); LOG_FAIL_COUNT (via failure())
# Arguments: none
# Returns:   0 — nothing to undo, declined, or the plan applied
#            1 — at least one step failed (already reported)
# ───────────────────────────────────────────────────────────────────────────────
undo_all_optimizations() {
    header "Undo All Optimizations"
    local plan=()
    local svc conn wifi_dns_fix=0 wifi_ps_fix=0 fstab_restore=0

    # ── Detection (read-only) ──────────────────────────────────────────────────
    if sudo test -f "$SYSCTL_CONF"; then
        plan+=("Remove the kernel parameter file and reload defaults: $SYSCTL_CONF")
    fi
    if sudo test -f "$JOURNALD_DROPIN"; then
        plan+=("Remove the journal size cap and restart journald: $JOURNALD_DROPIN")
    fi
    if sudo test -f "$SUDOERS_TIMEOUT_FILE"; then
        plan+=("Remove the extended sudo timeout: $SUDOERS_TIMEOUT_FILE")
    fi
    if sudo test -f "$POLKIT_RULE_FILE"; then
        plan+=("Remove the polkit rule and restart polkit: $POLKIT_RULE_FILE")
    fi
    if sudo test -f /etc/fstab.bak; then
        if undo_root_has_noatime /etc/fstab && ! undo_root_has_noatime <(sudo cat /etc/fstab.bak 2>/dev/null); then
            plan+=("Restore /etc/fstab from the automatic backup and remount /")
            fstab_restore=1
        else
            warn "fstab backup exists but does not match the expected noatime edit — fstab is left untouched."
        fi
    fi
    # Services disabled by disable_extra_services() — re-enable when present but not enabled
    local units
    units=$(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}')
    for svc in cups-browsed whoopsie avahi-daemon; do
        if grep -qx "${svc}.service" <<< "$units" \
           && [ "$(systemctl is-enabled "$svc" 2>/dev/null)" != "enabled" ]; then
            plan+=("Re-enable the service: $svc")
        fi
    done
    # NetworkManager overrides set by set_dns() / disable_wifi_powersave()
    if command -v nmcli > /dev/null 2>&1; then
        conn=$(get_active_connection wireless)
        if [ -n "$conn" ]; then
            if [ "$(nmcli -g ipv4.ignore-auto-dns connection show "$conn" 2>/dev/null)" = "yes" ]; then
                plan+=("Reset DNS of '$conn' back to automatic (Wi-Fi reconnects briefly)")
                wifi_dns_fix=1
            fi
            if [ "$(nmcli -g 802-11-wireless.powersave connection show "$conn" 2>/dev/null)" = "2" ]; then
                plan+=("Reset Wi-Fi power management of '$conn' to the default (Wi-Fi reconnects briefly)")
                wifi_ps_fix=1
            fi
        fi
    fi

    if [ ${#plan[@]} -eq 0 ]; then
        info "Nothing to undo — no changes made by this tool were detected."
        return 0
    fi

    # ── Plan ───────────────────────────────────────────────────────────────────
    echo -e "${BOLD}   The following changes will be reversed:${NC}"
    local i=1
    for step in "${plan[@]}"; do
        echo "     $i) $step"
        i=$((i + 1))
    done
    echo ""
    if [ "$wifi_dns_fix" = "1" ] || [ "$wifi_ps_fix" = "1" ]; then
        warn "The Wi-Fi connection will go down and come back for a few seconds."
        warn "Do not run this over an SSH session!"
    fi
    if ! confirm_action "Apply the undo plan above?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    # ── Apply ──────────────────────────────────────────────────────────────────
    local rc=0

    if sudo test -f "$SYSCTL_CONF"; then
        if sudo rm -f "$SYSCTL_CONF" && sudo sysctl --system > /dev/null 2>&1; then
            success "Kernel parameters removed and defaults reloaded."
        else
            failure "Failed to remove the kernel parameter file."
            rc=1
        fi
    fi

    if sudo test -f "$JOURNALD_DROPIN"; then
        if sudo rm -f "$JOURNALD_DROPIN" && sudo systemctl restart systemd-journald 2>/dev/null; then
            success "Journal size cap removed."
        else
            failure "Failed to remove the journal cap."
            rc=1
        fi
    fi

    if sudo test -f "$SUDOERS_TIMEOUT_FILE"; then
        if sudo rm -f "$SUDOERS_TIMEOUT_FILE"; then
            success "sudo password timeout restored to the distribution default."
        else
            failure "Failed to remove the sudoers drop-in."
            rc=1
        fi
    fi

    if sudo test -f "$POLKIT_RULE_FILE"; then
        if sudo rm -f "$POLKIT_RULE_FILE" && sudo systemctl restart polkit 2>/dev/null; then
            success "polkit rule removed and polkit restarted."
        else
            failure "Failed to remove the polkit rule."
            rc=1
        fi
    fi

    if [ "$fstab_restore" = "1" ]; then
        if sudo cp /etc/fstab.bak /etc/fstab; then
            sudo mount -o remount / 2>/dev/null
            if undo_root_has_noatime /etc/fstab; then
                warn "noatime is still present after the restore — check /etc/fstab manually."
            else
                success "/etc/fstab restored from backup (noatime removed)."
            fi
            info "The backup file is kept at /etc/fstab.bak."
        else
            failure "Failed to restore /etc/fstab from backup."
            rc=1
        fi
    fi

    for svc in cups-browsed whoopsie avahi-daemon; do
        if grep -qx "${svc}.service" <<< "$units" \
           && [ "$(systemctl is-enabled "$svc" 2>/dev/null)" != "enabled" ]; then
            if sudo systemctl enable --now "$svc" 2>/dev/null; then
                success "$svc re-enabled."
            else
                warn "Failed to re-enable $svc."
            fi
        fi
    done

    if [ "$wifi_dns_fix" = "1" ] || [ "$wifi_ps_fix" = "1" ]; then
        if [ "$DRY_RUN" != "1" ]; then
            info "The network will go down and come back for a few seconds."
        fi
        # Both overrides are cleared in one modify; powersave 0 = connection default
        if sudo nmcli connection modify "$conn" ipv4.dns "" ipv4.ignore-auto-dns no 802-11-wireless.powersave 0; then
            sudo nmcli connection down "$conn" > /dev/null 2>&1
            if sudo nmcli connection up "$conn" > /dev/null 2>&1; then
                success "NetworkManager overrides cleared (DNS auto, Wi-Fi power management default)."
            else
                failure "Wi-Fi reconnection failed — check the network state or run fixnet."
                rc=1
            fi
        else
            failure "Failed to reset the NetworkManager connection settings."
            rc=1
        fi
    fi

    # ── Packages are reported, never removed ───────────────────────────────────
    local pkg
    for pkg in preload tlp chrony; do
        if pkg_installed "$pkg"; then
            info "$pkg was installed by the optimizer and is left in place (remove manually: sudo apt remove $pkg)."
        fi
    done

    if [ "$rc" -eq 0 ]; then
        success "Undo finished — your previous configuration is back. A reboot is recommended."
    else
        warn "Undo finished with errors — see the messages above and the activity log."
    fi
    return "$rc"
}
