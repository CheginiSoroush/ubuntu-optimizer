# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/doctor.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Health check and repair for apps tracked by the script (tar.gz
#  registry + GitHub deb database): verifies files, permissions, PATH
#  symlinks, desktop entries, library dependencies and binary format,
#  and auto-repairs what it can. Called by --doctor and the System menu's
#  health-check entry.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# Result counters (reset by doctor_apps)
DOCTOR_TOTAL=0
DOCTOR_OK=0
DOCTOR_FIXED=0
DOCTOR_FAILED=0

# GUI library patterns — a binary linking against none of these is
# treated as a TUI/CLI tool and gets a terminal wrapper in its desktop entry
readonly DOCTOR_GUI_LIBS='libX11|libXext|libgtk|libQt|libQt5|libQt6|libGL|libwayland|libxcb|libEGL'

# ───────────────────────────────────────────────────────────────────────────────
# doctor_result() — Record and print one check outcome
#
# Bumps the matching DOCTOR_* counter and reports through success/failure
# so every outcome is visible and logged; the optional detail is appended
# after an em dash.
#
# Globals:   DOCTOR_TOTAL, DOCTOR_OK, DOCTOR_FIXED, DOCTOR_FAILED (write)
# Arguments: $1 — outcome: ok | fixed | broken
#            $2 — app name
#            $3 — optional detail text
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
doctor_result() {
    DOCTOR_TOTAL=$((DOCTOR_TOTAL + 1))
    case "$1" in
        ok)
            DOCTOR_OK=$((DOCTOR_OK + 1))
            success "$2: healthy${3:+ — $3}"
            ;;
        fixed)
            DOCTOR_FIXED=$((DOCTOR_FIXED + 1))
            success "$2: repaired${3:+ — $3}"
            ;;
        broken)
            DOCTOR_FAILED=$((DOCTOR_FAILED + 1))
            failure "$2: $3"
            ;;
    esac
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# doctor_terminal_cmd() — Detect a terminal wrapper command for TUI apps
#
# Desktop entries for TUI/CLI tools need an explicit terminal emulator.
# ptyxis is probed first because it is the new GNOME terminal (Ubuntu
# 25.10+); prints an empty string when no terminal is installed.
#
# Arguments: none
# Returns:   0 — always; the wrapper prefix (or empty) on stdout
# ───────────────────────────────────────────────────────────────────────────────
doctor_terminal_cmd() {
    if command -v ptyxis > /dev/null 2>&1; then
        printf 'ptyxis --'
    elif command -v gnome-terminal > /dev/null 2>&1; then
        printf 'gnome-terminal --'
    elif command -v konsole > /dev/null 2>&1; then
        printf 'konsole -e'
    elif command -v xterm > /dev/null 2>&1; then
        printf 'xterm -e'
    else
        printf ''
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# doctor_terminal_flag() — Decide whether a binary needs a terminal
#
# A dynamic binary without GUI libraries, or a static non-script binary
# (Go/Rust CLI), is treated as a TUI/CLI tool → true; everything else is
# GUI-safe → false. Electron-style launcher scripts are resolved to their
# .bin sibling before the ldd check.
#
# Globals:   DOCTOR_GUI_LIBS (read)
# Arguments: $1 — executable path
# Returns:   0 — always; prints true or false
# ───────────────────────────────────────────────────────────────────────────────
doctor_terminal_flag() {   # $1=executable path → output: true|false
    local check_bin="$1" ldd_out sibling
    # A launcher script → the real binary is the .bin sibling (Electron pattern)
    if head -c 2 "$check_bin" 2>/dev/null | grep -q '#!'; then
        sibling=$(find "$(dirname "$check_bin")" -maxdepth 1 -type f \
                  -name "$(basename "$check_bin").bin" 2>/dev/null | head -1)
        [ -n "$sibling" ] && check_bin="$sibling"
    fi
    ldd_out=$(ldd "$check_bin" 2>&1 || true)
    if printf '%s' "$ldd_out" | grep -q "not a dynamic executable"; then
        # Static binary — not a script → almost certainly a CLI/TUI tool
        if ! head -c 2 "$check_bin" 2>/dev/null | grep -q '#!'; then
            printf 'true'
        else
            printf 'false'
        fi
    elif ! printf '%s' "$ldd_out" | grep -qE "$DOCTOR_GUI_LIBS"; then
        # Dynamic binary without GUI libraries → TUI/CLI
        printf 'true'
    else
        printf 'false'
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# doctor_regen_desktop() — Regenerate a tar.gz app's desktop entry
#
# Writes the entry with sudo tee, picking the largest icon file under the
# install directory (fallback: applications-other). TUI/CLI tools get an
# explicit terminal wrapper (ptyxis/gnome-terminal/...) instead of
# Terminal=true because the DE handler for Terminal=true is unreliable on
# GNOME/Wayland; Terminal=true stays as the fallback when no terminal
# emulator is installed. Refreshes the desktop database when available.
#
# Arguments: $1 — app name
#            $2 — install directory (searched for icons)
#            $3 — executable path
#            $4 — desktop file path to (re)write
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
doctor_regen_desktop() {   # $1=name  $2=install_dir  $3=exec  $4=desktop_file
    local name="$1" dir="$2" exec_path="$3" desktop="$4" icon terminal_flag exec_line term_wrapper

    icon=$(find "$dir" -type f \( -iname "*.png" -o -iname "*.svg" \) \
           -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    icon=${icon:-applications-other}

    terminal_flag=$(doctor_terminal_flag "$exec_path")
    exec_line="$(desktop_escape_path "$exec_path")"

    # TUI/CLI app → wrap in a terminal emulator for reliable menu launch
    if [ "$terminal_flag" = "true" ]; then
        term_wrapper=$(doctor_terminal_cmd)
        if [ -n "$term_wrapper" ]; then
            exec_line="$term_wrapper $(desktop_escape_path "$exec_path")"
            terminal_flag="false"
        fi
        # No terminal found → keep Terminal=true as the fallback
    fi

    printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        "Name=$name" \
        'Comment=Installed by Ubuntu Optimizer' \
        "Exec=$exec_line" \
        "Path=$dir" \
        "Icon=$icon" \
        "Terminal=$terminal_flag" \
        'Categories=Utility;' | sudo tee "$desktop" > /dev/null

    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1
    return 0
}

# ── tar.gz (registry) app: full check + repair ──────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# doctor_check_targz() — Full check and repair for one registry app
#
# Seven ordered checks: install directory, executable (re-detected with
# pick_executable when the registered path is gone), binary format (Mach-O
# cannot run on Linux), execute permission, /usr/local/bin symlink,
# shared-library dependencies (fix_binary_deps) and the desktop entry
# (regenerated when missing, broken or lacking the terminal wrapper). The
# first unfixable problem is reported and ends the checks for that app;
# everything repaired is summarized in one "fixed" result.
#
# Globals:   SELECTED_EXEC (read — set by pick_executable)
# Arguments: $1 — app name        $4 — registered executable path
#            $2 — version         $5 — desktop file path
#            $3 — install dir     $6 — source archive
# Returns:   0 — always (the outcome is recorded via doctor_result)
# ───────────────────────────────────────────────────────────────────────────────
doctor_check_targz() {   # $1=name $2=ver $3=dir $4=exec $5=desktop $6=source
    local name="$1" ver="$2" dir="$3" exec_path="$4" desktop="$5" source="$6"
    local repairs="" need_regen=0 desktop_exec="" term_wrapper=""

    # 1) Install directory
    if [ ! -d "$dir" ]; then
        doctor_result "broken" "$name" "install directory missing ($dir) — reinstall the app"
        return 0
    fi

    # 2) Executable exists — re-detect if the registered path is gone
    if [ ! -f "$exec_path" ]; then
        info "  $name: registered executable missing — re-detecting..."
        if pick_executable "$dir" "$name"; then
            exec_path="$SELECTED_EXEC"
            registry_add "$name" "$ver" "$dir" "$exec_path" "$desktop" "$source"
            repairs="executable re-detected"
        else
            doctor_result "broken" "$name" "no executable found in $dir — reinstall the app"
            return 0
        fi
    fi

    # 3) Binary format check — Mach-O (macOS) binaries cannot run on Linux
    if command -v file > /dev/null 2>&1; then
        if file -b "$exec_path" 2>/dev/null | grep -q 'Mach-O'; then
            doctor_result "broken" "$name" "binary is macOS format (Mach-O) — reinstall from GitHub: uo --github-install"
            return 0
        fi
    fi

    # 4) Execute permission
    if [ ! -x "$exec_path" ]; then
        sudo chmod +x "$exec_path"
        repairs="${repairs:+$repairs, }exec permission"
    fi

    # 5) Command symlink in /usr/local/bin
    if [ ! -e "/usr/local/bin/$name" ]; then
        sudo ln -sf "$exec_path" "/usr/local/bin/$name"
        repairs="${repairs:+$repairs, }command symlink"
    fi

    # 6) Shared-library dependencies
    if ldd "$exec_path" 2>/dev/null | grep -q "not found"; then
        info "  $name: missing shared libraries — attempting repair..."
        if ! fix_binary_deps "$exec_path"; then
            doctor_result "broken" "$name" "missing libraries could not be installed (details above)"
            return 0
        fi
        repairs="${repairs:+$repairs, }dependencies"
    fi

    # 7) Desktop entry — missing, broken Exec, or TUI without terminal wrapper
    if [ ! -f "$desktop" ]; then
        need_regen=1
    else
        desktop_exec=$(_desktop_exec_path "$desktop" 2>/dev/null)
        if [ -n "$desktop_exec" ] && [[ "$desktop_exec" == /* ]] && [ ! -e "$desktop_exec" ]; then
            need_regen=1
        elif [ "$(doctor_terminal_flag "$exec_path")" = "true" ]; then
            # TUI app — needs the terminal wrapper in Exec.
            # An empty wrapper (no terminal emulator installed) keeps the
            # Terminal=true fallback — grep with an empty pattern would
            # otherwise match anything and silently skip the check.
            term_wrapper=$(doctor_terminal_cmd)
            if [ -n "$term_wrapper" ] && ! grep -qF -- "$term_wrapper" "$desktop" 2>/dev/null; then
                need_regen=1
            fi
        fi
    fi
    if [ "$need_regen" = "1" ]; then
        info "  $name: desktop entry needs repair — regenerating..."
        doctor_regen_desktop "$name" "$dir" "$exec_path" "$desktop"
        repairs="${repairs:+$repairs, }desktop entry"
    fi

    # Result
    if [ -n "$repairs" ]; then
        doctor_result "fixed" "$name" "$repairs"
    else
        doctor_result "ok" "$name"
    fi
    return 0
}

# ── deb app: check (stale cleanup + broadened search) ───────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# doctor_check_deb() — Check a GitHub-tracked deb app
#
# Removes the tracking entry automatically when the package is no longer
# installed. Otherwise verifies that an executable is reachable — as a
# command, or as any executable file the package ships outside data
# directories (covers /opt, /usr/local, ...) — and that shipped desktop
# entries point to existing targets. A working desktop entry counts as
# healthy even without a standard binary.
#
# Arguments: $1 — app (package) name
# Returns:   0 — always (the outcome is recorded via doctor_result)
# ───────────────────────────────────────────────────────────────────────────────
doctor_check_deb() {   # $1=app name
    local name="$1" df desktop_exec broken_entry="" found_bin=0 desktop_ok=0

    # 1) Package installed? — a stale tracking entry is removed automatically
    if ! pkg_installed "$name"; then
        info "  $name: package not installed — removing the stale tracking entry..."
        gh_db_remove "$name"
        doctor_result "fixed" "$name" "stale tracking entry removed (package not installed)"
        return 0
    fi

    # 2) Executable reachable — command name, or any executable file in the
    #    package outside data directories (covers /opt, /usr/local, etc.)
    if command -v "$name" > /dev/null 2>&1; then
        found_bin=1
    else
        while IFS= read -r bin; do
            [ -f "$bin" ] && [ -x "$bin" ] && { found_bin=1; break; }
        done < <(dpkg -L "$name" 2>/dev/null | grep -vE '^/(usr/share|usr/lib|usr/libexec|etc|var)/')
    fi

    # 3) Desktop entries shipped by the package — a valid Exec target
    #    counts as healthy even without a standard binary
    while IFS= read -r df; do
        [ -z "$df" ] && continue
        desktop_exec=$(_desktop_exec_path "$df" 2>/dev/null)
        if [ -n "$desktop_exec" ]; then
            if [[ "$desktop_exec" == /* ]]; then
                if [ -e "$desktop_exec" ]; then
                    desktop_ok=1
                else
                    broken_entry="$df"
                    break
                fi
            else
                if command -v "$desktop_exec" > /dev/null 2>&1; then
                    desktop_ok=1
                else
                    broken_entry="$df"
                    break
                fi
            fi
        fi
    done < <(dpkg -L "$name" 2>/dev/null | grep '\.desktop$')
    if [ -n "$broken_entry" ]; then
        doctor_result "broken" "$name" "desktop entry points to a missing file — reinstall the package"
        return 0
    fi

    # 4) Result: healthy if a binary was found OR a desktop entry works
    if [ "$found_bin" = "1" ] || [ "$desktop_ok" = "1" ]; then
        doctor_result "ok" "$name"
    else
        doctor_result "broken" "$name" "no working executable or desktop entry found — reinstall the package"
    fi
    return 0
}

# ── main entry point ────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# doctor_apps() — Check and repair every tracked app
#
# Entry point behind --doctor and the menu entry. Counts the tracked apps,
# authenticates sudo up front (the repairs need chmod/ln/tee), resets the
# DOCTOR_* counters, then runs the full tar.gz checks followed by the deb
# checks — skipping GitHub names already present in the registry — and
# prints the healthy/repaired/unfixable summary.
#
# Globals:   DOCTOR_TOTAL, DOCTOR_OK, DOCTOR_FIXED, DOCTOR_FAILED (write);
#            REGISTRY_DB, GITHUB_DB (read)
# Arguments: none
# Returns:   0 — scan finished (per-app failures are counted, not propagated)
#            1 — sudo authentication failed
# ───────────────────────────────────────────────────────────────────────────────
doctor_apps() {
    header "🩺 App Health Check & Repair"
    echo "   Checks every app installed/tracked by this script:"
    echo "   • tar.gz apps: files, binary format, permissions, symlink,"
    echo "     desktop entry (with terminal wrapper), dependencies"
    echo "   • GitHub deb apps: package, binary, desktop entries"
    echo ""

    # Count how many apps there are to check
    local expected=0
    [ -s "$REGISTRY_DB" ] && expected=$((expected + $(wc -l < "$REGISTRY_DB")))
    [ -s "$GITHUB_DB" ] && expected=$((expected + $(wc -l < "$GITHUB_DB")))
    if [ "$expected" -eq 0 ]; then
        info "No tracked apps found — nothing to check."
        return 0
    fi

    # The repairs need sudo (chmod, ln, tee) — authenticate up front
    sudo_precheck || return 1

    DOCTOR_TOTAL=0
    DOCTOR_OK=0
    DOCTOR_FIXED=0
    DOCTOR_FAILED=0

    # ── 1) tar.gz registry apps (full check + repair) ──
    if [ -s "$REGISTRY_DB" ]; then
        local -a reg_lines=()
        mapfile -t reg_lines < "$REGISTRY_DB"
        local line name ver dir exec_path desktop source
        for line in "${reg_lines[@]}"; do
            IFS='|' read -r name ver dir exec_path desktop source <<< "$line"
            [ -z "$name" ] && continue
            echo ""
            info "Checking: $name (tar.gz)"
            doctor_check_targz "$name" "$ver" "$dir" "$exec_path" "$desktop" "$source"
        done
    fi

    # ── 2) GitHub-tracked deb apps (skip registry duplicates) ──
    if [ -s "$GITHUB_DB" ]; then
        local -a gh_lines=()
        mapfile -t gh_lines < "$GITHUB_DB"
        local line name repo tag in_registry=0
        for line in "${gh_lines[@]}"; do
            IFS='|' read -r name repo tag <<< "$line"
            [ -z "$name" ] && continue
            # tar.gz apps were already checked above
            in_registry=0
            if [ -f "$REGISTRY_DB" ]; then
                awk -F'|' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$REGISTRY_DB" 2>/dev/null && in_registry=1
            fi
            [ "$in_registry" = "1" ] && continue
            echo ""
            info "Checking: $name (deb)"
            doctor_check_deb "$name"
        done
    fi

    # ── summary ──
    echo ""
    echo -e "${BOLD}── Doctor Summary ──${NC}"
    echo "   Total checked: $DOCTOR_TOTAL"
    echo -e "   ${GREEN}✓ Healthy:     $DOCTOR_OK${NC}"
    echo -e "   ${GREEN}🔧 Repaired:   $DOCTOR_FIXED${NC}"
    echo -e "   ${RED}✗ Unfixable:   $DOCTOR_FAILED${NC}"
    if [ "$DOCTOR_FAILED" -gt 0 ]; then
        warn "Some apps could not be repaired — see the reasons above."
    fi
    log_write "INFO" "doctor: total=$DOCTOR_TOTAL ok=$DOCTOR_OK fixed=$DOCTOR_FIXED broken=$DOCTOR_FAILED"
    return 0
}
