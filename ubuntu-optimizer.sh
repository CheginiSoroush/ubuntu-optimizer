#!/bin/bash
# ============================================================
#   Ubuntu Optimizer & Fixer
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#   github.com/CheginiSoroush/ubuntu-optimizer
#
#   Main project file: loads the modules, parses CLI arguments
#   and runs the interactive menu. The modules live in lib/
#   next to this file and must always be executed from this script.
#   The version is defined solely in lib/common.sh (SCRIPT_VERSION).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ---------- Load modules ----------
for _lib in common network system fixnet packages targz appmgmt snapflatpak recovery report github doctor disk gitssh menus; do
    _libfile="$SCRIPT_DIR/lib/${_lib}.sh"
    if [ -f "$_libfile" ]; then
        # shellcheck source=/dev/null
        # A module with a syntax error must abort immediately —
        # a half-loaded module causes cryptic "command not found" errors
        if ! source "$_libfile"; then
            echo "✗ Module failed to load: lib/${_lib}.sh (syntax error?)"
            echo "  ℹ Check with: bash -n lib/${_lib}.sh"
            exit 1
        fi
    else
        echo "✗ Module not found: lib/${_lib}.sh"
        echo "  ℹ Expected layout: ubuntu-optimizer.sh + lib/*.sh in one folder"
        exit 1
    fi
done
unset _lib _libfile

# ---------- Run state ----------
ASSUME_YES=0
PURGE_DATA=0
CLI_MODE=0
CLEANUP_TARGET=""
CLI_ACTIONS=()
INSTALL_TARGZ_FILE=""
INSTALL_TARGZ_NAME=""
GITHUB_INSTALL_REPO=""
GITHUB_INSTALL_NAME=""
GITHUB_REMOVE_TARGET=""
ORIG_ARGS="$*"   # original arguments for logging

usage() {
    printf 'Ubuntu Optimizer & Fixer - v%s\n\n' "$SCRIPT_VERSION"
    cat << 'EOF'
Usage:
  uo                          → interactive menu
  uo [options]                → CLI mode (no menu)

Options:
  -h, --help          show this help
  -V, --version       show the version
  -y, --yes           auto-confirm all questions
  --no-color          disable colored output
  --no-log            do not log this run
  --dry-run           preview: with --optimize/--network/--system/--security/--time
                      print what would change without changing anything

  --report            system status report (read-only)
  --disk              disk usage analysis (read-only)
  --disk-clean        disk cleanup

  --git-ssh           GitHub SSH key setup wizard
  --git-ssh-status    SSH key / GitHub authentication status

  --github-install OWNER/REPO [NAME]
                      install an app from the latest GitHub release
  --github-update     check & install updates for GitHub apps
  --github-list       list tracked GitHub apps
  --doctor            health check & repair all installed/tracked apps
  --github-remove NAME
                      fully remove a GitHub app + its tracking entry

  --install-targz FILE [NAME]
                      install an app from a .tar.gz file

  --optimize          all network + system optimizations
  --network           network optimizations (BBR, DNS, MTU, TCP)
  --system            system & memory optimizations
  --security          sudo timeout + polkit settings
  --time              sync system time
  --fixnet            create the fixnet script
  --fixnet-run        run fixnet (network repair)
  --test              network tests (ping, DNS, speed)

  --update            update all sources (apt, snap, flatpak, tar.gz, github)
  --update-apt        apt only
  --update-snap       snap only
  --update-flatpak    flatpak only
  --update-targz      check updates for tar.gz apps

  --list-apps         list all apps from all sources
  --cleanup NAME      fully remove app NAME from any source
  --purge-data        (with --cleanup) also remove user data
  --snap-clean        clean old snap revisions + unused flatpaks

  --log               show the last log lines
  --log-clear         delete the log file

Examples:
  uo --report
  uo --github-install junegunn/fzf fzf
  uo --github-remove karing
  uo --install-targz ~/Downloads/app.tar.gz myapp
  uo --update -y
  uo --cleanup abdownloadmanager --purge-data
  uo --optimize --dry-run -y
EOF
}

# ============================================================
#   Main
# ============================================================

# --help / --version are harmless, so they work for every user (even root)
# and are handled before the root check below
for _arg in "$@"; do
    case "$_arg" in
        -h|--help)    usage; exit 0 ;;
        -V|--version) echo "Ubuntu Optimizer & Fixer - v${SCRIPT_VERSION} — by CheginiSoroush"; exit 0 ;;
    esac
done
unset _arg

# Running directly as root is not allowed; sudo is requested only when needed
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}   ✗ Do not run this script with sudo.${NC}" >&2
    echo -e "${YELLOW}   ℹ It asks for the sudo password itself when needed.${NC}" >&2
    exit 1
fi

# Exit codes follow signal convention: SIGINT=130, SIGTERM=143
trap 'echo ""; warn "Exiting..."; exit 130' INT
trap 'echo ""; warn "Exiting..."; exit 143' TERM

# ---------- Parse arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)         ASSUME_YES=1; shift ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --no-color)       RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''; shift ;;
        --no-log)         LOG_ENABLED=0; shift ;;
        --report)         CLI_ACTIONS+=("system_report|system status report"); shift ;;
        --git-ssh)        CLI_ACTIONS+=("gitssh_setup|GitHub SSH setup"); shift ;;
        --git-ssh-status) CLI_ACTIONS+=("gitssh_status|GitHub SSH status"); shift ;;
        --github-update)  CLI_ACTIONS+=("github_update_apps|GitHub updates"); shift ;;
        --github-list)    CLI_ACTIONS+=("github_list_apps|GitHub app list"); shift ;;
        --doctor)         CLI_ACTIONS+=("doctor_apps|app health check"); shift ;;
        --disk)           CLI_ACTIONS+=("disk_analyze|disk analysis"); shift ;;
        --disk-clean)     CLI_ACTIONS+=("disk_cleanup|disk cleanup"); shift ;;
        --github-install)
            if [ $# -ge 2 ]; then
                case "$2" in
                    */*) GITHUB_INSTALL_REPO="$2" ;;
                    *)
                        echo "Invalid repository format: $2" >&2
                        echo "  ℹ Correct format: --github-install OWNER/REPO [NAME]" >&2
                        exit 1
                        ;;
                esac
                shift 2
                # optional name — the next argument is the app name unless it is a flag
                if [ $# -ge 1 ] && [[ "$1" != -* ]]; then
                    GITHUB_INSTALL_NAME="$1"
                    shift
                fi
            else
                echo "--github-install requires a repository: --github-install OWNER/REPO [name]" >&2
                exit 1
            fi
            ;;
        --github-remove)
            if [ $# -ge 2 ]; then
                GITHUB_REMOVE_TARGET="$2"; shift 2
            else
                echo "--github-remove requires an app name: --github-remove <name>" >&2
                exit 1
            fi
            ;;
        --install-targz)
            if [ $# -ge 2 ]; then
                if [ ! -f "$2" ]; then
                    echo "File not found: $2" >&2
                    exit 1
                fi
                INSTALL_TARGZ_FILE="$2"
                shift 2
                # optional name — the next argument is the app name unless it is a flag
                if [ $# -ge 1 ] && [[ "$1" != -* ]]; then
                    INSTALL_TARGZ_NAME="$1"
                    shift
                fi
            else
                echo "--install-targz requires a file path: --install-targz <file> [name]" >&2
                exit 1
            fi
            ;;
        --log)
            if [ -f "$LOG_FILE" ]; then
                echo "── Last 60 log lines ──"
                tail -n 60 "$LOG_FILE"
            else
                echo "No log file exists yet."
                echo "Log path: $LOG_FILE"
            fi
            exit 0
            ;;
        --log-clear)
            if [ -f "$LOG_FILE" ]; then
                rm -f "$LOG_FILE" "$LOG_FILE.old"
                echo "Log deleted."
            else
                echo "No log file to delete."
            fi
            exit 0
            ;;
        --optimize)       CLI_ACTIONS+=("all_network_opts|network optimization" "all_system_opts|system optimization"); shift ;;
        --network)        CLI_ACTIONS+=("all_network_opts|network optimization"); shift ;;
        --system)         CLI_ACTIONS+=("all_system_opts|system optimization"); shift ;;
        --security)       CLI_ACTIONS+=("all_security_opts|security settings"); shift ;;
        --time)           CLI_ACTIONS+=("fix_time|time sync"); shift ;;
        --fixnet)         CLI_ACTIONS+=("create_fixnet_script|create fixnet"); shift ;;
        --fixnet-run)     CLI_ACTIONS+=("run_fixnet|run fixnet"); shift ;;
        --test)           CLI_ACTIONS+=("all_tests|network tests"); shift ;;
        --update)         CLI_ACTIONS+=("update_all|update everything"); shift ;;
        --update-apt)     CLI_ACTIONS+=("update_apt|apt update"); shift ;;
        --update-snap)    CLI_ACTIONS+=("update_snap|snap update"); shift ;;
        --update-flatpak) CLI_ACTIONS+=("update_flatpak|flatpak update"); shift ;;
        --update-targz)   CLI_ACTIONS+=("update_targz_apps|tar.gz updates"); shift ;;
        --list-apps)      CLI_ACTIONS+=("list_all_apps|app list"); shift ;;
        --snap-clean)     CLI_ACTIONS+=("clean_snap_flatpak_junk|snap/flatpak cleanup"); shift ;;
        --purge-data)     PURGE_DATA=1; shift ;;
        --cleanup)
            if [ $# -ge 2 ]; then
                CLEANUP_TARGET="$2"; shift 2
            else
                echo "--cleanup requires an app name: --cleanup <name>" >&2
                exit 1
            fi
            ;;
        *)
            echo "Invalid option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Cross-option validation
if [ "$PURGE_DATA" = "1" ] && [ -z "$CLEANUP_TARGET" ]; then
    echo "--purge-data is only valid together with --cleanup." >&2
    exit 1
fi

# --dry-run only covers the optimization flows (the sudo wrapper intercepts them).
# Flows that remove or install apps also run plain rm/mv/tar commands that the
# wrapper cannot intercept, so they are rejected instead of silently executing.
if [ "$DRY_RUN" = "1" ]; then
    if [ -n "$CLEANUP_TARGET" ] || [ -n "$INSTALL_TARGZ_FILE" ] || \
       [ -n "$GITHUB_INSTALL_REPO" ] || [ -n "$GITHUB_REMOVE_TARGET" ]; then
        echo "--dry-run is not supported with --cleanup, --install-targz, --github-install or --github-remove." >&2
        exit 1
    fi
    if [ ${#CLI_ACTIONS[@]} -eq 0 ]; then
        echo "--dry-run requires an action: --optimize, --network, --system, --security or --time." >&2
        exit 1
    fi
    for cli_action in "${CLI_ACTIONS[@]}"; do
        case "${cli_action%%|*}" in
            all_network_opts|all_system_opts|all_security_opts|fix_time|\
            disable_wifi_powersave|set_dns|enable_bbr|set_mtu|optimize_tcp|\
            optimize_memory|set_noatime|disable_extra_services|install_preload|\
            install_tlp|limit_journal|extend_sudo_timeout|setup_polkit_rule) ;;
            *)
                echo "--dry-run is only valid with --optimize, --network, --system, --security or --time." >&2
                exit 1
                ;;
        esac
    done
fi

# ---------- CLI mode ----------
if [ ${#CLI_ACTIONS[@]} -gt 0 ] || [ -n "$CLEANUP_TARGET" ] || [ -n "$INSTALL_TARGZ_FILE" ] || [ -n "$GITHUB_INSTALL_REPO" ] || [ -n "$GITHUB_REMOVE_TARGET" ]; then
    CLI_MODE=1
    log_session_start "cli" "$ORIG_ARGS"
    trap 'log_session_end; print_session_summary' EXIT
    echo -e "${BOLD}Ubuntu Optimizer & Fixer v${SCRIPT_VERSION} — CLI mode${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        warn "── DRY RUN: commands are printed, nothing is executed ──"
    fi
    for cli_action in "${CLI_ACTIONS[@]}"; do
        "${cli_action%%|*}"
    done
    if [ -n "$INSTALL_TARGZ_FILE" ]; then
        install_targz_cli "$INSTALL_TARGZ_FILE" "$INSTALL_TARGZ_NAME"
    fi
    if [ -n "$GITHUB_INSTALL_REPO" ]; then
        github_install_repo "$GITHUB_INSTALL_REPO" "$GITHUB_INSTALL_NAME"
    fi
    if [ -n "$GITHUB_REMOVE_TARGET" ]; then
        github_remove_app "$GITHUB_REMOVE_TARGET"
    fi
    if [ -n "$CLEANUP_TARGET" ]; then
        cleanup_app "$CLEANUP_TARGET"
    fi
    echo ""
    # Exit code 1 when any step failed — so scripts/cron can detect it
    if [ "$LOG_FAIL_COUNT" -gt 0 ]; then
        warn "Finished — some steps had errors; see the log for details."
        exit 1
    fi
    success "Finished — all requested tasks completed."
    exit 0
fi

# ---------- Interactive menu ----------
log_session_start "interactive"
trap 'log_session_end; print_session_summary' EXIT
main_menu
