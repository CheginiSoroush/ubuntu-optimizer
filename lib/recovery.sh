# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/recovery.sh
# ───────────────────────────────────────────────────────────────────────────────
#  System rescue and advanced tools: apt/dpkg repair, desktop reinstallation and
#  the VEET deep-removal installer (dangerous). Entry points: submenu 11 (System
#  Recovery & Rescue) and submenu 12 (Advanced Tools — Dangerous).
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# fix_broken() — repair a broken apt/dpkg package state
#
# Runs apt --fix-broken install followed by dpkg --configure -a; the ok flag
# remembers whether either step failed so the combined result is honest.
#
# Arguments: none
# Returns:   0 — both repair steps succeeded
#            1 — at least one step failed
# ───────────────────────────────────────────────────────────────────────────────
fix_broken() {
    header "Fix Broken Packages"
    local ok=1
    sudo apt --fix-broken install -y || ok=0
    sudo dpkg --configure -a || ok=0
    if [ "$ok" -eq 1 ]; then
        success "Repair completed."
        return 0
    else
        failure "Repair incomplete. Check the output above."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# reinstall_desktop() — reinstall the Ubuntu GNOME desktop stack
#
# Asks for confirmation first: besides taking minutes, on other flavors
# (Kubuntu, Xubuntu, ...) this would install GNOME next to the existing
# desktop rather than repairing it. Reinstalls ubuntu-desktop,
# gnome-shell, gdm3, nautilus and gnome-terminal; a reboot is recommended
# afterwards.
#
# Arguments: none
# Returns:   0 — reinstall completed, or user declined
#            1 — apt reinstall failed
# ───────────────────────────────────────────────────────────────────────────────
reinstall_desktop() {
    header "Reinstall the Desktop Environment"
    warn "This reinstalls the Ubuntu GNOME desktop stack (ubuntu-desktop, gnome-shell, gdm3, ...)."
    warn "On other flavors (Kubuntu, Xubuntu, ...) it would install GNOME next to your desktop."
    confirm_action "Continue?" || { info "Cancelled."; return 0; }
    warn "This may take several minutes..."
    if sudo apt install --reinstall -y ubuntu-desktop ubuntu-desktop-minimal gnome-shell gdm3 nautilus gnome-terminal; then
        success "Desktop environment reinstalled."
        info "Please reboot the system."
        return 0
    else
        failure "Failed to reinstall the desktop environment."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# fix_dpkg_configure() — finish pending dpkg package configuration
#
# Runs dpkg --configure -a to configure packages left unconfigured by an
# interrupted install or upgrade.
#
# Arguments: none
# Returns:   0 — configuration completed
#            1 — dpkg failed
# ───────────────────────────────────────────────────────────────────────────────
fix_dpkg_configure() {
    header "Configure Pending Packages with dpkg"
    if sudo dpkg --configure -a; then
        success "Package configuration completed."
        return 0
    else
        failure "Failed to configure packages."
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# install_veet() — build and install the VEET deep-removal tool (dangerous)
#
# Double-warned and confirmed: VEET can accidentally remove system
# packages, so it must only ever be aimed at user applications. Installs
# golang and make when missing, clones (or best-effort updates)
# github.com/swadhinbiswas/veet into ~/veet, builds it with make, installs
# via 'make install' or a manual binary copy, and verifies that
# /usr/local/bin/veet actually exists at the end.
#
# Arguments: none
# Returns:   0 — VEET installed and verified, or user declined
#            1 — prerequisites, download, build or installation failed
# ───────────────────────────────────────────────────────────────────────────────
install_veet() {
    header "Install VEET (Deep Removal Tool)"
    warn "⚠ Warning: VEET can accidentally remove system packages!"
    warn "⚠ Only remove user applications with it, never system packages."
    confirm_action "Continue?" || { info "Cancelled."; return 0; }

    if ! command -v go > /dev/null 2>&1; then
        info "Installing golang..."
        sudo apt install -y golang > /dev/null 2>&1 || { failure "Failed to install golang."; return 1; }
    fi
    if ! command -v make > /dev/null 2>&1; then
        info "Installing make..."
        sudo apt install -y make > /dev/null 2>&1 || { failure "Failed to install make."; return 1; }
    fi

    if [ ! -d "$HOME/veet/.git" ]; then
        info "Downloading the VEET source..."
        git clone https://github.com/swadhinbiswas/veet.git "$HOME/veet" \
            || { failure "Download failed (check your internet or the repo URL)."; return 1; }
    else
        # The existing source is updated (best-effort)
        info "Updating the VEET source..."
        git -C "$HOME/veet" pull --ff-only > /dev/null 2>&1 \
            || warn "Update failed — continuing with the existing version."
    fi

    info "Building the program (may take a while)..."
    if ! (cd "$HOME/veet" && make build); then
        failure "Failed to build VEET."
        return 1
    fi

    # Install: make install or a manual binary copy — existence is verified at the end
    if ! sudo make -C "$HOME/veet" install > /dev/null 2>&1 || [ ! -x /usr/local/bin/veet ]; then
        if [ -f "$HOME/veet/veet" ]; then
            sudo cp "$HOME/veet/veet" /usr/local/bin/veet
            sudo chmod +x /usr/local/bin/veet
        fi
    fi
    if [ -x /usr/local/bin/veet ]; then
        success "VEET installed. Run with: sudo veet"
        return 0
    fi
    failure "The VEET binary was not built/installed."
    return 1
}
