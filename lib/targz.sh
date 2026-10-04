# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/targz.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Smart installer for apps distributed as .tar.gz archives or AppImages:
#  detects the main executable, checks the package architecture, installs
#  missing library dependencies and registers the app for later removal
#  and updates. In UO_AUTO=1 mode (the GitHub flow) it runs non-interactively.
#
#  Reached from the “Install Packages & Apps” menu and the CLI flag
#  --install-targz FILE [NAME]; reused by lib/github.sh and
#  lib/snapflatpak.sh for downloaded release assets.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# sanitize_app_name() — reduce an app name to a safe character set
#
# Keeps only letters, digits, underscore and dash, so the result can be
# embedded safely in /opt paths, /usr/local/bin symlink names and desktop
# file names. Pure Bash pattern substitution — no tr process is forked,
# which matters because this sits on several hot paths.
#
# Arguments: $1 — raw app name
# ───────────────────────────────────────────────────────────────────────────────
sanitize_app_name() {
    printf '%s' "${1//[![:alnum:]_-]/}"
}

# ───────────────────────────────────────────────────────────────────────────────
# pick_executable() — pick the main executable of an extracted package
#
# Scans the package for executable files, skipping shared libraries and
# Electron/JVM helper tools, and fills SELECTED_EXEC. The candidate list is
# sorted, so automatic choices stay deterministic. Priority: AppImage →
# exact normalized name match → partial match (preferring a file without a
# .bin suffix, since Electron launchers sit next to their .bin payload) →
# the only candidate → in UO_AUTO mode the first candidate, otherwise an
# interactive numbered choice (EOF or invalid input cancels).
#
# Globals:   SELECTED_EXEC — written; the chosen path (empty when not found)
#            UO_AUTO — read; "1" suppresses the interactive prompt
# Arguments: $1 — extracted package directory
#            $2 — app name used for matching
# Returns:   0 — an executable was selected
#            1 — no candidate found, or the user cancelled
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# lib_pkg_candidates() — map a missing library to deb package candidates
#
# Prints one or more candidate package names for a library reported missing
# by ldd; several names cover different Ubuntu releases (the 24.04 t64
# transition renamed many library packages). The first candidate that apt
# can actually install wins.
#
# Arguments: $1 — library file name (e.g. libwebkit2gtk-4.1.so.0)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# fix_binary_deps() — detect and auto-install missing shared libraries
#
# Runs ldd on the executable and installs each missing library through the
# lib_pkg_candidates mapping; when the target is a launcher script, the
# real binary (same name + .bin, the Electron layout) next to it is checked
# instead. A dependency failure only warns — the install itself continues,
# and the user is told which libraries are still missing and how to look
# for them.
#
# Arguments: $1 — executable path
# Returns:   0 — all dependencies satisfied (or nothing was missing)
#            1 — libraries are still missing after the install attempt
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# check_package_arch() — verify package/system architecture compatibility
#
# Inspects the main executable with file(1) — installed on demand — and
# compares the ELF architecture against uname -m; for scripted launchers
# the first ELF binary of the package is inspected instead. x86_64
# additionally accepts i386 builds. A mismatch is a hard stop with a hint
# about which build to download, because the app would not start at all.
#
# Arguments: $1 — install root (searched for a fallback binary)
#            $2 — main executable path
# Returns:   0 — compatible, not an ELF binary, or 'file' unavailable
#            1 — incompatible architecture
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# registry_remove_by_dir() — drop stale registry entries for an install dir
#
# Rewrites the registry without entries that point at the given install
# directory under a different name — a renamed app would otherwise leave
# stale rows behind. The one entry matching the kept name survives. The
# rewrite goes through a temp file, so an awk failure leaves the original
# untouched, and a missing registry is a no-op.
#
# Globals:   REGISTRY_DB — registry file rewritten in place
# Arguments: $1 — install directory to match
#            $2 — app name whose entry is kept
# ───────────────────────────────────────────────────────────────────────────────
registry_remove_by_dir() {   # $1=install dir  $2=allowed name (kept)
    [ -f "$REGISTRY_DB" ] || return 0
    local tmp="$REGISTRY_DB.tmp"
    awk -F'|' -v dir="$1" -v keep="$2" \
        '!($3 == dir && $1 != keep)' "$REGISTRY_DB" > "$tmp" 2>/dev/null
    mv "$tmp" "$REGISTRY_DB"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# desktop_escape_path() — escape a path for a desktop file's Exec value
#
# Backslash-escapes the characters reserved by the freedesktop spec and
# turns spaces into "\ ", so paths with blanks or special characters
# survive the desktop environment's parsing. _desktop_exec_path
# (appmgmt.sh) reverses this transformation exactly.
#
# Arguments: $1 — absolute path
# ───────────────────────────────────────────────────────────────────────────────
desktop_escape_path() {   # $1=path
    printf '%s' "$1" | sed -e 's/\([\\"$&()*;<>~|`#]\)/\\\1/g' -e 's/ /\\ /g'
}

# ───────────────────────────────────────────────────────────────────────────────
# _targz_install_python() — install a Python source package via pipx
#
# Fallback for archives that ship no binary but a pyproject.toml/setup.py:
# they are installed into an isolated pipx venv instead of /opt. pipx is
# installed on demand, and --force makes the same call cover fresh installs
# and reinstalls/updates alike. The temp extraction dir is removed on every
# path through the function.
#
# Arguments: $1 — path to the .tar.gz archive
#            $2 — app name
#            $3 — extracted source directory (currently unused)
#            $4 — temp directory to clean up
# Returns:   0 — installed, or the user declined the install
#            1 — pipx could not be installed, or the install failed
# ───────────────────────────────────────────────────────────────────────────────
_targz_install_python() {   # $1=tar.gz path  $2=app name  $3=src dir  $4=temp dir
    local tar_path="$1" name="$2" src_dir="$3" temp_dir="$4"

    info "This is a Python source package (no binary executable)."
    info "The recommended install method is pipx (isolated virtual environment)."

    if ! command -v pipx > /dev/null 2>&1; then
        info "Installing pipx..."
        if ! sudo apt install -y pipx > /dev/null 2>&1; then
            failure "Failed to install pipx."
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    if ! confirm_action "Install $name with pipx?"; then
        info "Cancelled."
        rm -rf "$temp_dir"
        return 0
    fi

    # --force handles both fresh install and reinstall/update
    info "Installing $name with pipx..."
    if pipx install --force "$tar_path" 2>/dev/null; then
        rm -rf "$temp_dir"
        success "$name installed via pipx."
        info "Run: $name"
        info "Update: uo --github-update"
        info "Remove: pipx uninstall $name  (or: uo --cleanup $name)"
        return 0
    fi

    failure "pipx install failed."
    info "Manual: pipx install $name"
    rm -rf "$temp_dir"
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# targz_install_from_file() — install an app from a .tar.gz archive
#
# Shared engine for interactive installs, CLI installs and updates:
# extract to a temp dir, detect the archive layout, pick the main
# executable (falling back to a pipx install for Python source packages),
# move the tree to /opt/<name>, verify the architecture, repair missing
# libraries, then create the /usr/local/bin symlink, the desktop entry and
# the registry record, and clean up. sudo is authenticated up front so the
# flow is not interrupted mid-extraction; an existing /opt/<name> is
# replaced only after confirmation (automatically in UO_AUTO mode); a
# dependency failure warns but does not abort, while an architecture
# mismatch aborts and removes the partial files.
#
# Globals:   SELECTED_EXEC — consumed from pick_executable
#            UO_AUTO — read; "1" makes the flow fully non-interactive
# Arguments: $1 — path to the .tar.gz/.tgz file
#            $2 — app name (sanitized again internally)
# Returns:   0 — installed/updated, or cancelled by the user
#            1 — invalid name, or extraction/executable/architecture failure
# ───────────────────────────────────────────────────────────────────────────────
targz_install_from_file() {   # $1=file path  $2=app name
    local TARGZ_PATH="$1" APP_NAME="$2"

    # Sanitize and validate the name — an empty name would lead to the dangerous /opt/ path
    APP_NAME=$(sanitize_app_name "$APP_NAME")
    [ -n "$APP_NAME" ] || { failure "Invalid app name."; return 1; }

    # Authenticate sudo up front — extraction/analysis runs first and can
    # take a while; the password should not be requested mid-flow
    sudo_precheck || return 1

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
        # Python source distribution — no binary, but pipx-installable
        if [ -f "$SRC_DIR/pyproject.toml" ] || [ -f "$SRC_DIR/setup.py" ]; then
            _targz_install_python "$TARGZ_PATH" "$APP_NAME" "$SRC_DIR" "$TEMP_DIR"
            return $?
        fi
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

    # Rebase the chosen executable path from the temp dir onto the install dir
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

# ───────────────────────────────────────────────────────────────────────────────
# install_targz() — interactive .tar.gz install (menu entry)
#
# Prompts for the archive path and the app name, validating both (~
# expansion, existence, .tar.gz/.tgz extension, name charset), then
# delegates to targz_install_from_file. Cancelling any prompt aborts with
# no side effects.
#
# Arguments: none
# Returns:   0 — install finished
#            1 — invalid input, or the underlying install failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# install_targz_cli() — CLI front-end for --install-targz FILE [NAME]
#
# Validates the path and extension like the interactive flow; when no name
# is supplied it is derived from the archive file name, and a failed
# derivation is a hard error with the retry hint. Delegates to
# targz_install_from_file.
#
# Arguments: $1 — archive path (~ expanded)
#            $2 — app name (optional)
# Returns:   0 — install finished
#            1 — invalid input, or the underlying install failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ── AppImage installer ─────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# appimage_install_from_file() — install an AppImage file
#
# Copies the AppImage to /opt/<name>/<name>.AppImage, makes it executable,
# creates the /usr/local/bin symlink and a desktop entry. AppImages are
# self-contained — no extraction or dependency resolution is needed — so
# only libfuse2 (absent on Ubuntu 24.04+) is ensured beforehand; the icon
# is mined from the embedded squashfs when possible. Also reused by
# lib/github.sh for downloaded release assets.
#
# Globals:   UO_AUTO — read; "1" replaces an existing install without asking
# Arguments: $1 — path to the .AppImage file
#            $2 — app name (sanitized again internally)
# Returns:   0 — installed, or cancelled by the user
#            1 — invalid name, sudo precheck or libfuse2 failure
# ───────────────────────────────────────────────────────────────────────────────
appimage_install_from_file() {   # $1=AppImage path  $2=app name
    local appimage_path="$1" name="$2" APP_NAME

    # Sanitize and validate name
    APP_NAME=$(sanitize_app_name "$name")
    [ -n "$APP_NAME" ] || { failure "Invalid app name."; return 1; }
    name="$APP_NAME"

    sudo_precheck || return 1

    # libfuse2 check — Ubuntu 24.04+ ships fuse3 only
    if ! ldconfig -p 2>/dev/null | grep -q "libfuse\.so\.2"; then
        info "Installing libfuse2 (required for AppImage)..."
        if ! sudo apt install -y libfuse2t64 > /dev/null 2>&1; then
            sudo apt install -y libfuse2 > /dev/null 2>&1 || {
                failure "Failed to install libfuse2 — required for AppImage."
                return 1
            }
        fi
    fi

    # Install directory
    local install_dir="/opt/$name"
    local appimage_file="$install_dir/$name.AppImage"
    if [ -d "$install_dir" ]; then
        warn "Directory $install_dir already exists."
        if [ "${UO_AUTO:-0}" = "1" ]; then
            info "(automatic remove & reinstall)"
            sudo rm -rf "$install_dir"
        elif confirm_action "Remove and reinstall?"; then
            sudo rm -rf "$install_dir"
        else
            info "Cancelled."
            return 0
        fi
    fi
    sudo mkdir -p "$install_dir"
    sudo cp "$appimage_path" "$appimage_file"
    sudo chmod +x "$appimage_file"
    success "AppImage installed to: $install_dir"

    # Command symlink
    sudo ln -sf "$appimage_file" "/usr/local/bin/$name"
    success "Command: /usr/local/bin/$name"

    # Desktop entry — try to extract from AppImage, fallback to generic
    local desktop_file="/usr/share/applications/$name.desktop"
    local icon="applications-other"
    local tmp_extract
    tmp_extract=$(mktemp -d)
    if (cd "$tmp_extract" && "$appimage_file" --appimage-extract > /dev/null 2>&1); then
        # Find icon from the extracted squashfs-root
        local found_icon
        found_icon=$(find "$tmp_extract" -type f \( -iname "*.png" -o -iname "*.svg" \) \
                     -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "$found_icon" ]; then
            sudo cp "$found_icon" "/usr/local/share/icons/$name.png" 2>/dev/null || true
            [ -f "/usr/local/share/icons/$name.png" ] && icon="$name"
        fi
    fi
    rm -rf "$tmp_extract"

    printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        "Name=$name" \
        'Comment=Installed by Ubuntu Optimizer' \
        "Exec=$(desktop_escape_path "$appimage_file")" \
        "Path=$install_dir" \
        "Icon=$icon" \
        'Terminal=false' \
        'Categories=Utility;' | sudo tee "$desktop_file" > /dev/null

    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1

    # Register
    registry_remove_by_dir "$install_dir" "$name"
    registry_add "$name" "$(guess_version "$appimage_path")" \
                 "$install_dir" "$appimage_file" "$desktop_file" "$(basename "$appimage_path")"

    success "🎉 $name AppImage installed."
    info "Run: $name"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# install_appimage() — interactive AppImage install (menu entry)
#
# Prompts for the .AppImage path and the app name, validates both (~
# expansion, existence, extension, name charset) and delegates to
# appimage_install_from_file.
#
# Arguments: none
# Returns:   0 — install finished
#            1 — invalid input, or the underlying install failed
# ───────────────────────────────────────────────────────────────────────────────
install_appimage() {
    header "Install from AppImage File"
    echo "   • Self-contained — no dependencies needed"
    echo "   • Creates /opt/name/name.AppImage"
    echo "   • Installs desktop entry + terminal command"
    echo "   • Registers in the app registry"
    echo ""

    local APPIMAGE_PATH APP_NAME
    read -r -p "   Path to .AppImage file: " APPIMAGE_PATH || return 1
    APPIMAGE_PATH=${APPIMAGE_PATH/#\~/$HOME}
    [ -f "$APPIMAGE_PATH" ] || { failure "File not found: $APPIMAGE_PATH"; return 1; }
    [[ "$APPIMAGE_PATH" =~ \.AppImage$ ]] || { failure "File must be a .AppImage."; return 1; }

    read -r -p "   App name (e.g. obsidian): " APP_NAME || return 1
    APP_NAME=$(sanitize_app_name "$APP_NAME")
    [ -n "$APP_NAME" ] || { failure "Invalid app name."; return 1; }

    appimage_install_from_file "$APPIMAGE_PATH" "$APP_NAME"
}
