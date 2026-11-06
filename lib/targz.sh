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

    # Free-space guard before any extract/install work happens
    if ! disk_check_install 500; then
        return 1
    fi

    # Authenticate sudo up front — extraction/analysis runs first and can
    # take a while; the password should not be requested mid-flow
    sudo_precheck || return 1

    local TEMP_DIR SRC_DIR first
    local -a top_entries=()
    TEMP_DIR=$(mktemp -d) || return 1
    info "Extracting..."
    if ! tar -xzf "$TARGZ_PATH" -C "$TEMP_DIR"; then
        failure "Failed to extract: $TARGZ_PATH"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    success "Extracted."

    # Detect the archive layout: single root folder or top-level files
    # (one find pass instead of two)
    mapfile -t top_entries < <(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)
    local n=${#top_entries[@]}
    first="${top_entries[0]:-}"
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

    # Free-space guard before the copy (AppImages are usually large)
    if ! disk_check_install 500; then
        return 1
    fi

    # Architecture guard — a mismatched AppImage installs cleanly and then
    # silently refuses to launch, the worst failure mode. The ELF header
    # tells the truth even when the file name says nothing.
    if command -v file > /dev/null 2>&1 && file -b "$appimage_path" 2> /dev/null | grep -qiE "ELF.*(aarch64|arm)"; then
        case "$(uname -m)" in
            aarch64|armv7*|armv8*) : ;;
            *)
                warn "This AppImage is built for ARM, but this machine is $(uname -m)."
                if ! confirm_action "Install it anyway? (it will not run on this machine)"; then
                    info "Cancelled — nothing was installed."
                    return 0
                fi
                ;;
        esac
    fi

    # libfuse2 check — Ubuntu 24.04+ ships fuse3 only
    appimage_ensure_fuse || return 1

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
            # Keep the real extension — an SVG renamed to .png breaks icon lookups
            local icon_ext
            case "${found_icon,,}" in
                *.svg) icon_ext=".svg" ;;
                *)     icon_ext=".png" ;;
            esac
            sudo mkdir -p /usr/local/share/icons
            if sudo cp "$found_icon" "/usr/local/share/icons/$name$icon_ext" 2>/dev/null \
               && [ -f "/usr/local/share/icons/$name$icon_ext" ]; then
                icon="$name"
            fi
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
    appimage_print_launch_hint "$name"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_ensure_fuse() — libfuse2 present, installed and VERIFIED
#
# Ubuntu 24.04+ ships fuse3 only, so AppImages need libfuse2. A silent apt
# failure must never produce a half-installed app that cannot open, so the
# check is re-run after the install attempts — a wrapper function keeps the
# suite able to override it.
#
# Returns:   0 — libfuse.so.2 is available
#            1 — still missing after the install attempts
# ───────────────────────────────────────────────────────────────────────────────
appimage_has_fuse() {
    ldconfig -p 2> /dev/null | grep -q "libfuse\.so\.2"
}

appimage_ensure_fuse() {
    appimage_has_fuse && return 0
    info "Installing libfuse2 (required for AppImage)..."
    sudo apt install -y libfuse2t64 > /dev/null 2>&1 || sudo apt install -y libfuse2 > /dev/null 2>&1 || true
    # Verify — an apt failure must not become a silently broken install
    if ! appimage_has_fuse; then
        failure "libfuse2 is still missing — AppImages cannot run without it."
        info "Try manually:  sudo apt install -y libfuse2t64  (or:  sudo apt install -y libfuse2)"
        info "Then retry the install — nothing was changed."
        return 1
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_print_launch_hint() — the honest “if it won't open” guidance
#
# Desktop entries launch with Terminal=false, so a crashing AppImage shows
# NOTHING — the single most confusing failure mode there is. The hint points
# at the one command that always reveals the cause, then explains the Electron
# sandbox failure (“SUID sandbox helper … chrome-sandbox … mode 4755” on
# Ubuntu 23.10+) and both ways out: the one-run --no-sandbox check and the
# permanent per-app profile via `uo --fix-appimage-sandbox`.
#
# Arguments: $1 — app name (the terminal command)
# ───────────────────────────────────────────────────────────────────────────────
appimage_print_launch_hint() {
    info "If it won't open from the desktop, run it once in a terminal — '$1' — and read the error line (GUI launches hide it)."
    local _sbx="A crash like 'SUID sandbox helper … chrome-sandbox … mode 4755' is the Electron sandbox vs Ubuntu 23.10+ — permanent fix: uo --fix-appimage-sandbox <AppImage-or-app-name> — quick check: $1 --no-sandbox"
    if [ -r "/proc/sys/kernel/apparmor_restrict_unprivileged_userns" ] \
        && [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2> /dev/null)" = "1" ]; then
        _sbx+=" (this kernel restricts unprivileged user namespaces — the usual cause)"
    fi
    info "$_sbx"
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_userns_profile_body() — the Ubuntu 23.10+ per-app AppArmor profile
#
# Why this exists: an AppImage mounts read-only via FUSE (nosuid), so an
# Electron app's SUID chrome-sandbox helper can NEVER work inside it, and
# Ubuntu 23.10+ additionally denies the unprivileged-user-namespace fallback
# through AppArmor. Result: the app aborts with exactly the user-visible
# “Rather than run without sandboxing I'm aborting now … mode 4755” error.
# The distribution-documented answer is a per-app profile granting `userns`
# to that one binary — real sandboxing stays ON, unlike --no-sandbox.
#
# appimage_abi_line() — the `abi` declaration for the generated profile
#
# The syntax here is load-bearing. `abi <abi/4.0>,` (include-style angle
# brackets) tells the parser to read the ABI definition shipped at
# /etc/apparmor.d/abi/4.0 by AppArmor 4.x (Ubuntu 24.04+). A bare `abi 4.0,`
# is NOT that: the parser treats "4.0" as a literal file name and fails with
# "Could not open '4.0': No such file or directory" — the exact bug v7.18.2
# shipped and v7.18.5's error surfacing exposed in the wild. Parsers without
# abi/4.0 (AppArmor 3.x) get NO abi line at all: the unprivileged-userns
# restriction only exists where AppArmor 4.x ships it anyway.
#
# Env:      APPARMOR_ABI_DIR — abi directory override (hermetic tests)
# Prints:   the abi line, or nothing when the parser predates abi/4.0
# ───────────────────────────────────────────────────────────────────────────────
appimage_abi_line() {
    local _dir=${APPARMOR_ABI_DIR:-/etc/apparmor.d/abi} _v
    for _v in 4.0 5.0; do
        if [ -f "$_dir/$_v" ]; then
            printf 'abi <abi/%s>,\n' "$_v"
            return 0
        fi
    done
}

# Arguments: $1 — profile name (uo-appimage-<app>)
#            $2 — the AppImage realpath
# Prints:    the profile body (stdout)
# ───────────────────────────────────────────────────────────────────────────────
appimage_userns_profile_body() {
    {
        appimage_abi_line
        cat <<EOF
include <tunables/global>

profile $1 "$2" flags=(unconfined) {
  userns,

  # Site-specific additions and overrides for this AppImage
  include if exists <local/$1>
}
EOF
    }
}

# appimage_write_userns_profile() — write the profile body to a file
# Arguments: $1 — destination file   $2 — profile name   $3 — AppImage path
appimage_write_userns_profile() {
    appimage_userns_profile_body "$2" "$3" > "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_find_desktop_entries() — desktop files that mention an app name
#
# A GUI-only AppImage (no terminal command anywhere) still has a launcher:
# its .desktop entry. Scanning the two canonical application directories for
# Exec targets or Name= lines containing the name (case-insensitive) finds
# the app the way the menu sees it — and is also the diagnosis for "my app
# appears twice in the menu" (two entries → two icons, one often stale).
#
# Arguments: $1 — app name (e.g. zcode)
# Prints:    matching .desktop file paths, one per line
# ───────────────────────────────────────────────────────────────────────────────
appimage_find_desktop_entries() {   # $1=name → stdout: matching .desktop paths
    local name=$1
    [ -n "$name" ] || return 1
    local dir f exec_path
    for dir in "$HOME/.local/share/applications" /usr/share/applications; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            exec_path=$(_desktop_exec_path "$f")
            if [[ "${exec_path,,}" == *"${name,,}"* ]] \
                || grep -qiF "name=$name" "$f" 2> /dev/null; then
                printf '%s\n' "$f"
            fi
        done
    done
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _appimage_inner_appimage() — chase a binary/wrapper to the AppImage it runs
#
# `command -v app` may find a symlink to the AppImage (realpath already
# resolves that) or a wrapper SCRIPT that execs it. Scans the script text for
# one path token ending in .AppImage and prints it if the file exists.
#
# Arguments: $1 — candidate binary/wrapper path
# Prints:    the AppImage path, or nothing
# ───────────────────────────────────────────────────────────────────────────────
_appimage_inner_appimage() {   # $1=wrapper/binary path → stdout: AppImage or empty
    local p=$1
    [ -n "$p" ] && [ -f "$p" ] && [ -r "$p" ] || return 0
    local inner
    inner=$(grep -aoE '[^[:space:]"]+\.AppImage' "$p" 2> /dev/null | head -n 1)
    if [ -n "$inner" ] && [ -f "$inner" ]; then
        printf '%s\n' "$inner"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_resolve_name() — turn what the user knows into a real AppImage
#
# The user knows a name ("zcode"), not a path. Search order mirrors how the
# app is actually launched: (1) a terminal command → its symlink target or
# wrapper script, (2) desktop-menu Exec= entries — the GUI-only case, (3) a
# case-insensitive filename match in the folders people drop AppImages in.
# Existing candidates only; duplicates removed; newest file wins first place
# (when several copies exist, the one updated last is the one in use).
#
# Arguments: $1 — app name or file path
# Prints:    candidate .AppImage paths (existing files), best first
# Returns:   0 — at least one candidate; 1 — nothing found
# ───────────────────────────────────────────────────────────────────────────────
appimage_resolve_name() {   # $1=name → stdout: candidate paths, best first
    local name=$1
    [ -n "$name" ] || return 1
    local -a cands=()
    local p dir f exec_path

    # 1) terminal command: the binary behind the name
    p=$(command -v "$name" 2> /dev/null) || p=""
    if [ -n "$p" ] && [ -e "$p" ]; then
        p=$(realpath -e "$p" 2> /dev/null) || p=""
        case $p in
            *.AppImage) cands+=("$p") ;;
            "") : ;;
            *)  p=$(_appimage_inner_appimage "$p")
                [ -n "$p" ] && cands+=("$p") ;;
        esac
    fi

    # 2) desktop menu entries — how GUI-only apps actually start
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        exec_path=$(_desktop_exec_path "$f")
        [ -n "$exec_path" ] || continue
        case $exec_path in
            *.AppImage) : ;;
            *)  if [ -e "$exec_path" ]; then
                    p=$(realpath -e "$exec_path" 2> /dev/null) || p=""
                    case $p in
                        *.AppImage) exec_path=$p ;;
                        *)  p=$(_appimage_inner_appimage "$p")
                            [ -n "$p" ] && exec_path=$p ;;
                    esac
                fi ;;
        esac
        [ -f "$exec_path" ] && cands+=("$(realpath -e "$exec_path" 2> /dev/null || printf '%s' "$exec_path")")
    done < <(appimage_find_desktop_entries "$name" 2> /dev/null)

    # 3) the folders people actually drop AppImages into (case-insensitive)
    for dir in "$HOME/Applications" "$HOME/.local/bin" "$HOME/bin" "$HOME/Downloads" /opt /usr/local/bin; do
        [ -d "$dir" ] || continue
        while IFS= read -r p; do
            if [ -n "$p" ] && [ -f "$p" ]; then
                cands+=("$(realpath -e "$p" 2> /dev/null || printf '%s' "$p")")
            fi
        done < <(find "$dir" -maxdepth 2 -iname "*${name}*.AppImage" 2> /dev/null)
    done

    # dedupe (string equality — glob-safe), keep only real files
    local -a uniq=()
    local c d dup
    for c in "${cands[@]}"; do
        if [ -z "$c" ] || [ ! -f "$c" ]; then continue; fi
        dup=0
        for d in "${uniq[@]}"; do
            if [ "$d" = "$c" ]; then dup=1; break; fi
        done
        if [ "$dup" = 0 ]; then uniq+=("$c"); fi
    done
    [ "${#uniq[@]}" -gt 0 ] || return 1
    if [ "${#uniq[@]}" -eq 1 ]; then
        printf '%s\n' "${uniq[0]}"
    else
        # newest first: the recently updated copy is the one being used
        local c2
        for c2 in "${uniq[@]}"; do stat -c '%Y %n' "$c2" 2> /dev/null; done \
            | sort -rn | cut -d' ' -f2-
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _appimage_report_entries() — explain an app's menu entries (duplicate icons)
#
# "The app shows up twice in my menu" = two .desktop entries name it, and one
# of them usually points at an AppImage that no longer exists. Prints where
# each entry's Exec points, flags stale targets with the exact removal advice.
#
# Arguments: $1 — app name or .AppImage path
# ───────────────────────────────────────────────────────────────────────────────
_appimage_report_entries() {   # $1=name or path → info/warn lines
    local name=$1
    if [[ "$name" == */* ]]; then name=$(basename "$name"); fi
    name=${name%.AppImage}
    [ -n "$name" ] || return 0
    local -a entries=()
    mapfile -t entries < <(appimage_find_desktop_entries "$name" 2> /dev/null)
    [ "${#entries[@]}" -gt 0 ] || return 0
    local f tgt stale=0
    for f in "${entries[@]}"; do
        tgt=$(_desktop_exec_path "$f")
        if [ -n "$tgt" ] && [ -e "$tgt" ]; then
            info "Menu entry: $f → $tgt"
        else
            stale=$((stale + 1))
            warn "Stale menu entry: $f → ${tgt:-<no Exec>} — its target is gone; remove this .desktop file to drop the icon"
        fi
    done
    if [ "${#entries[@]}" -gt 1 ]; then
        warn "${#entries[@]} menu entries mention '$name' — that is why it can appear twice in the menu; keep the one whose target you actually use."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# appimage_fix_sandbox() — the permanent fix for Electron AppImage aborts
#
# Writes /etc/apparmor.d/uo-appimage-<app> (a per-app userns profile for the
# exact AppImage path) and loads it with `apparmor_parser -r` (kernel load —
# the documented command; the profile must be ACTIVE, not merely parsed).
# Pre-flights AppArmor availability (userspace tools + kernel interface) and
# HONESTLY reports captured stderr on any failure. Honors DRY_RUN
# (prints the profile + the commands it would run, changes nothing) and
# asks before touching anything. The profile is path-bound: moving the file
# means re-running this command; the undo line is always printed.
#
# Input: $1 — a .AppImage path, OR just the app's name (v7.18.4): resolved
#            through PATH commands, wrapper scripts, desktop-menu Exec=
#            entries and common AppImage folders — `uo --fix-appimage-sandbox
#            zcode` finds the app even when it has no terminal command and
#            only a menu icon. When invoked from the CLI dispatcher, $1 is
#            empty and the value rides on the APPIMAGE_SANDBOX_FILE global
#            (the dispatcher calls arg-less).
# Returns:   0 — profile installed (or shown in dry-run)
#            1 — invalid input, cancellation, or the install failed
# ───────────────────────────────────────────────────────────────────────────────
appimage_fix_sandbox() {
    local APPIMAGE_PATH=${1:-${APPIMAGE_SANDBOX_FILE:-}}
    APPIMAGE_PATH=${APPIMAGE_PATH/#\~/$HOME}
    local _input=$APPIMAGE_PATH   # what the user actually typed (for reports)
    if [ -z "$APPIMAGE_PATH" ]; then
        failure "Usage: uo --fix-appimage-sandbox <path/to/app.AppImage>"
        return 1
    fi
    # A bare name (no slash) that is not a file — resolve it the way the user
    # actually launches the app: PATH → wrapper script → menu entries → folders.
    if [ ! -f "$APPIMAGE_PATH" ] && [[ "$APPIMAGE_PATH" != */* ]]; then
        local -a _cands=()
        mapfile -t _cands < <(appimage_resolve_name "$APPIMAGE_PATH" 2> /dev/null)
        if [ "${#_cands[@]}" -gt 0 ]; then
            APPIMAGE_PATH=${_cands[0]}
            if [ "${#_cands[@]}" -gt 1 ]; then
                warn "Several AppImages match '$_input' — using the newest:"
                local _c
                for _c in "${_cands[@]}"; do info "  · $_c"; done
                info "To target another one, pass its exact path."
            fi
        fi
    fi
    if [ ! -f "$APPIMAGE_PATH" ]; then
        # diagnose BEFORE giving up: menu entries often explain everything
        _appimage_report_entries "$_input"
        failure "File not found: $APPIMAGE_PATH"
        info "Searched: terminal commands, desktop menu entries (Exec=) and common AppImage folders."
        info "Locate the real .AppImage and pass its path:  uo --fix-appimage-sandbox /path/to/App.AppImage"
        return 1
    fi
    APPIMAGE_PATH=$(realpath -e "$APPIMAGE_PATH" 2> /dev/null) || {
        failure "File not found: $APPIMAGE_PATH"
        return 1
    }
    [[ "$APPIMAGE_PATH" =~ \.AppImage$ ]] || { failure "Not an AppImage: $APPIMAGE_PATH"; return 1; }
    [ -f "$APPIMAGE_PATH" ] || { failure "File not found: $APPIMAGE_PATH"; return 1; }
    # while we are here: duplicate/stale menu icons for this app (v7.18.4).
    # Key on the name the user typed ("zcode"), not the resolved, possibly
    # versioned filename ("zcode-2.0") — siblings must be caught too.
    if [[ "$_input" != */* ]]; then
        _appimage_report_entries "$_input"
    else
        _appimage_report_entries "$APPIMAGE_PATH"
    fi

    local APP_NAME PROFILE_NAME DEST TMP
    APP_NAME=$(basename "$APPIMAGE_PATH")
    APP_NAME=${APP_NAME%.AppImage}
    PROFILE_NAME="uo-appimage-$(sanitize_app_name "$APP_NAME")"
    DEST="/etc/apparmor.d/$PROFILE_NAME"

    header "AppImage Sandbox Fix (per-app userns profile)"
    info "App:      $APPIMAGE_PATH"
    info "Profile:  $DEST — grants user-namespace sandboxing to this app only (sandboxing stays ON)"

    if [ "$DRY_RUN" = "1" ]; then
        warn "DRY RUN — the profile would be written as:"
        appimage_userns_profile_body "$PROFILE_NAME" "$APPIMAGE_PATH" | sed 's/^/   /'
        info "[dry-run] sudo install -m 0644 <profile> $DEST"
        info "[dry-run] sudo apparmor_parser -r $DEST"
        success "[dry-run] AppImage sandbox fix would be applied."
        return 0
    fi

    # Pre-flight: AppArmor must exist in BOTH userspace and kernel, or this
    # fix can never work — say so honestly BEFORE asking for confirmation
    # (WSL2, containers and some VMs ship without the kernel interface).
    local _sysfs=${APPARMOR_SYSFS:-/sys/kernel/security/apparmor}
    if ! command -v apparmor_parser > /dev/null 2>&1; then
        failure "AppArmor userspace tools are not installed — the userns profile cannot be written or loaded."
        info "Install them:  sudo apt install apparmor"
        info "Fallback for this run:  $APPIMAGE_PATH --no-sandbox"
        return 1
    fi
    if [ ! -d "$_sysfs" ]; then
        failure "AppArmor is not enabled in this kernel ($_sysfs is missing)."
        info "Common in WSL2, containers and some VMs — the userns profile cannot be enforced here."
        info "Fallback for this run:  $APPIMAGE_PATH --no-sandbox"
        return 1
    fi

    confirm_action "Write the AppArmor profile and reload it?" || { warn "Cancelled — nothing was changed."; return 1; }

    # Every privileged step's stderr is captured and SHOWN on failure — a
    # silent `2>/dev/null` once turned a parser error into a dead end.
    # `apparmor_parser -r` (replace + load into the kernel) is the documented
    # command: the profile must be ACTIVE, not merely parsed and cached.
    TMP=$(mktemp)
    appimage_write_userns_profile "$TMP" "$PROFILE_NAME" "$APPIMAGE_PATH"
    local _out="" _installed=0 _rc=1 _l
    _out=$(sudo install -m 0644 "$TMP" "$DEST" 2>&1); _rc=$?
    if [ "$_rc" -eq 0 ]; then
        _installed=1
        _out=$(sudo apparmor_parser -r "$DEST" 2>&1); _rc=$?
    fi
    if [ "$_rc" -eq 0 ]; then
        rm -f "$TMP"
        success "Sandbox profile installed for '$APP_NAME' — launch the app normally (no --no-sandbox needed)."
        info "The profile is bound to this exact path — if the AppImage moves, re-run this command."
        info "Undo:  sudo apparmor_parser -R $DEST; sudo rm $DEST"
        return 0
    fi
    rm -f "$TMP"
    failure "Could not install the AppArmor profile."
    if [ -n "$_out" ]; then
        while IFS= read -r _l; do info "  └ $_l"; done <<< "$_out"
    fi
    if [ "$_installed" = 1 ]; then
        warn "The profile file WAS written to $DEST but could not be loaded — remove it if you don't need it:  sudo rm $DEST"
    fi
    info "Quick fallback (per run):  $APPIMAGE_PATH --no-sandbox"
    info "Manual: write $DEST by hand (see the docs), then: sudo apparmor_parser -r $DEST"
    return 1
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
