#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — ubuntu-optimizer.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Main entry point: loads the lib/ modules, parses CLI arguments and runs
#  either the requested actions (CLI mode) or the interactive menu. Modules
#  live in lib/ beside this file and must only be executed through it; the
#  version is defined solely in lib/common.sh (SCRIPT_VERSION).
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ── Load modules ───────────────────────────────────────────────────────────────
for _lib in common cache config network system fixnet packages targz appmgmt snapflatpak recovery report jsonreport github doctor disk htmlreport gitssh undo profile selfupdate timer menus; do
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

# ── Run state ───────────────────────────────────────────────────────────────────
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
PROFILE_NAME=""
JSON_MODE=0
OUTPUT_FILE=""
APPEND_MODE=0
AUTO_UPDATE=1        # startup self-update check (off with --no-update)
CLI_NO_UPDATE=0      # records an explicit --no-update for --config-show-style tracing
ORIG_ARGS="$*"   # original arguments for logging
ORIG_ARGS_LIST=("$@")   # original arguments for the startup self-update re-exec
# CLI_* markers record which preference flags were given explicitly — they
# let the config file (lib/config.sh) apply only where the CLI stayed silent.
CLI_YES=0
CLI_NO_COLOR=0
CLI_NO_LOG=0
CLI_DRY_RUN=0
CLI_NO_CACHE=0
CONFIG_PATH_OVERRIDE=""
NO_CONFIG=0
CONFIG_SHOW=0
TIMER_PERIOD=""
TIMER_SCOPE="user"
TIMER_NOTIFY=0
TIMER_LOG_LINES=50
DISK_REPORT_FILE=""

# ───────────────────────────────────────────────────────────────────────────────
# run_cli_profile() — dispatch --profile from the queued action list
#
# The parser stores the validated profile name in PROFILE_NAME (same pattern
# as CLEANUP_TARGET / GITHUB_INSTALL_REPO) so the dispatcher keeps calling
# single-word functions only.
#
# Globals:   PROFILE_NAME (read)
# Returns:   exit status of apply_profile
# ───────────────────────────────────────────────────────────────────────────────
run_cli_profile() {
    apply_profile "$PROFILE_NAME"
}

# ───────────────────────────────────────────────────────────────────────────────
# usage() — Print the full help text to stdout
#
# The heredoc is the single source for the option reference; it is shown
# by -h/--help and reused by the parser for invalid options (on stderr,
# followed by exit 1).
#
# Globals:   SCRIPT_VERSION (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
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
  --no-update         skip the automatic startup update check for this run
                      (UO_AUTO_UPDATE=0 disables it permanently)
  --dry-run           preview: with --optimize/--network/--system/--security/--time
                      print what would change without changing anything

  --config FILE       use FILE as the config file instead of
                      ~/.config/uo/config.conf
  --no-config         ignore every config file for this run
  --config-show       print the effective configuration and exit
  --config-example    print an annotated template config and exit

  --no-cache          bypass the TTL cache for this run (lookups miss,
                      new results are not stored)
  --cache-clear       delete every cached entry (apt lists, GitHub
                      release info, connectivity verdict)
  --cache-stats       show the cache entries with their remaining TTL

  --report            system status report (read-only)
  --json              (with --report) machine-readable JSON output
  --output FILE       (with --report) write the report to FILE instead of
                      stdout (JSON + --append produces a JSONL time-series
                      log that dashboards can tail)
  --append            (with --output) append instead of overwrite
  --disk              disk usage analysis (read-only)
  --disk-clean        disk cleanup
  --disk-report [FILE]
                      write the disk analysis as a self-contained HTML
                      report (charts + sortable tables, fully offline;
                      default: uo-disk-report.html)

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
  --undo              reverse all optimizations this tool made (drop-in
                      files, fstab backup, disabled services, DNS/powersave)
  --profile NAME      apply a curated preset: laptop | server | gaming | minimal
                      (a safe, profile-specific subset of the optimizer steps)
  --self-update       update the toolkit itself from the official GitHub repo
                      (git pull for clones, verified archive for static copies)
                      every 'uo' start also checks automatically (TTL-cached);
                      --no-update skips that check for one run
  --fixnet            create the fixnet script
  --fixnet-run        run fixnet (network repair)
  --test              network tests (ping, DNS, speed)

  --update            update all sources (apt, snap, flatpak, tar.gz, github)
  --update-apt        apt only
  --update-snap       snap only
  --update-flatpak    flatpak only
  --update-targz      check updates for tar.gz apps

  --timer-install [PERIOD]
                      install + enable a systemd timer that runs on schedule
                      (hourly | daily | weekly | monthly — default: weekly)
  --timer-remove      disable + remove the timer and its unit files
  --timer-status      installed? enabled? next runs? last result?
  --timer-log [N]     show the last N journal lines of the runs (default 50)
  --timer-preview [PERIOD]
                      print the unit files an install would write
                      (works everywhere — no systemd needed)
  --timer-system      (with --timer-install/--timer-preview) system-wide
                      units in /etc/systemd/system (sudo) instead of the
                      default user scope (~/.config/systemd/user)
  --timer-notify-only (with --timer-install/--timer-preview) monitor mode:
                      the schedule snapshots the read-only JSON report into
                      report-log.jsonl + notifies on trouble — it never
                      applies updates

  --list-apps         list all apps from all sources
  --cleanup NAME      fully remove app NAME from any source
  --purge-data        (with --cleanup) also remove user data
  --snap-clean        clean old snap revisions + unused flatpaks

  --log               show the last log lines
  --log-clear         delete the log file

Environment:
  UO_DNS_SERVERS      custom DNS servers for --network/--optimize
                      (space-separated IPv4; default: "8.8.8.8 1.1.1.1")
                      config file key DNS_SERVERS applies when this is unset
  UO_NO_CACHE         set to 1 to bypass the TTL cache for this run
                      (config file key NO_CACHE applies when this is unset)
  UO_AUTO_UPDATE      set to 0 to disable the automatic startup update check
                      (the --no-update flag overrides this for one run)
  UO_UPDATE_CHECK_TTL seconds between startup update checks (default 300;
                      0 checks on every run)
  GH_TOKEN            GitHub token — raises the API rate limit to 5000/hour

Config file:
  ~/.config/uo/config.conf — optional KEY=VALUE preferences loaded for every
  run: ASSUME_YES, NO_COLOR, NO_LOG, DRY_RUN, DNS_SERVERS, NO_CACHE.
  Precedence: built-in defaults < config file < environment < CLI flags.
  Template: uo --config-example · inspect: uo --config-show

Cache:
  Costly results (apt list refresh, GitHub release lookups, connectivity
  probes) are TTL-cached under ~/.local/share/ubuntu-optimizer/cache so
  repeated runs skip the wait. Inspect: uo --cache-stats · wipe: uo --cache-clear

Scheduled updates:
  uo --timer-install weekly puts a systemd user timer in place that runs
  'uo --update -y --no-color' every week (Persistent=true replays missed
  runs after downtime). Monitor mode (--timer-notify-only) only snapshots
  the read-only JSON report to report-log.jsonl on schedule and notifies
  when something needs attention. Inspect: uo --timer-status

Examples:
  uo                       # menu — first a quick update check, then the menu
  uo --no-update           # skip the startup update check once
  UO_UPDATE_CHECK_TTL=0 uo # force the update check on every single start
  uo --report
  uo --github-install junegunn/fzf fzf
  uo --github-remove karing
  uo --install-targz ~/Downloads/app.tar.gz myapp
  uo --update -y
  uo --cleanup abdownloadmanager --purge-data
  uo --optimize --dry-run -y
  uo --profile laptop   # one safe preset for the whole scenario
  uo --undo             # reverse everything the optimizer changed
  uo --self-update      # keep the toolkit itself on the latest version
  uo --report --json | jq '.summary'   # pipe the report into scripts
  uo --report --json --output ~/report.json           # snapshot into a file
  uo --report --json --append \
     --output ~/.local/share/ubuntu-optimizer/report-log.jsonl
  #  → one JSON line per run: a time-series log for dashboards (cron-friendly)
  uo --config-show      # inspect the effective configuration
  uo --config-example > ~/.config/uo/config.conf   # start a config file
  uo --cache-clear --update-apt    # force a fresh apt list refresh
  uo --cache-stats    # what is cached right now, and for how long
  uo --timer-install weekly          # weekly unattended 'uo --update -y'
  uo --timer-preview monthly         # show the unit files, install nothing
  uo --timer-install daily --timer-notify-only   # read-only monitor tick
  uo --disk-report ~/disk-report.html   # shareable HTML disk analysis (charts)
EOF
}

# ── Main ────────────────────────────────────────────────────────────────────────

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

# ── Parse arguments ─────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)         ASSUME_YES=1; CLI_YES=1; shift ;;
        --dry-run)        DRY_RUN=1; CLI_DRY_RUN=1; shift ;;
        --no-update)      AUTO_UPDATE=0; CLI_NO_UPDATE=1; shift ;;
        --no-color)       RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''; CLI_NO_COLOR=1; shift ;;
        --no-log)         LOG_ENABLED=0; CLI_NO_LOG=1; shift ;;
        --report)         CLI_ACTIONS+=("system_report|system status report"); shift ;;
        --json)           JSON_MODE=1; shift ;;
        --output)
            if [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != -* ]]; then
                OUTPUT_FILE="$2"; shift 2
            else
                echo "--output requires a file path: --output <file>" >&2
                exit 1
            fi
            ;;
        --append)         APPEND_MODE=1; shift ;;
        --config)
            if [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != -* ]]; then
                if [ ! -f "$2" ]; then
                    echo "Config file not found: $2" >&2
                    exit 1
                fi
                CONFIG_PATH_OVERRIDE="$2"; shift 2
            else
                echo "--config requires a file path: --config <file>" >&2
                exit 1
            fi
            ;;
        --no-config)      NO_CONFIG=1; shift ;;
        --config-show)    CONFIG_SHOW=1; shift ;;
        --config-example) uo_config_example; exit 0 ;;
        --no-cache)       NO_CACHE=1; CLI_NO_CACHE=1; shift ;;
        --cache-clear)    CLI_ACTIONS+=("cache_maintenance_clear|cache clear"); shift ;;
        --cache-stats)    CLI_ACTIONS+=("cache_maintenance_stats|cache stats"); shift ;;
        --timer-install)
            if [ $# -ge 2 ] && [[ "$2" != -* ]]; then
                if ! timer_period_is_valid "$2"; then
                    echo "Invalid timer period: $2" >&2
                    echo "  ℹ Valid periods: hourly · daily · weekly · monthly" >&2
                    exit 1
                fi
                TIMER_PERIOD="$2"; shift 2
            else
                shift
            fi
            CLI_ACTIONS+=("timer_cli_install|timer install")
            ;;
        --timer-remove)   CLI_ACTIONS+=("timer_cli_remove|timer remove"); shift ;;
        --timer-status)   CLI_ACTIONS+=("timer_cli_status|timer status"); shift ;;
        --timer-tick)     CLI_ACTIONS+=("timer_tick|monitor tick"); shift ;;
        --timer-log)
            if [ $# -ge 2 ] && [[ "$2" != -* ]]; then
                if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Invalid line count: $2" >&2
                    echo "  ℹ Usage: --timer-log [N] (a positive integer, default 50)" >&2
                    exit 1
                fi
                TIMER_LOG_LINES="$2"; shift 2
            else
                shift
            fi
            CLI_ACTIONS+=("timer_cli_log|timer log")
            ;;
        --timer-preview)
            if [ $# -ge 2 ] && [[ "$2" != -* ]]; then
                if ! timer_period_is_valid "$2"; then
                    echo "Invalid timer period: $2" >&2
                    echo "  ℹ Valid periods: hourly · daily · weekly · monthly" >&2
                    exit 1
                fi
                TIMER_PERIOD="$2"; shift 2
            else
                shift
            fi
            CLI_ACTIONS+=("timer_cli_preview|timer preview")
            ;;
        --timer-system)      TIMER_SCOPE="system"; shift ;;
        --timer-notify-only) TIMER_NOTIFY=1; shift ;;
        --git-ssh)        CLI_ACTIONS+=("gitssh_setup|GitHub SSH setup"); shift ;;
        --git-ssh-status) CLI_ACTIONS+=("gitssh_status|GitHub SSH status"); shift ;;
        --github-update)  CLI_ACTIONS+=("github_update_apps|GitHub updates"); shift ;;
        --github-list)    CLI_ACTIONS+=("github_list_apps|GitHub app list"); shift ;;
        --doctor)         CLI_ACTIONS+=("doctor_apps|app health check"); shift ;;
        --disk)           CLI_ACTIONS+=("disk_analyze|disk analysis"); shift ;;
        --disk-clean)     CLI_ACTIONS+=("disk_cleanup|disk cleanup"); shift ;;
        --disk-report)
            # optional destination — a following flag is never eaten as the file
            if [ $# -ge 2 ] && [[ "$2" != -* ]]; then
                DISK_REPORT_FILE="$2"; shift 2
            else
                shift
            fi
            CLI_ACTIONS+=("disk_report_cli|disk HTML report")
            ;;
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
        --undo)           CLI_ACTIONS+=("undo_all_optimizations|undo optimizations"); shift ;;
        --self-update)    CLI_ACTIONS+=("self_update_interactive|self update"); shift ;;
        --profile)
            if [ $# -ge 2 ]; then
                if [ -n "$PROFILE_NAME" ]; then
                    echo "--profile can only be given once." >&2
                    exit 1
                fi
                if ! profile_is_valid "$2"; then
                    echo "Unknown profile: $2" >&2
                    echo "  ℹ Valid profiles: ${PROFILE_NAMES[*]}" >&2
                    exit 1
                fi
                PROFILE_NAME="$2"
                CLI_ACTIONS+=("run_cli_profile|$2 profile")
                shift 2
            else
                echo "--profile requires a name: --profile laptop|server|gaming|minimal" >&2
                exit 1
            fi
            ;;
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

# ── Configuration file ──────────────────────────────────────────────────────────
# Loaded once, after parsing: explicit CLI flags already set their CLI_*
# markers, so the config only fills the gaps (defaults < config < env < CLI).
# --config-show is a read-only introspection mode: load, print, exit.
if [ "$CONFIG_SHOW" = "1" ]; then
    uo_config_load
    uo_config_show
    exit 0
fi
uo_config_load

# Cross-option validation
if [ "$PURGE_DATA" = "1" ] && [ -z "$CLEANUP_TARGET" ]; then
    echo "--purge-data is only valid together with --cleanup." >&2
    exit 1
fi

# --output is a report-only destination: every other action prints
# human-only progress that must stay on the terminal. --append only makes
# sense relative to a file.
if [ -n "$OUTPUT_FILE" ]; then
    if [ ${#CLI_ACTIONS[@]} -eq 0 ] || [ "${CLI_ACTIONS[0]%%|*}" != "system_report" ]; then
        echo "--output is only valid together with --report." >&2
        exit 1
    fi
    if [ "$APPEND_MODE" = "1" ]; then
        # append: the directory must exist+be writable, and an existing file
        # must be writable — nothing is truncated here, ever
        if [ ! -w "$(dirname -- "$OUTPUT_FILE")" ] || \
           { [ -e "$OUTPUT_FILE" ] && [ ! -w "$OUTPUT_FILE" ]; }; then
            echo "Cannot write to file: $OUTPUT_FILE" >&2
            exit 1
        fi
    else
        # overwrite: an existing file must be writable, otherwise its
        # directory must be (this check replaces the file only at write time)
        if { [ -e "$OUTPUT_FILE" ] && [ ! -w "$OUTPUT_FILE" ]; } || \
           [ ! -w "$(dirname -- "$OUTPUT_FILE")" ]; then
            echo "Cannot write to file: $OUTPUT_FILE" >&2
            exit 1
        fi
    fi
fi
if [ "$APPEND_MODE" = "1" ] && [ -z "$OUTPUT_FILE" ]; then
    echo "--append is only valid together with --output." >&2
    exit 1
fi

# --disk-report validates its destination up front (fail fast): the default
# lands beside the working directory, an existing file must be writable and
# its directory must be writable — nothing is touched before this check.
if [ ${#CLI_ACTIONS[@]} -gt 0 ]; then
    for hr_action in "${CLI_ACTIONS[@]}"; do
        if [ "${hr_action%%|*}" = "disk_report_cli" ]; then
            [ -n "$DISK_REPORT_FILE" ] || DISK_REPORT_FILE="$PWD/uo-disk-report.html"
            if { [ -e "$DISK_REPORT_FILE" ] && [ ! -w "$DISK_REPORT_FILE" ]; } || \
               [ ! -w "$(dirname -- "$DISK_REPORT_FILE")" ]; then
                echo "Cannot write to file: $DISK_REPORT_FILE" >&2
                exit 1
            fi
        fi
    done
    unset hr_action
fi

# --timer-system / --timer-notify-only are unit-rendering modifiers: they
# only have meaning where unit files are rendered (install / preview).
if [ "$TIMER_SCOPE" = "system" ] || [ "$TIMER_NOTIFY" = "1" ]; then
    timer_modifier_ok=0
    if [ ${#CLI_ACTIONS[@]} -gt 0 ]; then
        for timer_action in "${CLI_ACTIONS[@]}"; do
            case "${timer_action%%|*}" in
                timer_cli_install|timer_cli_preview) timer_modifier_ok=1 ;;
            esac
        done
    fi
    if [ "$timer_modifier_ok" = "0" ]; then
        echo "--timer-system / --timer-notify-only are only valid together with --timer-install or --timer-preview." >&2
        exit 1
    fi
    unset timer_action
fi
unset timer_modifier_ok

# --json is a strict output format for exactly one flow: --report. Every other
# action prints human-only text (banners, confirmations, progress), so a mixed
# invocation would produce a corrupt document — rejected instead.
if [ "$JSON_MODE" = "1" ]; then
    if [ ${#CLI_ACTIONS[@]} -ne 1 ] || [ "${CLI_ACTIONS[0]%%|*}" != "system_report" ]; then
        echo "--json is only valid together with --report." >&2
        exit 1
    fi
    # Pure-JSON stdout: colors are never wanted inside a JSON document
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''
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
        echo "--dry-run requires an action: --optimize, --network, --system, --security, --time, --undo, --profile or --self-update." >&2
        exit 1
    fi
    for cli_action in "${CLI_ACTIONS[@]}"; do
        # The queued action is "function [arg]|label" — only the function
        # word matters here (e.g. "apply_profile laptop")
        cli_fn="${cli_action%%|*}"
        cli_fn="${cli_fn%% *}"
        case "$cli_fn" in
            all_network_opts|all_system_opts|all_security_opts|fix_time|undo_all_optimizations|apply_profile|run_cli_profile|self_update_interactive|\
            disable_wifi_powersave|set_dns|enable_bbr|set_mtu|optimize_tcp|\
            optimize_memory|set_noatime|disable_extra_services|install_preload|\
            install_tlp|limit_journal|extend_sudo_timeout|setup_polkit_rule) ;;
            *)
                echo "--dry-run is only valid with --optimize, --network, --system, --security, --time, --undo, --profile or --self-update." >&2
                exit 1
                ;;
        esac
    done
    unset cli_fn
fi

# ── Startup self-update check ────────────────────────────────────────────────
# 'uo' keeps itself current: before anything runs, a quick TTL-cached version
# check compares the local SCRIPT_VERSION with the official repository and —
# when a newer release exists — offers to apply it first, then re-execs the
# new code with the original arguments. Skippable for one run with
# --no-update (or permanently with UO_AUTO_UPDATE=0); offline, declined or
# failed checks fall through to the normal run, so this can never block work.
selfupdate_auto_check "${ORIG_ARGS_LIST[@]}"

# ── CLI mode ─────────────────────────────────────────────────────────────────────
if [ ${#CLI_ACTIONS[@]} -gt 0 ] || [ -n "$CLEANUP_TARGET" ] || [ -n "$INSTALL_TARGZ_FILE" ] || [ -n "$GITHUB_INSTALL_REPO" ] || [ -n "$GITHUB_REMOVE_TARGET" ]; then
    CLI_MODE=1
    log_session_start "cli" "$ORIG_ARGS"
    trap 'log_session_end; [ "$JSON_MODE" = "1" ] || print_session_summary' EXIT
    if [ "$JSON_MODE" != "1" ]; then
        echo -e "${BOLD}Ubuntu Optimizer & Fixer v${SCRIPT_VERSION} — CLI mode${NC}"
    fi
    if [ "$DRY_RUN" = "1" ]; then
        warn "── DRY RUN: commands are printed, nothing is executed ──"
    fi
    # Each queued action is "function|label" — dispatch to the function part.
    # JSON mode swaps the plain-text report for its machine-readable twin.
    # --output redirects the report into a file (>> appends a JSONL series);
    # everything else keeps printing to the terminal as usual.
    for cli_action in "${CLI_ACTIONS[@]}"; do
        cli_dispatch_fn="${cli_action%%|*}"
        if [ "$JSON_MODE" = "1" ] && [ "$cli_dispatch_fn" = "system_report" ]; then
            cli_dispatch_fn="system_report_json"
        fi
        if [ -n "$OUTPUT_FILE" ] && { [ "$cli_dispatch_fn" = "system_report_json" ] || [ "$cli_dispatch_fn" = "system_report" ]; }; then
            if [ "$APPEND_MODE" = "1" ]; then
                "$cli_dispatch_fn" >> "$OUTPUT_FILE"
            else
                "$cli_dispatch_fn" > "$OUTPUT_FILE"
            fi
        else
            "$cli_dispatch_fn"
        fi
    done
    unset cli_dispatch_fn
    if [ -n "$OUTPUT_FILE" ]; then
        if [ "$JSON_MODE" = "1" ]; then
            echo "Report saved to: $OUTPUT_FILE" >&2
        else
            echo "ℹ Report saved to: $OUTPUT_FILE"
        fi
    fi
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
    # Human-only closing lines stay off the stdout stream in JSON mode
    if [ "$JSON_MODE" != "1" ]; then
        echo ""
        # Exit code 1 when any step failed — so scripts/cron can detect it
        if [ "$LOG_FAIL_COUNT" -gt 0 ]; then
            warn "Finished — some steps had errors; see the log for details."
            exit 1
        fi
        success "Finished — all requested tasks completed."
    elif [ "$LOG_FAIL_COUNT" -gt 0 ]; then
        exit 1
    fi
    exit 0
fi

# ── Interactive menu ─────────────────────────────────────────────────────────────
log_session_start "interactive"
trap 'log_session_end; print_session_summary' EXIT
main_menu
