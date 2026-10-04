# shellcheck shell=bash
# ============================================================
#   lib/menus.sh — menu engine, submenus and the main menu
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

# Generic menu engine — each item is "title|function_name"
# Usage: menu_loop "title" [-w "warning"]... "item"...
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

# ---------- Submenus ----------
menu_network() {
    menu_loop "🌐 Network Optimization" \
        "Disable Wi-Fi power management|disable_wifi_powersave" \
        "Set DNS to 8.8.8.8 & 1.1.1.1|set_dns" \
        "Enable BBR congestion control|enable_bbr" \
        "Set MTU (default 1492)|set_mtu" \
        "Optimize TCP parameters|optimize_tcp" \
        "Run all of the above|all_network_opts"
}

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

menu_security() {
    menu_loop "🔐 Security & Passwords" \
        "Extend sudo password timeout|extend_sudo_timeout" \
        "Create polkit rule|setup_polkit_rule" \
        "Run both|all_security_opts" \
        "Set up GitHub SSH key (passwordless)|gitssh_setup" \
        "GitHub SSH status|gitssh_status"
}

menu_time() {
    menu_loop "🕐 Time & NTP" \
        "Fix time sync with chrony|fix_time" \
        "Show time status|show_time_status"
}

menu_fixnet() {
    menu_loop "🛠 fixnet Script" \
        "Create the fixnet script (bilingual)|create_fixnet_script" \
        "Run fixnet|run_fixnet"
}

menu_testing() {
    menu_loop "📊 Network Tests" \
        "Ping test to 8.8.8.8|test_ping" \
        "DNS test (ping google.com)|test_ping_dns" \
        "Internet speed test|test_speed" \
        "Show full network info|show_network_info" \
        "Run all tests|all_tests"
}

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

menu_updates() {
    menu_loop "🔄 Update Apps" \
        "Update everything (apt + snap + flatpak + tar.gz + github)|update_all" \
        "Update apt (system & deb packages)|update_apt" \
        "Update snap|update_snap" \
        "Update flatpak|update_flatpak" \
        "Check tar.gz app updates|update_targz_apps" \
        "Check GitHub app updates|github_update_apps"
}

menu_recovery() {
    menu_loop "🚑 System Recovery & Rescue" \
        "Fix broken packages (apt --fix-broken)|fix_broken" \
        "Reinstall the desktop environment|reinstall_desktop" \
        "Configure pending packages with dpkg|fix_dpkg_configure"
}

menu_dangerous() {
    menu_loop "☠ Advanced Tools (Dangerous)" \
        -w "This section contains powerful tools that, if used incorrectly," \
        -w "can cause serious damage to your system!" \
        "Install VEET (deep removal tool — warned)|install_veet"
}

# ---------- Main menu ----------
# The banner is generated programmatically: the border width (54)
# matches the printf %-54s lines, so alignment can never drift.
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
        echo ""
        echo -e "${BOLD}   ── Emergency & Diagnostics ──${NC}"
        echo "   5) 🛠 Create & run fixnet"
        echo "   6) 📊 Network & speed tests"
        echo ""
        echo -e "${BOLD}   ── Applications ──${NC}"
        echo "   7) 📦 Install packages & apps"
        echo "   8) 🧹 Manage & fully remove apps"
        echo "   9) 🔄 Update apps"
        echo "  10) 🧩 snap & flatpak management"
        echo ""
        echo -e "${BOLD}   ── System & Info ──${NC}"
        echo "  11) 🚑 System recovery & rescue"
        echo "  12) ☠ Advanced tools (dangerous)"
        echo "  13) 📜 Activity log"
        echo "  14) 📊 System status report"
        echo "  15) 📊 Disk space analysis"
        echo "  16) 🧹 Disk cleanup"
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
            5) menu_fixnet ;;
            6) menu_testing ;;
            7) menu_packages ;;
            8) menu_appmgmt ;;
            9) menu_updates ;;
            10) menu_snapflat ;;
            11) menu_recovery ;;
            12) menu_dangerous ;;
            13) show_log; press_enter ;;
            14) system_report; press_enter ;;
            15) disk_analyze; press_enter ;;
            16) disk_cleanup; press_enter ;;
            0) clear; echo -e "${GREEN}Goodbye! 👋${NC}"; exit 0 ;;
            # Invalid user input is not a system error — logged as WARN, not ERROR
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}
