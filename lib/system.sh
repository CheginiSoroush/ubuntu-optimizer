# shellcheck shell=bash
# ============================================================
#   lib/system.sh — system/memory optimization + security + time
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

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

set_noatime() {
    header "Add noatime to /etc/fstab"
    # Only the root partition line is checked — not any noatime in the file
    if sed -n '/^[^#]*[[:space:]]\/[[:space:]]/p' /etc/fstab 2>/dev/null | grep -q "noatime"; then
        info "noatime is already enabled on the root partition."
        return 0
    fi
    sudo cp /etc/fstab /etc/fstab.bak
    info "Backup created: /etc/fstab.bak"
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

disable_extra_services() {
    header "Disable Extra Services"
    warn "Disabling avahi-daemon breaks network printer discovery (mDNS)."
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

install_preload() {
    header "Install preload (adaptive prefetcher)"
    if pkg_installed preload; then
        info "preload is already installed."
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

limit_journal() {
    header "Limit System Journal Size"
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

all_system_opts() {
    optimize_memory
    set_noatime
    disable_extra_services
    install_preload
    install_tlp
    limit_journal
}

# ============================================================
#   Security & passwords
# ============================================================

extend_sudo_timeout() {
    header "Extend the sudo password timeout"
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

setup_polkit_rule() {
    header "Create a polkit rule for graphical apps"
    warn "⚠ This rule grants passwordless polkit approval to the sudo group."
    warn "⚠ Administrative apps will no longer ask for a password (slightly lower security)."
    warn "⚠ The rule is limited to local active sessions — SSH sessions are not covered."
    if ! confirm_action "Continue?"; then
        info "Cancelled."
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

all_security_opts() {
    extend_sudo_timeout
    setup_polkit_rule
}

# ============================================================
#   Time & NTP
# ============================================================

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
