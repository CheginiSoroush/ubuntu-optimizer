# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/fzf.sh
# ───────────────────────────────────────────────────────────────────────────────
#  The fzf-powered launcher: `uo --fzf` (and main-menu entry 22) lists the
#  toolkit's actions in an fzf UI and runs the one the user picks. Fully
#  graceful when fzf is absent: exactly one friendly hint with the install
#  command, exit 0 — it never auto-installs and never error-spams. The action
#  list is a pure helper (_fzf_actions) whose keys are the exact function
#  names the interactive menus dispatch to, so no action logic lives here
#  and every picked entry runs precisely what the menu would run.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# i18n (lib/i18n.sh) provides the t() helper the missing-fzf hint renders
# through. The entry script loads it as a module in the normal startup order;
# when this file is sourced standalone (the test suite does), pull it in —
# the load-once guard inside i18n.sh keeps this a no-op either way.
if ! declare -F t > /dev/null 2>&1; then
    # shellcheck source=lib/i18n.sh
    source "${BASH_SOURCE[0]%/*}/i18n.sh"
fi

# ───────────────────────────────────────────────────────────────────────────────
# _fzf_actions() — emit the fzf menu as "label|action_key" lines
#
# Pure helper — only the printf builtin, no fzf, no terminal, no side effects,
# so tests can exercise it on an empty PATH. Every action_key is the exact
# function name lib/menus.sh (or the timer / disk-report menus) dispatches to;
# labels are reused from those menus. Destructive entries (cleanup_app,
# browser_clean, undo, ...) keep their own existing confirm/-y guards. The two
# flows that live behind explicit warning screens or heavy reinstall prompts
# (the dangerous-tools VEET entry, reinstall desktop) are deliberately NOT
# offered here — they stay behind their warning screens in the main menu.
#
# Arguments: none
# Returns:   0 — the list goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_fzf_actions() {
    printf '%s\n' \
        'System status report|system_report' \
        'Disk space analysis|disk_analyze' \
        'Disk cleanup|disk_cleanup' \
        'Disk report (HTML, shareable)|menu_disk_report' \
        'Activity log|show_log' \
        'System health snapshot|health_show' \
        'Find large files|bigfiles_menu' \
        'Listening ports|ports_show' \
        'Browser cache cleanup|browser_clean' \
        'Boot time analysis (slowest units + verdict)|boot_show' \
        'Failed system units|boot_failed_show' \
        'List startup applications|autostart_show' \
        'Disable a startup application|autostart_disable_menu' \
        'Enable a startup application|autostart_enable_menu' \
        'Disable Wi-Fi power management|disable_wifi_powersave' \
        'Set DNS to 8.8.8.8 & 1.1.1.1|set_dns' \
        'Enable BBR congestion control|enable_bbr' \
        'Set MTU (default 1492)|set_mtu' \
        'Optimize TCP parameters|optimize_tcp' \
        'Run all of the above (network)|all_network_opts' \
        'Reduce swappiness & vfs_cache_pressure|optimize_memory' \
        'Add noatime to /etc/fstab|set_noatime' \
        'Disable extra services|disable_extra_services' \
        'Install preload|install_preload' \
        'Install tlp (battery management)|install_tlp' \
        'Limit journal log size|limit_journal' \
        'Run all of the above (system)|all_system_opts' \
        'Extend sudo password timeout|extend_sudo_timeout' \
        'Create polkit rule|setup_polkit_rule' \
        'Run both (security)|all_security_opts' \
        'Set up GitHub SSH key (passwordless)|gitssh_setup' \
        'GitHub SSH status|gitssh_status' \
        'Fix time sync with chrony|fix_time' \
        'Show time status|show_time_status' \
        'Create the fixnet script (bilingual)|create_fixnet_script' \
        'Run fixnet|run_fixnet' \
        'Ping test to 8.8.8.8|test_ping' \
        'DNS test (ping google.com)|test_ping_dns' \
        'Internet speed test|test_speed' \
        'Show full network info|show_network_info' \
        'Run all tests|all_tests' \
        'Install essential tools (curl, wget, git, ...)|install_essential_tools' \
        'Install archive tools (unrar, p7zip, file-roller)|install_unrar' \
        'Install a .deb file|install_deb' \
        'Install app from .tar.gz (smart + registry)|install_targz' \
        'Install app from GitHub (latest release)|github_install_repo' \
        'Install nodejs and npm|install_nodejs' \
        'Install AppClean|install_appclean' \
        'Install from AppImage file|install_appimage' \
        'List all installed apps (all sources)|list_all_apps' \
        'Health check & repair all installed apps|doctor_apps' \
        'Fully remove an app from any source (with data)|cleanup_app' \
        'List tracked GitHub apps|github_list_apps' \
        'Remove a tracked GitHub app|github_remove_app' \
        'Clean leftover deb package configs|cleanup_deb_residuals' \
        'Remove orphan desktop files|cleanup_desktop_orphans' \
        'Update everything (apt + snap + flatpak + tar.gz + github)|update_all' \
        'Update apt (system & deb packages)|update_apt' \
        'Update snap|update_snap' \
        'Update flatpak|update_flatpak' \
        'Check tar.gz app updates|update_targz_apps' \
        'Check GitHub app updates|github_update_apps' \
        'Update this toolkit itself (self-update)|self_update_interactive' \
        'List snap apps|snap_list_apps' \
        'Install a snap|snap_install_app' \
        'Remove a snap|snap_remove_app' \
        'Clean old snap revisions (reclaim disk space)|snap_clean_revisions' \
        'List flatpak apps|flatpak_list_apps' \
        'Install a flatpak|flatpak_install_app' \
        'Remove a flatpak|flatpak_remove_app' \
        'Clean unused flatpak runtimes|flatpak_clean_unused' \
        'Clean old snap revisions + unused flatpaks|clean_snap_flatpak_junk' \
        'Laptop — battery & responsiveness|profile_run_laptop' \
        'Server — throughput, no desktop extras|profile_run_server' \
        'Gaming — lowest latency only|profile_run_gaming' \
        'Minimal — the conservative core|profile_run_minimal' \
        'Fix broken packages (apt --fix-broken)|fix_broken' \
        'Configure pending packages with dpkg|fix_dpkg_configure' \
        'Undo all optimizations (restore defaults)|undo_all_optimizations' \
        'Scheduled timer status|timer_cli_status' \
        'Scheduled timer run log|timer_cli_log'
}

# ───────────────────────────────────────────────────────────────────────────────
# run_cli_fzf() — show the action list in fzf and run the picked action
#
# Launcher behind `uo --fzf` (CLI mode) and main-menu entry 22. The binary is
# resolved from UO_FZF_BIN when set (path or name), else the first fzf on
# PATH. When fzf is missing: one friendly hint with the exact install command
# and a clean exit 0 — never auto-install, never an error. Esc, Ctrl+C and an
# empty selection are clean cancels (exit 0, no output). Everything else maps
# the selected "label|action_key" line to the same dispatch the menus use:
# the function named by the key is called like menu_loop calls its targets.
#
# Globals:   UO_FZF_BIN (read)
# Arguments: none
# Returns:   0 — hint shown, cancel or action completed
#            1 — the dispatched action itself failed (propagated)
# ───────────────────────────────────────────────────────────────────────────────
run_cli_fzf() {
    local fzf_bin="${UO_FZF_BIN:-fzf}"
    local selected action_key fzf_status=0

    # Graceful absence: a single friendly hint, then a clean exit —
    # the toolkit never installs anything on its own
    if ! command -v "$fzf_bin" > /dev/null 2>&1; then
        info "$(t msg.fzf_missing)"
        return 0
    fi

    # fzf UI: the action list on stdin, the picked line on stdout.
    # Enter runs the selection, Esc cancels — both explained in the header.
    selected=$(_fzf_actions | "$fzf_bin" --header="Enter=run · Esc=cancel" --prompt="uo> ") || fzf_status=$?
    if [ "$fzf_status" -ne 0 ] || [ -z "$selected" ]; then
        # Esc / Ctrl+C / empty selection — a clean cancel, never an error
        return 0
    fi

    # Same dispatch mechanism as menu_loop: the key after the last "|" is the
    # exact function name the interactive menus call
    local dispatch_status=0
    action_key="${selected##*|}"
    if declare -F "$action_key" > /dev/null; then
        "$action_key" || dispatch_status=$?
    else
        failure "Function '$action_key' not found — check the menu definition"
    fi
    return "$dispatch_status"
}
