# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/packages.sh
# ───────────────────────────────────────────────────────────────────────────────
#  apt-based package installs: everyday tools, archive tools, .deb files,
#  nodejs/npm and AppClean. Entry point: submenu 7 (Install Packages & Apps)
#  of the interactive menu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# install_essential_tools() — install the everyday toolkit via apt
#
# One-shot apt install of curl, wget, git, synaptic, iw, net-tools and
# gnome-tweaks.
#
# Arguments: none
# Returns:   0 — apt install succeeded
#            1 — apt install failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# install_unrar() — install archive tools (unrar, p7zip, file-roller)
#
# On failure, checks whether unrar is visible to apt-cache and, when it is
# not, hints that the multiverse repository must be enabled — the unrar
# package only exists there.
#
# Arguments: none
# Returns:   0 — install succeeded
#            1 — install failed (with a multiverse hint when applicable)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# install_deb() — install a local .deb file interactively
#
# Prompts for the file path (~ expanded), prefixes ./ to bare names so apt
# does not mistake them for package names, and validates existence and the
# .deb extension. Installs with apt; on failure falls back to dpkg -i and
# repairs dependencies with apt --fix-broken.
#
# Arguments: none — the file path is prompted interactively
# Returns:   0 — package installed (directly or via the dpkg fallback)
#            1 — cancelled (EOF), file missing/wrong extension, or both
#                install attempts failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# install_appclean() — install AppClean globally via npm
#
# Requires node and npm (checked up front with a pointer to the nodejs
# menu entry); installs the pinned appclean@2.0.0 with npm -g under sudo.
#
# Arguments: none
# Returns:   0 — AppClean installed
#            1 — node/npm missing or the npm install failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# install_nodejs() — install nodejs and npm from apt
#
# Idempotent: when both packages are already installed, the current
# versions are reported and nothing is installed; otherwise apt installs
# them and the versions are shown afterwards.
#
# Arguments: none
# Returns:   0 — both packages present (installed or already there)
#            1 — apt install failed
# ───────────────────────────────────────────────────────────────────────────────
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
