# shellcheck shell=bash
# ============================================================
#   lib/targz.sh — smart tar.gz application installer
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Detects the main executable, checks the architecture,
#   installs missing dependencies and registers the app.
#   In UO_AUTO=1 mode (the GitHub flow) it runs non-interactively.
# ============================================================

# Sanitize an app name — only letters/digits/underscore/dash allowed
sanitize_app_name() {
    printf '%s' "$1" | tr -cd '[:alnum:]_-'
}

# Pick the main executable of the package
# Priority: AppImage → exact name match → partial match (no .bin) →
# only candidate → in UO_AUTO the first candidate, otherwise user choice
# Electron/JVM helper tools are skipped.
# The list is sorted so automatic choices are deterministic.
pick_executable() {   # $1=package dir  $2=app name  → output: SELECTED_EXEC
    SELECTED_EXEC=""
    local dir="$1" app="$2" f base_norm app_norm choice i
    app_norm=$(normalize_name "$app")

    local -a all=() matched=()
    mapfile -t all < <(find "$dir" -type f -executable \
        ! -name "*.so*" \
        ! -name "chrome-sandbox" ! -name "chrome_crashpad_handler" \
        ! -name "crashpad_handler" ! -name "jspawnhelper" 2>/dev/null | sort)
    [ ${#all[@]} -gt 0 ] || return 1

    for f in "${all[@]}"; do
        basename "$f" | grep -qi appimage && { SELECTED_EXEC="$f"; return 0; }
    done

    for f in "${all[@]}"; do
        base_norm=$(normalize_name "$(basename "$f")")
        [ "$base_norm" = "$app_norm" ] && matched+=("$f")
    done

    if [ ${#matched[@]} -eq 0 ]; then
        for f in "${all[@]}"; do
            base_norm=$(normalize_name "$(basename "$f")")
            [[ "$base_norm" == *"$app_norm"* ]] && matched+=("$f")
        done
    fi

    if [ ${#matched[@]} -ge 1 ]; then
        # In Electron packages the launcher is the file without the .bin suffix
        for f in "${matched[@]}"; do
            [[ "$f" != *.bin ]] && { SELECTED_EXEC="$f"; return 0; }
        done
        SELECTED_EXEC="${matched[0]}"
        return 0
    fi

    if [ ${#all[@]} -eq 1 ]; then
        SELECTED_EXEC="${all[0]}"
        return 0
    fi

    if [ "${UO_AUTO:-0}" = "1" ]; then
        warn "Multiple equivalent executables — picked the first: $(basename "${all[0]}")"
        SELECTED_EXEC="${all[0]}"
        return 0
    fi
    warn "Multiple executables found; which one is the main program?"
    i=1
    for f in "${all[@]}"; do
        echo "   $i) $(realpath --relative-to="$dir" "$f" 2>/dev/null || basename "$f")"
        i=$((i + 1))
    done
    # EOF (Ctrl+D) or invalid input → cancel
    read -r -p "   Number of the main executable: " choice || return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#all[@]}" ]; then
        SELECTED_EXEC="${all[$((choice-1))]}"
        return 0
    fi
    return 1
}

# Map a missing library to a deb package — several names for different Ubuntu versions
lib_pkg_candidates() {
    case "$1" in
        libwebkit2gtk-4.0*|libjavascriptcoregtk-4.0*) echo "libwebkit2gtk-4.0-37" ;;
        libwebkit2gtk-4.1*|libjavascriptcoregtk-4.1*) echo "libwebkit2gtk-4.1-0" ;;
        libfuse.so.2)             echo "libfuse2t64 libfuse2" ;;
        libgtk-3.so.0)            echo "libgtk-3-0t64 libgtk-3-0" ;;
        libgtk-4.so.1)            echo "libgtk-4-1" ;;
        libnss3.so)               echo "libnss3" ;;
        libasound.so.2)           echo "libasound2t64 libasound2" ;;
        libXss.so.1)              echo "libxss1" ;;
        libgbm.so.1)              echo "libgbm1" ;;
        libatk-bridge*)           echo "libatk-bridge2.0-0t64 libatk-bridge2.0-0" ;;
        libayatana-appindicator*) echo "libayatana-appindicator3-1" ;;
        *) echo "" ;;
    esac
}

# Detect missing dependencies with ldd and install them automatically
fix_binary_deps() {   # $1 = executable path
    local bin="$1" out missing lib pkg sibling
    # If the file is a launcher script, the real binary (.bin) next to it is checked
    if head -c 2 "$bin" 2>/dev/null | grep -q '#!'; then
        sibling=$(find "$(dirname "$bin")" -maxdepth 1 -type f \
                  -name "$(basename "$bin").bin" 2>/dev/null | head -1)
        [ -n "$sibling" ] && bin="$sibling"
    fi

    out=$(ldd "$bin" 2>&1)
    echo "$out" | grep -q "not a dynamic executable" && return 0

    missing=$(echo "$out" | grep "not found" | awk '{print $1}' | sort -u)
    [ -z "$missing" ] && return 0

    warn "These libraries are missing from the system:"
    # shellcheck disable=SC2086  # intentional word splitting: one library per line
    printf '      • %s\n' $missing

    for lib in $missing; do
        for pkg in $(lib_pkg_candidates "$lib"); do
            if apt-cache show "$pkg" > /dev/null 2>&1; then
                if sudo apt install -y "$pkg" > /dev/null 2>&1; then
                    success "Installed: $pkg"
                    break
                fi
            fi
        done
    done

    missing=$(ldd "$bin" 2>/dev/null | grep "not found" | awk '{print $1}' | sort -u)
    if [ -z "$missing" ]; then
        success "All dependencies are satisfied."
        return 0
    fi
    failure "These libraries are still not installed:"
    # shellcheck disable=SC2086  # intentional word splitting: one library per line
    printf '      • %s\n' $missing
    info "Hint: apt search <part of the library name>"
    return 1
}

# Check package/system architecture compatibility
check_package_arch() {   # $1 = install root  $2 = main executable
    local root="$1" target="$2" f info arch sys_arch compatible

    command -v file > /dev/null 2>&1 || sudo apt install -y file > /dev/null 2>&1
    command -v file > /dev/null 2>&1 || { info "'file' is unavailable; architecture check skipped."; return 0; }

    # If the main executable is a script, the first ELF binary of the package is checked
    if head -c 2 "$target" 2>/dev/null | grep -q '#!'; then
        while IFS= read -r f; do
            if file -b "$f" 2>/dev/null | grep -q 'ELF'; then
                target="$f"
                break
            fi
        done < <(find "$root" -type f -executable ! -name "*.so*" \
                    ! -name "chrome-sandbox" ! -name "chrome_crashpad_handler" \
                    ! -name "jspawnhelper" 2>/dev/null)
    fi

    info=$(file -b "$target" 2>/dev/null)
    echo "$info" | grep -q 'ELF' || return 0

    sys_arch=$(uname -m)
    if   echo "$info" | grep -q 'x86-64';  then arch="x86_64"
    elif echo "$info" | grep -q 'aarch64'; then arch="aarch64"
    elif echo "$info" | grep -q 'ARM,';    then arch="arm"
    elif echo "$info" | grep -q '80386';   then arch="i386"
    else return 0; fi

    compatible="no"
    case "$sys_arch" in
        x86_64)  if [ "$arch" = "x86_64" ] || [ "$arch" = "i386" ]; then compatible="yes"; fi ;;
        aarch64) if [ "$arch" = "aarch64" ]; then compatible="yes"; fi ;;
        # Other architectures: only an exact match is acceptable
        *)       [ "$arch" = "$sys_arch" ] && compatible="yes" ;;
    esac
    [ "$compatible" = "yes" ] && return 0

    failure "Package architecture is incompatible with this system!"
    warn "Package arch: $arch  |  System arch: $sys_arch"
    case "$sys_arch" in
        x86_64)  warn "→ Download the 'amd64' or 'x64' build of the app." ;;
        aarch64) warn "→ Download the 'arm64' or 'aarch64' build of the app." ;;
    esac
    return 1
}

# Remove registry entries pointing at a specific install dir but with a
# different name — prevents stale entries after renaming
registry_remove_by_dir() {   # $1=install dir  $2=allowed name (kept)
    [ -f "$REGISTRY_DB" ] || return 0
    local tmp="$REGISTRY_DB.tmp"
    awk -F'|' -v dir="$1" -v keep="$2" \
        '!($3 == dir && $1 != keep)' "$REGISTRY_DB" > "$tmp" 2>/dev/null
    mv "$tmp" "$REGISTRY_DB"
    return 0
}

# Escape a path for the Exec value of a desktop file — per the freedesktop spec
# Reserved characters are backslash-escaped and spaces become "\ "
desktop_escape_path() {   # $1=path
    printf '%s' "$1" | sed -e 's/\([\\"$&()*;<>~|`#]\)/\\\1/g' -e 's/ /\\ /g'
}

# Install an app from a tar.gz file — shared logic for install and update
targz_install_from_file() {   # $1=file path  $2=app name
    local TARGZ_PATH="$1" APP_NAME="$2"

    # Sanitize and validate the name — an empty name would lead to the dangerous /opt/ path
    APP_NAME=$(sanitize_app_name "$APP_NAME")
    [ -n "$APP_NAME" ] || { failure "Invalid app name."; return 1; }

    local TEMP_DIR SRC_DIR n first
    TEMP_DIR=$(mktemp -d) || return 1
    info "Extracting..."
    if ! tar -xzf "$TARGZ_PATH" -C "$TEMP_DIR"; then
        failure "Failed to extract: $TARGZ_PATH"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    success "Extracted."

    # Detect the archive layout: single root folder or top-level files
    n=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -printf "%f\n" 2>/dev/null | wc -l)
    first=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -printf "%f\n" 2>/dev/null | sort | head -1)
    if [ "$n" -eq 1 ] && [ -d "$TEMP_DIR/$first" ]; then
        SRC_DIR="$TEMP_DIR/$first"
    else
        SRC_DIR="$TEMP_DIR"
    fi

    if ! pick_executable "$SRC_DIR" "$APP_NAME"; then
        failure "Main executable not found. Package contents:"
        ls -la "$SRC_DIR"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    local EXEC_FILE="$SELECTED_EXEC"
    info "Main executable: $EXEC_FILE"

    local INSTALL_DIR="/opt/$APP_NAME"
    if [ -d "$INSTALL_DIR" ]; then
        warn "Directory $INSTALL_DIR already exists."
        if [ "${UO_AUTO:-0}" = "1" ]; then
            info "(automatic remove & reinstall)"
            sudo rm -rf "$INSTALL_DIR"
        elif confirm_action "Remove and reinstall?"; then
            sudo rm -rf "$INSTALL_DIR"
        else
            info "Cancelled."
            rm -rf "$TEMP_DIR"
            return 0
        fi
    fi

    sudo mv "$SRC_DIR" "$INSTALL_DIR"
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    success "App moved to $INSTALL_DIR."

    local FINAL_EXEC="$INSTALL_DIR${EXEC_FILE#"$SRC_DIR"}"

    if ! check_package_arch "$INSTALL_DIR" "$FINAL_EXEC"; then
        warn "Install cancelled; incomplete files are removed."
        sudo rm -rf "$INSTALL_DIR"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Dependency install — a failure does not abort the install but is warned about
    if ! fix_binary_deps "$FINAL_EXEC"; then
        warn "The app may not run until the libraries above are installed."
    fi

    sudo ln -sf "$FINAL_EXEC" "/usr/local/bin/$APP_NAME"
    success "Terminal command: /usr/local/bin/$APP_NAME"

    # Icon: the largest image found in the package
    local ICON_FILE
    ICON_FILE=$(find "$INSTALL_DIR" -type f \( -iname "*.png" -o -iname "*.svg" \) \
                -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    ICON_FILE=${ICON_FILE:-applications-other}

    local DESKTOP_FILE="/usr/share/applications/$APP_NAME.desktop"
    # Exec is escaped per the freedesktop spec
    cat << EOF | sudo tee "$DESKTOP_FILE" > /dev/null
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Installed by Ubuntu Optimizer
Exec=$(desktop_escape_path "$FINAL_EXEC")
Path=$INSTALL_DIR
Icon=$ICON_FILE
Terminal=false
Categories=Utility;
EOF
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1

    rm -rf "$TEMP_DIR"

    # Before registering, stale entries with a different name but the same dir are removed
    registry_remove_by_dir "$INSTALL_DIR" "$APP_NAME"
    registry_add "$APP_NAME" "$(guess_version "$TARGZ_PATH")" \
                 "$INSTALL_DIR" "$FINAL_EXEC" "$DESKTOP_FILE" "$(basename "$TARGZ_PATH")"

    success "🎉 $APP_NAME installed/updated."
    info "Run from terminal: $APP_NAME"

    # Test run only in interactive mode
    if [ "${UO_AUTO:-0}" = "1" ]; then
        info "(test run skipped in automatic mode)"
    elif confirm_action "Launch it now to verify it works?"; then
        (cd "$INSTALL_DIR" && nohup "$FINAL_EXEC" > /dev/null 2>&1 &)
        info "If no window opens, run '$APP_NAME' in a terminal to see the error."
    fi
    return 0
}

# Interactive install from the menu
install_targz() {
    header "Install an App from a .tar.gz File"
    echo "   For apps that are distributed only as an archive."
    echo "   • Automatic detection of the main executable"
    echo "   • Package architecture check"
    echo "   • Automatic install of missing dependencies"
    echo "   • Registry entry (for later removal & updates)"
    echo ""

    local TARGZ_PATH APP_NAME
    read -r -p "   Full path of the .tar.gz file (e.g. ~/Downloads/app.tar.gz): " TARGZ_PATH || return 1
    TARGZ_PATH=${TARGZ_PATH/#\~/$HOME}
    [ -f "$TARGZ_PATH" ] || { failure "File not found: $TARGZ_PATH"; return 1; }
    [[ "$TARGZ_PATH" =~ \.tar\.gz$ || "$TARGZ_PATH" =~ \.tgz$ ]] || { failure "The file extension must be .tar.gz or .tgz."; return 1; }

    read -r -p "   App name (e.g. ab-download-manager): " APP_NAME || return 1
    APP_NAME=$(sanitize_app_name "$APP_NAME")
    [ -n "$APP_NAME" ] || { failure "Invalid app name (only letters, digits, - and _)."; return 1; }

    targz_install_from_file "$TARGZ_PATH" "$APP_NAME"
}

# CLI install — $1=file path  $2=optional name
install_targz_cli() {
    local TARGZ_PATH="$1" APP_NAME="$2"

    TARGZ_PATH=${TARGZ_PATH/#\~/$HOME}
    [ -f "$TARGZ_PATH" ] || { failure "File not found: $TARGZ_PATH"; return 1; }
    [[ "$TARGZ_PATH" =~ \.tar\.gz$ || "$TARGZ_PATH" =~ \.tgz$ ]] || { failure "The file extension must be .tar.gz or .tgz."; return 1; }

    if [ -z "$APP_NAME" ]; then
        APP_NAME=$(name_from_archive "$TARGZ_PATH")
        if [ -z "$APP_NAME" ]; then
            failure "The app name could not be derived from the file name."
            info "Specify it explicitly: --install-targz <file> <name>"
            return 1
        fi
        info "Name derived from the file: $APP_NAME"
    fi
    APP_NAME=$(sanitize_app_name "$APP_NAME")
    [ -n "$APP_NAME" ] || { failure "Invalid app name."; return 1; }

    targz_install_from_file "$TARGZ_PATH" "$APP_NAME"
}
