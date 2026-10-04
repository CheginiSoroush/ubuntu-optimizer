# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/system.sh
# ───────────────────────────────────────────────────────────────────────────────
#  System/memory optimizations (sysctl values, fstab noatime, services,
#  preload, tlp, journal cap), security settings (sudo timeout, polkit
#  rule) and time sync with chrony. Called by --system, --security and
#  --time (--system also via --optimize) plus the matching menus.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── System & memory optimization ────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# optimize_memory() — Lower swappiness and vfs_cache_pressure
#
# Writes vm.swappiness=10 and vm.vfs_cache_pressure=50 through set_sysctl
# into $SYSCTL_CONF, applies them with sysctl --system, then reads both
# keys back to verify they actually took effect.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — values applied and verified (or previewed in dry-run)
#            1 — apply failed, or the values could not be verified
# ───────────────────────────────────────────────────────────────────────────────
optimize_memory() {
    header "Reduce swappiness and vfs_cache_pressure"
    set_sysctl vm.swappiness 10
    set_sysctl vm.vfs_cache_pressure 50
    if ! apply_sysctl; then
        failure "Failed to apply the memory settings."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] memory values would be set (swappiness=10, vfs_cache_pressure=50)."
        return 0
    fi
    # Verify the applied values
    local sw vcp
    sw=$(sysctl -n vm.swappiness 2>/dev/null)
    vcp=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)
    if [ "$sw" = "10" ] && [ "$vcp" = "50" ]; then
        success "Memory values set: swappiness=10 | vfs_cache_pressure=50"
        return 0
    else
        failure "Values could not be verified: swappiness=${sw:-?} | vfs_cache_pressure=${vcp:-?}"
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# set_noatime() — Add noatime to the root entry in /etc/fstab
#
# Only the root partition line is inspected; noatime is appended to the
# end of its options field, independent of a 'defaults' entry. A backup is
# kept at /etc/fstab.bak, the root filesystem is remounted immediately and
# the result verified with findmnt (falls back to "applies after reboot").
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — noatime present (already, added, or previewed in dry-run)
#            1 — editing /etc/fstab failed
# ───────────────────────────────────────────────────────────────────────────────
set_noatime() {
    header "Add noatime to /etc/fstab"
    # Only the root partition line is checked — not any noatime in the file
    if sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' /etc/fstab 2>/dev/null | grep -q "noatime"; then
        info "noatime is already enabled on the root partition."
        return 0
    fi
    sudo cp /etc/fstab /etc/fstab.bak
    # In dry-run the cp above was only printed — the backup does not exist yet
    [ "$DRY_RUN" = "1" ] || info "Backup created: /etc/fstab.bak"
    # Append noatime to the end of the options field — independent of a 'defaults' entry
    sudo sed -i -E '/^[^#]*[[:space:]]\/[[:space:]]/ { /noatime/! s/(^[^#]*[[:space:]]\/[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+)/\1,noatime/ }' /etc/fstab
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] noatime would be added to the root entry of /etc/fstab."
        return 0
    fi
    if sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' /etc/fstab 2>/dev/null | grep -q "noatime"; then
        # Apply immediately with a remount
        sudo mount -o remount / 2>/dev/null
        if findmnt -no OPTIONS / 2>/dev/null | grep -qw noatime; then
            success "noatime added to fstab and applied right away (remount)."
        else
            success "noatime added to fstab; it will apply after a reboot."
        fi
        return 0
    else
        failure "Failed to edit /etc/fstab."
        info "To restore if needed: sudo cp /etc/fstab.bak /etc/fstab"
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# disable_extra_services() — Disable unneeded background services
#
# Targets cups-browsed, whoopsie and avahi-daemon; disabling avahi-daemon
# breaks network printer discovery (mDNS), hence the up-front warning. The
# unit-file list is read once and each service is touched only when its
# unit exists on this system.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — always (individual failures are warned about)
# ───────────────────────────────────────────────────────────────────────────────
disable_extra_services() {
    header "Disable Extra Services"
    warn "Disabling avahi-daemon breaks network printer discovery (mDNS)."
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] these services would be disabled (if present): cups-browsed, whoopsie, avahi-daemon"
        return 0
    fi
    # The unit list is read once (instead of a systemctl call per iteration)
    local units svc count=0
    units=$(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}')
    for svc in cups-browsed whoopsie avahi-daemon; do
        if grep -qx "${svc}.service" <<< "$units"; then
            if sudo systemctl disable --now "$svc" 2>/dev/null; then
                success "$svc disabled."
                count=$((count + 1))
            else
                warn "Failed to disable $svc."
            fi
        else
            info "$svc does not exist on this system."
        fi
    done
    [ "$count" -gt 0 ] && success "$count services disabled in total."
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# install_preload() — Install the preload adaptive prefetcher
#
# A no-op when preload is already present; otherwise installs it via apt
# with the output suppressed.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — installed, already present, or previewed in dry-run
#            1 — the apt install failed
# ───────────────────────────────────────────────────────────────────────────────
install_preload() {
    header "Install preload (adaptive prefetcher)"
    if pkg_installed preload; then
        info "preload is already installed."
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] preload would be installed."
        return 0
    fi
    if sudo apt install -y preload > /dev/null 2>&1; then
        success "preload installed."
        return 0
    else
        failure "Failed to install preload."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# install_tlp() — Install and enable tlp (battery management)
#
# Battery presence distinguishes laptop from desktop — on a desktop tlp
# has little effect and the user is warned. power-profiles-daemon conflicts
# with tlp and is removed first, only after an explicit confirmation.
#
# Globals:   DRY_RUN (read); ASSUME_YES (read via confirm_action)
# Arguments: none
# Returns:   0 — tlp installed and enabled, already present, declined,
#            or previewed in dry-run
#            1 — removing power-profiles-daemon or installing tlp failed
# ───────────────────────────────────────────────────────────────────────────────
install_tlp() {
    header "Install tlp (battery management)"
    if pkg_installed tlp; then
        info "tlp is already installed."
        return 0
    fi
    # Laptop detection via battery presence
    if compgen -G "/sys/class/power_supply/BAT*" > /dev/null; then
        info "Battery detected — this is a laptop."
    else
        warn "No battery found — tlp has little effect on a desktop."
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] tlp would be installed and enabled."
        return 0
    fi
    # power-profiles-daemon conflicts with tlp
    if pkg_installed power-profiles-daemon; then
        warn "power-profiles-daemon conflicts with tlp and must be removed."
        if ! confirm_action "Remove power-profiles-daemon and install tlp?"; then
            info "Cancelled — tlp was not installed."
            return 0
        fi
        if ! sudo apt remove -y power-profiles-daemon > /dev/null 2>&1; then
            failure "Failed to remove power-profiles-daemon."
            return 1
        fi
    fi
    if sudo apt install -y tlp tlp-rdw > /dev/null 2>&1; then
        sudo systemctl enable tlp > /dev/null 2>&1
        sudo systemctl start tlp > /dev/null 2>&1
        success "tlp installed and enabled."
        return 0
    else
        failure "Failed to install tlp."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# limit_journal() — Cap the systemd journal at 100M
#
# Writes the drop-in $JOURNALD_DROPIN (SystemMaxUse=100M), restarts
# systemd-journald and vacuums the existing logs down to the new cap so
# the space is reclaimed immediately.
#
# Globals:   DRY_RUN (read); JOURNALD_DROPIN (read)
# Arguments: none
# Returns:   0 — limit applied (or previewed in dry-run)
#            1 — a step failed (the failing step is reported)
# ───────────────────────────────────────────────────────────────────────────────
limit_journal() {
    header "Limit System Journal Size"
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] journal size would be limited to 100M."
        return 0
    fi
    if ! sudo mkdir -p /etc/systemd/journald.conf.d; then
        failure "Failed to create journald.conf.d."
        return 1
    fi
    if ! printf "[Journal]\nSystemMaxUse=100M\n" | sudo tee "$JOURNALD_DROPIN" > /dev/null; then
        failure "Failed to write the journald config file."
        return 1
    fi
    if ! sudo systemctl restart systemd-journald 2> /dev/null; then
        failure "Failed to restart systemd-journald."
        return 1
    fi
    # Apply the new cap to existing logs
    sudo journalctl --vacuum-size=100M > /dev/null 2>&1
    success "Journal size limited to 100M."
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# all_system_opts() — Run every system/memory optimization in order
#
# Sequence behind --system, --optimize and the System & Memory menu's
# "run all" entry: memory values, noatime, extra services, preload, tlp
# and journal cap. Each step reports its own status; a failure does not
# stop the chain.
#
# Arguments: none
# Returns:   exit status of the last step (limit_journal)
# ───────────────────────────────────────────────────────────────────────────────
all_system_opts() {
    optimize_memory
    set_noatime
    disable_extra_services
    install_preload
    install_tlp
    limit_journal
}

# ── Security & passwords ────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# extend_sudo_timeout() — Extend the sudo password timeout to 120 min
#
# Writes Defaults timestamp_timeout=120 into $SUDOERS_TIMEOUT_FILE (mode
# 440) unless a value is already configured. The file is validated with
# `visudo -c` before it is left in place — an invalid file is removed
# again, so sudoers itself is never broken.
#
# Globals:   DRY_RUN (read); SUDOERS_TIMEOUT_FILE (read)
# Arguments: none
# Returns:   0 — timeout set, already configured, or previewed in dry-run
#            1 — the file was invalid (removed) or could not be written
# ───────────────────────────────────────────────────────────────────────────────
extend_sudo_timeout() {
    header "Extend the sudo password timeout"
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] sudo password timeout would be extended to 120 minutes."
        return 0
    fi
    if sudo test -f "$SUDOERS_TIMEOUT_FILE" && sudo grep -q "timestamp_timeout" "$SUDOERS_TIMEOUT_FILE" 2>/dev/null; then
        info "timestamp_timeout is already set: $(sudo grep -o 'timestamp_timeout=[0-9]*' "$SUDOERS_TIMEOUT_FILE" 2>/dev/null | head -n 1)"
        return 0
    fi
    echo "Defaults timestamp_timeout=120" | sudo tee "$SUDOERS_TIMEOUT_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_TIMEOUT_FILE"
    # Validate with visudo before applying — an invalid file is removed automatically
    if sudo visudo -c -f "$SUDOERS_TIMEOUT_FILE" > /dev/null 2>&1; then
        success "sudo password timeout extended to 120 minutes."
        return 0
    else
        sudo rm -f "$SUDOERS_TIMEOUT_FILE"
        failure "The file was invalid and has been removed. sudoers is untouched."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# setup_polkit_rule() — Create a passwordless-polkit rule for sudo users
#
# Security trade-off, stated up front: administrative apps stop asking for
# a password. The rule is scoped to local active sessions
# (subject.local && subject.active) — SSH/remote sessions still require
# one. Written to $POLKIT_RULE_FILE and activated by restarting polkit.
#
# Globals:   DRY_RUN (read); POLKIT_RULE_FILE (read);
#            ASSUME_YES (read via confirm_action)
# Arguments: none
# Returns:   0 — rule created, declined, or previewed in dry-run
#            1 — writing the rule or restarting polkit failed
# ───────────────────────────────────────────────────────────────────────────────
setup_polkit_rule() {
    header "Create a polkit rule for graphical apps"
    warn "⚠ This rule grants passwordless polkit approval to the sudo group."
    warn "⚠ Administrative apps will no longer ask for a password (slightly lower security)."
    warn "⚠ The rule is limited to local active sessions — SSH sessions are not covered."
    if ! confirm_action "Continue?"; then
        info "Cancelled."
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] the polkit rule would be created (local active sessions only)."
        return 0
    fi
    sudo mkdir -p /etc/polkit-1/rules.d
    # subject.local && subject.active → local active sessions only (not SSH/remote)
    if ! printf '%s\n' \
        'polkit.addRule(function(action, subject) {' \
        '    if (subject.isInGroup("sudo") && subject.local && subject.active) {' \
        '        return polkit.Result.YES;' \
        '    }' \
        '});' | sudo tee "$POLKIT_RULE_FILE" > /dev/null; then
        failure "Failed to write the polkit rule."
        return 1
    fi
    if sudo systemctl restart polkit 2> /dev/null; then
        success "polkit rule created and polkit restarted."
        return 0
    else
        failure "Failed to restart polkit."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# all_security_opts() — Run both security settings in order
#
# Sequence behind --security and the Security & Passwords menu's "run
# both" entry: the sudo timeout extension, then the polkit rule. Each step
# reports its own status; a failure does not stop the chain.
#
# Arguments: none
# Returns:   exit status of the last step (setup_polkit_rule)
# ───────────────────────────────────────────────────────────────────────────────
all_security_opts() {
    extend_sudo_timeout
    setup_polkit_rule
}

# ── Time & NTP ──────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# fix_time() — Synchronize the system clock with chrony
#
# Installs chrony when missing and disables systemd-timesyncd (two NTP
# daemons conflict). Sync is attempted twice: `chronyc makestep` against
# the running daemon (polled up to five times, one second apart), then a
# one-shot `chronyd -q` with the daemon stopped temporarily. A failed sync
# is warned about, not propagated — chrony keeps retrying in the
# background. The RTC is synced from the system clock at the end.
#
# Globals:   DRY_RUN (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
fix_time() {
    header "Fix System Time"
    if ! pkg_installed chrony; then
        info "Installing chrony..."
        sudo apt install -y chrony > /dev/null 2>&1 || { failure "Failed to install chrony."; return 1; }
    fi
    # timesyncd is disabled when active (two NTP daemons conflict)
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        sudo systemctl disable --now systemd-timesyncd > /dev/null 2>&1
    fi
    sudo systemctl enable --now chrony > /dev/null 2>&1

    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] chrony would be enabled and the time synchronized."
        return 0
    fi

    local synced=0

    # Method 1: request an immediate sync from the running daemon
    if systemctl is-active --quiet chrony 2>/dev/null; then
        sudo chronyc makestep > /dev/null 2>&1
        for _ in 1 2 3 4 5; do
            if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
                synced=1
                break
            fi
            sleep 1
        done
    fi

    # Method 2: one-shot standalone sync — the daemon is stopped temporarily
    if [ "$synced" = "0" ] && command -v chronyd > /dev/null 2>&1; then
        sudo systemctl stop chrony > /dev/null 2>&1
        if sudo chronyd -q 'pool pool.ntp.org iburst' > /dev/null 2>&1; then
            synced=1
        fi
        sudo systemctl start chrony > /dev/null 2>&1
    fi

    if [ "$synced" = "1" ]; then
        success "System time synchronized."
    else
        warn "NTP sync could not be completed right now."
        warn "Common cause: NTP port (UDP 123) blocked by the ISP or a firewall."
        info "chrony keeps retrying in the background."
    fi

    sudo hwclock --systohc 2> /dev/null
    info "Current time: $(date)"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# show_time_status() — Show the current time-sync status
#
# Prints `timedatectl status` and, when chrony is installed and running,
# appends the head of `chronyc tracking` for quick diagnostics. Read-only.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
show_time_status() {
    header "System Time Status"
    timedatectl status
    if command -v chronyc > /dev/null 2>&1 && systemctl is-active --quiet chrony 2>/dev/null; then
        echo ""
        echo -e "${BOLD}chrony status:${NC}"
        chronyc tracking 2>/dev/null | head -n 12
    fi
    return 0
}
