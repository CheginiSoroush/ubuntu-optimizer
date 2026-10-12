# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/menus.sh
# ───────────────────────────────────────────────────────────────────────────────
#  The interactive UI layer: the generic menu_loop engine, the twelve submenus
#  it drives and the boxed main menu. Loaded by ubuntu-optimizer.sh when no CLI
#  flags are given; every entry dispatches to a function in the other lib/* modules.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# menu_loop() — render and drive an interactive selection menu
#
# Generic engine behind every submenu. Items are "title|function_name"
# strings; optional leading -w "warning" pairs are printed above the list.
# Loops until the user chooses 0 (Back) or sends EOF (Ctrl+D — clean exit);
# dispatches to the function stored after the "|" and pauses with
# press_enter afterwards. Invalid input is reported as a warning, never
# logged as an error.
#
# Arguments: $1 — menu title
#            -w "warning"... — optional warning lines shown above the items
#            "title|function"... — the numbered menu items
# Returns:   0 — on Back (exits 0 on EOF/Ctrl+D)
# ───────────────────────────────────────────────────────────────────────────────
menu_loop() {
    local title="$1"; shift
    local warnings=()
    while [ "$1" = "-w" ]; do
        warnings+=("$2")
        shift 2
    done
    local items=("$@")
    local choice i item w func

    while true; do
        clear
        header "$title"
        for w in "${warnings[@]}"; do warn "$w"; done
        [ ${#warnings[@]} -gt 0 ] && echo ""
        i=1
        for item in "${items[@]}"; do
            echo "   $i) ${item%%|*}"
            i=$((i + 1))
        done
        echo "   0) Back"
        echo ""
        # EOF (Ctrl+D) → clean exit; without this the loop would spin forever
        read -r -p "   Select: " choice || exit 0
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
            func="${items[$((choice-1))]#*|}"
            if declare -F "$func" > /dev/null; then
                "$func"
            else
                failure "Function '$func' not found — check the menu definition"
            fi
            press_enter
        elif [ "$choice" = "0" ]; then
            break
        else
            # Invalid user input is not a system error — logged as WARN, not ERROR
            warn "Invalid choice"
            sleep 1
        fi
    done
}

# ── Submenus ──────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# menu_network() — submenu 1: Network Optimization
#
# Thin wrapper: renders the submenu via menu_loop; every entry dispatches
# to its optimizer in lib/network.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_network() {
    menu_loop "🌐 Network Optimization" \
        "Disable Wi-Fi power management|disable_wifi_powersave" \
        "Set DNS to 8.8.8.8 & 1.1.1.1|set_dns" \
        "Enable BBR congestion control|enable_bbr" \
        "Set MTU (default 1492)|set_mtu" \
        "Optimize TCP parameters|optimize_tcp" \
        "Run all of the above|all_network_opts"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_system() — submenu 2: System & Memory Optimization
#
# Thin wrapper: renders the submenu via menu_loop; every entry dispatches
# to its optimizer in lib/system.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_system() {
    menu_loop "💾 System & Memory Optimization" \
        "Reduce swappiness & vfs_cache_pressure|optimize_memory" \
        "Add noatime to /etc/fstab|set_noatime" \
        "Disable extra services|disable_extra_services" \
        "Install preload|install_preload" \
        "Install tlp (battery management)|install_tlp" \
        "Limit journal log size|limit_journal" \
        "Run all of the above|all_system_opts"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_security() — submenu 3: Security & Passwords
#
# Thin wrapper: the sudo timeout and polkit entries dispatch to
# lib/system.sh, the two GitHub SSH entries to lib/gitssh.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_security() {
    menu_loop "🔐 Security & Passwords" \
        "Extend sudo password timeout|extend_sudo_timeout" \
        "Create polkit rule|setup_polkit_rule" \
        "Run both|all_security_opts" \
        "Set up GitHub SSH key (passwordless)|gitssh_setup" \
        "GitHub SSH status|gitssh_status"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_time() — submenu 4: Time & NTP
#
# Thin wrapper: renders the submenu via menu_loop; both entries dispatch
# to lib/system.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_time() {
    menu_loop "🕐 Time & NTP" \
        "Fix time sync with chrony|fix_time" \
        "Show time status|show_time_status"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_fixnet() — submenu 5: fixnet Script
#
# Thin wrapper: creating (embedding) and running the standalone fixnet
# repair script; both entries dispatch to lib/fixnet.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_fixnet() {
    menu_loop "🛠 fixnet Script" \
        "Create the fixnet script (bilingual)|create_fixnet_script" \
        "Run fixnet|run_fixnet"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_testing() — submenu 6: Network Tests
#
# Thin wrapper: renders the submenu via menu_loop; every entry dispatches
# to its test in lib/network.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_testing() {
    menu_loop "📊 Network Tests" \
        "Ping test to 8.8.8.8|test_ping" \
        "DNS test (ping google.com)|test_ping_dns" \
        "Internet speed test|test_speed" \
        "Show full network info|show_network_info" \
        "Run all tests|all_tests"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_packages() — submenu 7: Install Packages & Apps
#
# Thin wrapper: apt tools and the .deb/node installs dispatch to
# lib/packages.sh, tar.gz and AppImage installs to lib/targz.sh and the
# GitHub release install to lib/github.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_packages() {
    menu_loop "📦 Install Packages & Apps" \
        "Install essential tools (curl, wget, git, ...)|install_essential_tools" \
        "Install archive tools (unrar, p7zip, file-roller)|install_unrar" \
        "Install a .deb file|install_deb" \
        "Install app from .tar.gz (smart + registry)|install_targz" \
        "Install app from GitHub (latest release)|github_install_repo" \
        "Install nodejs and npm|install_nodejs" \
        "Install AppClean|install_appclean" \
        "Install from AppImage file|install_appimage"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_appmgmt() — submenu 8: Manage & Fully Remove Apps
#
# Thin wrapper: listing and cleanup entries dispatch to lib/appmgmt.sh,
# the health check to lib/doctor.sh and the tracked GitHub app entries to
# lib/github.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_appmgmt() {
    menu_loop "🧹 Manage & Fully Remove Apps" \
        "List all installed apps (all sources)|list_all_apps" \
        "🩺 Health check & repair all installed apps|doctor_apps" \
        "Fully remove an app from any source (with data)|cleanup_app" \
        "List tracked GitHub apps|github_list_apps" \
        "Remove a tracked GitHub app|github_remove_app" \
        "Clean leftover deb package configs|cleanup_deb_residuals" \
        "Remove orphan desktop files|cleanup_desktop_orphans"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_snapflat() — submenu 10: snap & flatpak Management
#
# Thin wrapper: renders the submenu via menu_loop; every entry dispatches
# to its handler in lib/snapflatpak.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_snapflat() {
    menu_loop "🧩 snap & flatpak Management" \
        "List snap apps|snap_list_apps" \
        "Install a snap|snap_install_app" \
        "Remove a snap|snap_remove_app" \
        "Clean old snap revisions (reclaim disk space)|snap_clean_revisions" \
        "List flatpak apps|flatpak_list_apps" \
        "Install a flatpak|flatpak_install_app" \
        "Remove a flatpak|flatpak_remove_app" \
        "Clean unused flatpak runtimes|flatpak_clean_unused"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_updates() — submenu 9: Update Apps
#
# Thin wrapper: update_all and the per-backend updates dispatch to
# lib/snapflatpak.sh; the tracked GitHub app update check to lib/github.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_updates() {
    menu_loop "🔄 Update Apps" \
        "Update everything (apt + snap + flatpak + tar.gz + github)|update_all" \
        "Update apt (system & deb packages)|update_apt" \
        "Update snap|update_snap" \
        "Update flatpak|update_flatpak" \
        "Check tar.gz app updates|update_targz_apps" \
        "Check GitHub app updates|github_update_apps"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_profiles() — submenu 5: Optimization Profiles
#
# Curated presets (lib/profile.sh): each runs a safe, scenario-specific
# subset of the optimizer steps after showing its plan.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_profiles() {
    menu_loop "⚡ Optimization Profiles" \
        "Laptop — battery & responsiveness|profile_run_laptop" \
        "Server — throughput, no desktop extras|profile_run_server" \
        "Gaming — lowest latency only|profile_run_gaming" \
        "Minimal — the conservative core|profile_run_minimal"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_recovery() — submenu 12: System Recovery & Rescue
#
# Thin wrapper: renders the submenu via menu_loop; every entry dispatches
# to its repair function in lib/recovery.sh.
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_recovery() {
    menu_loop "🚑 System Recovery & Rescue" \
        "Fix broken packages (apt --fix-broken)|fix_broken" \
        "Reinstall the desktop environment|reinstall_desktop" \
        "Configure pending packages with dpkg|fix_dpkg_configure" \
        "Undo all optimizations (restore defaults)|undo_all_optimizations"
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_dangerous() — submenu 12: Advanced Tools (Dangerous)
#
# Thin wrapper for high-risk tools; the -w warnings are rendered above the
# list by menu_loop. Currently offers only VEET (lib/recovery.sh).
#
# Arguments: none
# Returns:   0 — on Back/EOF
# ───────────────────────────────────────────────────────────────────────────────
menu_dangerous() {
    menu_loop "☠ Advanced Tools (Dangerous)" \
        -w "This section contains powerful tools that, if used incorrectly," \
        -w "can cause serious damage to your system!" \
        "Install VEET (deep removal tool — warned)|install_veet"
}

# ── Main menu ──────────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# main_menu() — render the boxed main menu and dispatch the selection
#
# Interactive entry point used when no CLI flags are given. Draws the banner
# box — the border width (54) matches the printf %-54s lines, so the
# alignment can never drift — lists the 17 numbered entries plus Exit, and
# loops until Exit or EOF. Entries 1–12 open the submenus above; 13–17 call
# show_log, system_report, disk_analyze, disk_cleanup and the profile menu.
#
# Globals:   SCRIPT_VERSION (read), colour codes from lib/common.sh
# Arguments: none
# Returns:   0 — on Exit (exits 0 on EOF/Ctrl+D)
# ───────────────────────────────────────────────────────────────────────────────
main_menu() {
    local choice border
    border=$(printf '═%.0s' {1..54})
    while true; do
        clear
        echo -e "${MAGENTA}"
        printf '    ╔%s╗\n' "$border"
        printf '    ║%-54s║\n' ""
        printf '    ║%-54s║\n' "       Ubuntu Optimizer & Fixer - v${SCRIPT_VERSION}"
        printf '    ║%-54s║\n' "       All-in-one Ubuntu optimization & repair toolkit"
        printf '    ║%-54s║\n' ""
        printf '    ║%-54s║\n' "       Author & Designer: CheginiSoroush"
        printf '    ║%-54s║\n' "       github.com/CheginiSoroush/ubuntu-optimizer"
        printf '    ╚%s╝\n' "$border"
        echo -e "${NC}"
        echo -e "${BOLD}   ── Optimization & Health ──${NC}"
        echo "   1) 🌐 Network optimization"
        echo "   2) 💾 System & memory optimization"
        echo "   3) 🔐 Security & passwords"
        echo "   4) 🕐 Time & NTP"
        echo "   5) ⚡ Optimization profiles (laptop/server/gaming/minimal)"
        echo ""
        echo -e "${BOLD}   ── Emergency & Diagnostics ──${NC}"
        echo "   6) 🛠 Create & run fixnet"
        echo "   7) 📊 Network & speed tests"
        echo ""
        echo -e "${BOLD}   ── Applications ──${NC}"
        echo "   8) 📦 Install packages & apps"
        echo "   9) 🧹 Manage & fully remove apps"
        echo "  10) 🔄 Update apps"
        echo "  11) 🧩 snap & flatpak management"
        echo ""
        echo -e "${BOLD}   ── System & Info ──${NC}"
        echo "  12) 🚑 System recovery & rescue"
        echo "  13) ☠ Advanced tools (dangerous)"
        echo "  14) 📜 Activity log"
        echo "  15) 📊 System status report"
        echo "  16) 📊 Disk space analysis"
        echo "  17) 🧹 Disk cleanup"
        echo ""
        echo "   0) Exit"
        echo ""
        echo -e "${BOLD}   Quick CLI reference:${NC} uo --help  (after installing with install.sh)"
        echo ""
        # EOF (Ctrl+D) → clean exit; without this the loop would spin forever
        read -r -p "   Select: " choice || exit 0
        case $choice in
            1) menu_network ;;
            2) menu_system ;;
            3) menu_security ;;
            4) menu_time ;;
            5) menu_profiles ;;
            6) menu_fixnet ;;
            7) menu_testing ;;
            8) menu_packages ;;
            9) menu_appmgmt ;;
            10) menu_updates ;;
            11) menu_snapflat ;;
            12) menu_recovery ;;
            13) menu_dangerous ;;
            14) show_log; press_enter ;;
            15) system_report; press_enter ;;
            16) disk_analyze; press_enter ;;
            17) disk_cleanup; press_enter ;;
            0) clear; echo -e "${GREEN}Goodbye! 👋${NC}"; exit 0 ;;
            # Invalid user input is not a system error — logged as WARN, not ERROR
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}
