# shellcheck shell=bash
# ============================================================
#   lib/packages.sh — install packages and apps from apt repos
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

install_essential_tools() {
    header "Install Essential Tools"
    if sudo apt install -y curl wget git synaptic iw net-tools gnome-tweaks; then
        success "Essential tools installed."
        return 0
    else
        failure "Failed to install the tools."
        return 1
    fi
}

install_unrar() {
    header "Install Archive Tools (unrar, p7zip, file-roller)"
    if sudo apt install -y unrar p7zip-full file-roller; then
        success "Archive tools installed."
        return 0
    fi
    failure "Failed to install the tools."
    # The unrar package is only in the multiverse repository
    if ! apt-cache show unrar > /dev/null 2>&1; then
        info "The unrar package is not in the enabled repos — enable multiverse:"
        info "  sudo add-apt-repository multiverse && sudo apt update"
    fi
    return 1
}

install_deb() {
    header "Install a .deb File"
    local DEB_PATH
    # EOF (Ctrl+D) → cancel
    read -r -p "   Full path of the .deb file: " DEB_PATH || return 1
    DEB_PATH=${DEB_PATH/#\~/$HOME}

    # A path without '/' is interpreted as a package name — prefix ./ for a file
    [[ "$DEB_PATH" == */* ]] || DEB_PATH="./$DEB_PATH"

    if [ ! -f "$DEB_PATH" ]; then
        failure "File not found: $DEB_PATH"
        return 1
    fi
    if [[ ! "$DEB_PATH" =~ \.deb$ ]]; then
        failure "The file must have a .deb extension."
        return 1
    fi

    info "Installing the package..."
    if sudo apt install -y "$DEB_PATH"; then
        success "Package installed successfully."
        return 0
    fi
    warn "apt install failed; trying dpkg..."
    if sudo dpkg -i "$DEB_PATH"; then
        sudo apt --fix-broken install -y > /dev/null 2>&1
        success "Package installed (with dependencies fixed)."
        return 0
    fi
    failure "Failed to install the package."
    return 1
}

install_appclean() {
    header "Install AppClean"
    if ! command -v node > /dev/null 2>&1; then
        failure "nodejs is not installed. Install nodejs from this menu first."
        return 1
    fi
    if ! command -v npm > /dev/null 2>&1; then
        failure "npm is not installed. Install nodejs and npm from this menu first."
        return 1
    fi
    if sudo npm install -g appclean@2.0.0 > /dev/null 2>&1; then
        success "AppClean installed. Run with: appclean gui"
        return 0
    else
        failure "Failed to install AppClean."
        return 1
    fi
}

install_nodejs() {
    header "Install nodejs and npm"
    if pkg_installed nodejs && pkg_installed npm; then
        info "nodejs and npm are already installed."
        info "Versions: node $(node --version 2>/dev/null) | npm $(npm --version 2>/dev/null)"
        return 0
    fi
    if sudo apt install -y nodejs npm; then
        success "nodejs and npm installed."
        info "Versions: node $(node --version 2>/dev/null) | npm $(npm --version 2>/dev/null)"
        return 0
    fi
    failure "Failed to install nodejs."
    return 1
}
