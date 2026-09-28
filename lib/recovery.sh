# shellcheck shell=bash
# ============================================================
#   lib/recovery.sh — system recovery and advanced tools
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

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

reinstall_desktop() {
    header "Reinstall the Desktop Environment"
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
