# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/common.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Shared foundation for every module: version and path constants, the
#  logging system, colored output helpers, the dry-run sudo wrapper and
#  the tar.gz application registry. Never executed directly — always
#  sourced by ubuntu-optimizer.sh together with the other lib/ modules.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Version (single source of truth for the whole project) ─────────────
readonly SCRIPT_VERSION="7.12"

# ── Constants ─────────────────────────────────────────────────────────────────
readonly SYSCTL_CONF="/etc/sysctl.d/99-ubuntu-optimizer.conf"
readonly JOURNALD_DROPIN="/etc/systemd/journald.conf.d/99-optimizer.conf"
readonly SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/99-optimizer-timeout"
readonly POLKIT_RULE_FILE="/etc/polkit-1/rules.d/10-disable-password-timeout.rules"
readonly REGISTRY_DIR="$HOME/.local/share/ubuntu-optimizer"
readonly REGISTRY_DB="$REGISTRY_DIR/apps.db"

# ── Logging ────────────────────────────────────────────────────────────────────
readonly LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-optimizer"
readonly LOG_FILE="$LOG_DIR/optimizer.log"
readonly LOG_MAX_BYTES=1048576   # 1MB — beyond this the log rotates to .old

LOG_ENABLED=1
LOG_OK_COUNT=0
LOG_FAIL_COUNT=0
LOG_WARN_COUNT=0

# extglob for the ANSI-strip pattern in log_write —
# must be enabled before the functions below are parsed
shopt -s extglob

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Non-interactive output (pipe/redirect): colors are disabled automatically
if [ ! -t 1 ]; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''
fi

# ── Logging system ─────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# _strip_ansi() — Remove ANSI color escape sequences from a string
#
# Implemented with the extglob pattern enabled at the top of this file, so
# no sed fork is needed. The logging helpers strip inline with the same
# pattern; this helper is exercised by the test suite.
#
# Arguments: $1 — text that may contain color codes
# Returns:   0 — always; the cleaned text goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_strip_ansi() {
    printf '%s' "${1//$'\e'\[*([0-9;])m/}"
}

# ───────────────────────────────────────────────────────────────────────────────
# _log_rotate() — Rotate the log file once it exceeds LOG_MAX_BYTES
#
# Moves the current log to $LOG_FILE.old, replacing any previous rotation.
# Called at session start so an oversized log never grows unbounded.
#
# Globals:   LOG_FILE, LOG_MAX_BYTES (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_log_rotate() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.old"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# log_write() — Append one line to the log file
#
# Creates $LOG_DIR on demand and formats the timestamp with printf's
# built-in %(..)T, so the whole call is pure Bash — no date or sed fork.
# ANSI codes are stripped inline. A no-op when logging is disabled.
#
# Globals:   LOG_ENABLED, LOG_DIR, LOG_FILE (read)
# Arguments: $1 — level tag (OK / ERROR / INFO / WARN / SESSION / SECTION)
#            $2 — message text
# Returns:   0 — written, or silently skipped when disabled/unavailable
#            1 — the final append itself failed (permissions, disk full)
# ───────────────────────────────────────────────────────────────────────────────
log_write() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    # %(..)T with the argument -1 expands to the current time
    printf '[%(%Y-%m-%d %H:%M:%S)T] %-8s %s\n' -1 "$1" "${2//$'\e'\[*([0-9;])m/}" >> "$LOG_FILE"
}

# ───────────────────────────────────────────────────────────────────────────────
# log_session_start() — Open a session block in the log
#
# Rotates an oversized log first, then writes the session banner with the
# invocation mode and the raw CLI arguments. Called once by
# ubuntu-optimizer.sh in both CLI and interactive mode.
#
# Globals:   LOG_ENABLED (read)
# Arguments: $1 — mode tag (cli / interactive)
#            $2.. — raw invocation arguments, appended to the banner
# Returns:   0 — normally; a failed log append propagates
# ───────────────────────────────────────────────────────────────────────────────
log_session_start() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    _log_rotate
    local mode="$1"
    shift
    local extra=""
    [ $# -gt 0 ] && extra=" | args: $*"
    log_write "SESSION" "════ session start ($mode)$extra ════"
}

# ───────────────────────────────────────────────────────────────────────────────
# log_session_end() — Close the session block and log the counters
#
# Writes the ok/error/warning totals accumulated during the run, followed
# by the session-end banner. Invoked from the EXIT trap in
# ubuntu-optimizer.sh.
#
# Globals:   LOG_ENABLED, LOG_OK_COUNT, LOG_FAIL_COUNT, LOG_WARN_COUNT (read)
# Arguments: none
# Returns:   0 — normally; a failed log append propagates
# ───────────────────────────────────────────────────────────────────────────────
log_session_end() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    log_write "SESSION" "session summary: ok=$LOG_OK_COUNT  errors=$LOG_FAIL_COUNT  warnings=$LOG_WARN_COUNT"
    log_write "SESSION" "════ session end ════"
}

# ───────────────────────────────────────────────────────────────────────────────
# print_session_summary() — Print the run's counter summary to the terminal
#
# Shows the ok/error/warning totals and, when logging is on, the path of
# the full log. Runs from the EXIT trap so it closes both CLI and menu
# runs.
#
# Globals:   LOG_OK_COUNT, LOG_FAIL_COUNT, LOG_WARN_COUNT, LOG_ENABLED,
#            LOG_FILE (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
print_session_summary() {
    echo ""
    echo -e "${BOLD}── Session summary ──${NC}"
    echo -e "   ✓ OK: $LOG_OK_COUNT     ✗ Errors: $LOG_FAIL_COUNT     ⚠ Warnings: $LOG_WARN_COUNT"
    # TTL cache line only when the cache was actually consulted this run
    if [ "${CACHE_HITS:-0}" -gt 0 ] || [ "${CACHE_MISSES:-0}" -gt 0 ]; then
        echo -e "   ⚡ Cache: ${CACHE_HITS:-0} hit(s), ${CACHE_MISSES:-0} miss(es) — ${CACHE_DIR:-unknown}"
    fi
    if [ "$LOG_ENABLED" = "1" ]; then
        echo -e "   ℹ Full log: $LOG_FILE"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# show_log() — Show the last 60 log lines (interactive menu)
#
# Prints the tail of $LOG_FILE and points at the rotated .old file when one
# exists; explains where the log will be created when nothing has been
# logged yet.
#
# Globals:   LOG_FILE (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
show_log() {
    header "📜 Activity log (last 60 lines)"
    if [ -f "$LOG_FILE" ]; then
        tail -n 60 "$LOG_FILE"
        echo ""
        info "Full path: $LOG_FILE"
        [ -f "$LOG_FILE.old" ] && info "Older log: $LOG_FILE.old"
    else
        info "Nothing has been logged yet."
        info "The log is created at: $LOG_FILE"
    fi
    return 0
}

# ── Output (terminal + simultaneous logging) ──────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# success() — Report a successful step (green check mark)
#
# Prints the message and records it in the log; the OK counter feeds the
# session summary printed at exit.
#
# Globals:   LOG_OK_COUNT (incremented)
# Arguments: $1 — message
# Returns:   0 — unless the log append fails
# ───────────────────────────────────────────────────────────────────────────────
success() {
    echo -e "${GREEN}   ✓ $1${NC}"
    LOG_OK_COUNT=$((LOG_OK_COUNT + 1))
    log_write "OK" "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# failure() — Report a failed step (red cross)
#
# Prints the message and records it in the log. The error counter drives
# the CLI-mode exit code (1 when any step failed).
#
# Globals:   LOG_FAIL_COUNT (incremented)
# Arguments: $1 — message
# Returns:   0 — unless the log append fails
# ───────────────────────────────────────────────────────────────────────────────
failure() {
    echo -e "${RED}   ✗ $1${NC}"
    LOG_FAIL_COUNT=$((LOG_FAIL_COUNT + 1))
    log_write "ERROR" "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# info() — Show an informational note (yellow)
#
# Printed to the terminal and recorded in the log, but not counted as a
# success or a failure.
#
# Arguments: $1 — message
# Returns:   0 — unless the log append fails
# ───────────────────────────────────────────────────────────────────────────────
info() {
    echo -e "${YELLOW}   ℹ $1${NC}"
    log_write "INFO" "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# warn() — Show a warning (magenta)
#
# Prints the message and records it in the log; warnings are counted but
# do not affect the CLI exit code.
#
# Globals:   LOG_WARN_COUNT (incremented)
# Arguments: $1 — message
# Returns:   0 — unless the log append fails
# ───────────────────────────────────────────────────────────────────────────────
warn() {
    echo -e "${MAGENTA}   ⚠ $1${NC}"
    LOG_WARN_COUNT=$((LOG_WARN_COUNT + 1))
    log_write "WARN" "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# header() — Print a cyan section banner
#
# Emits a blank line, the title framed by rules, and logs the section
# name. Every feature function starts its output with this call, which is
# what keeps the CLI transcript readable.
#
# Arguments: $1 — section title
# Returns:   0 — unless the log append fails
# ───────────────────────────────────────────────────────────────────────────────
header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}   $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    log_write "SECTION" "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# press_enter() — Pause until Enter (skipped in CLI mode)
#
# CLI runs print only a blank line so piped output stays clean;
# interactive runs wait for the user so results stay on screen.
#
# Globals:   CLI_MODE (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
press_enter() {
    if [ "$CLI_MODE" = "1" ]; then echo; return 0; fi
    echo ""
    read -r -p "   Press Enter to continue..." _ || true
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# confirm_action() — Ask a yes/no question, auto-confirmed with -y
#
# Reads exactly one character; Enter or anything other than y/Y means no.
# A local reply variable keeps the caller's REPLY untouched.
#
# Globals:   ASSUME_YES (read)
# Arguments: $1 — question shown at the prompt
# Returns:   0 — answered y/Y, or ASSUME_YES=1 (auto-confirmed)
#            1 — declined
# ───────────────────────────────────────────────────────────────────────────────
confirm_action() {
    if [ "$ASSUME_YES" = "1" ]; then
        info "(auto-confirmed with -y)"
        return 0
    fi
    local reply=""
    read -r -n 1 -p "   $1 (y/n): " reply || true
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

# ───────────────────────────────────────────────────────────────────────────────
# die() — Abort immediately with a logged error
#
# The failure is recorded first, so the session summary and the exit code
# both reflect the abort.
#
# Arguments: $1 — error message
#            $2 — optional exit code (default 1)
# Returns:   none — the script exits
# ───────────────────────────────────────────────────────────────────────────────
die() {
    failure "$1"
    exit "${2:-1}"
}

# ───────────────────────────────────────────────────────────────────────────────
# require_cmd() — Verify that a command exists in PATH
#
# A missing command is reported through failure() (logged and counted)
# with an optional hint, so callers can bail out with the context already
# printed.
#
# Arguments: $1 — command name
#            $2 — optional detail appended to the error message
# Returns:   0 — command found
#            1 — not found (the error is already printed)
# ───────────────────────────────────────────────────────────────────────────────
require_cmd() {   # $1=command  $2=optional detail
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi
    failure "Command '$1' not found${2:+ — $2}"
    return 1
}

# ── Dry-run mode ───────────────────────────────────────────────────────────────
# When DRY_RUN=1, the sudo wrapper below intercepts mutating commands and
# prints them instead of executing them. Read-only subcommands (test/grep)
# still run so state detection keeps working. Only the optimization flows
# (--optimize / --network / --system / --security / --time) are supported.
DRY_RUN="${DRY_RUN:-0}"

# ───────────────────────────────────────────────────────────────────────────────
# sudo() — Shadow of the sudo binary (dry-run interception)
#
# Defining sudo as a function takes precedence over the binary in PATH, so
# every sourced module goes through this wrapper without a single change.
# With DRY_RUN=1, mutating commands are quoted with %q and printed as a
# plan instead of executed; read-only subcommands (test/grep) still run so
# state detection keeps working. The plan line is written to /dev/tty
# directly so the caller's `> /dev/null` / `2>&1` redirects cannot hide
# it, with stderr as the fallback for pipes and CI; every line is also
# written to the log.
#
# Globals:   DRY_RUN (read)
# Arguments: $@ — the command line exactly as it would be passed to sudo
# Returns:   0 — in dry-run mode, after printing the plan
#            otherwise the exit status of the real sudo command
# ───────────────────────────────────────────────────────────────────────────────
sudo() {
    if [ "$DRY_RUN" != "1" ]; then
        command sudo "$@"
        return
    fi
    case "$1" in
        test|grep)
            # Read-only subcommands still run — state detection must keep working.
            # A preview must never ask for a password: use sudo only when a ticket
            # is already cached; otherwise run the command as the current user
            # (the files it inspects, e.g. /etc/sysctl.d/*.conf, are world-readable).
            if command sudo -n true 2>/dev/null; then
                command sudo "$@"
            else
                "$@"
            fi
            return $?
            ;;
    esac
    # %q keeps argument boundaries visible (e.g. "8.8.8.8 1.1.1.1" stays one argument)
    local plan
    plan=$(printf '%q ' "$@")
    plan=${plan% }
    # Real tty test: [ -w /dev/tty ] only checks permissions and passes without a tty
    if { true > /dev/tty; } 2>/dev/null; then
        echo -e "${YELLOW}   ℹ [dry-run] sudo $plan${NC}" > /dev/tty
    else
        echo -e "${YELLOW}   ℹ [dry-run] sudo $plan${NC}" >&2
    fi
    log_write "INFO" "[dry-run] sudo $plan"
    return 0
}

# ── Sudo pre-authentication ─────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# sudo_precheck() — Validate sudo access before a long flow
#
# Requesting the password up front means it is entered while the user is
# attentive, not mid-flow after a slow download. A cached ticket validates
# silently (sudo -n -v); otherwise the prompt is cancelled after the
# timeout so nothing is downloaded or changed. Skipped in dry-run mode.
#
# Globals:   DRY_RUN (read)
# Arguments: $1 — optional prompt timeout in seconds (default 600)
# Returns:   0 — sudo access validated
#            1 — authentication failed or timed out
# ───────────────────────────────────────────────────────────────────────────────
sudo_precheck() {   # $1 optional: prompt timeout in seconds (default 600)
    [ "$DRY_RUN" = "1" ] && return 0
    local secs="${1:-600}"
    # Fast path: a cached sudo ticket validates silently (no prompt at all)
    if sudo -n -v 2>/dev/null; then
        return 0
    fi
    info "sudo access is required — you have ${secs} seconds to enter your password:"
    timeout --foreground "$secs" sudo -v
    local rc=$?
    if [ "$rc" -eq 124 ]; then
        failure "sudo authentication timed out (${secs}s) — cancelled, nothing was downloaded or changed."
        return 1
    fi
    if [ "$rc" -ne 0 ]; then
        failure "sudo authentication failed — cancelled, nothing was downloaded or changed."
        return 1
    fi
    return 0
}

# ── System helpers ──────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# pkg_installed() — Check whether a deb package is installed
#
# Reads the dpkg status field and matches it in pure Bash (no grep fork);
# this is one of the most frequently called helpers (cleanup, doctor and
# update flows), so the saved processes add up.
#
# Arguments: $1 — package name
# Returns:   0 — status contains "install ok installed"
#            1 — not installed (or dpkg-query failed)
# ───────────────────────────────────────────────────────────────────────────────
pkg_installed() {
    local st
    st=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)
    [[ $st == *"install ok installed"* ]]
}

# ───────────────────────────────────────────────────────────────────────────────
# set_sysctl() — Set a sysctl key in the project's config file
#
# Updates the existing line in $SYSCTL_CONF when the key is already there,
# otherwise appends a new one; dots, ampersands and the "|" sed delimiter
# are escaped for the substitution, so unusual values cannot corrupt the
# config line. The value is only written, not applied — pair it with
# apply_sysctl to activate the setting.
#
# Globals:   SYSCTL_CONF (read)
# Arguments: $1 — sysctl key (e.g. vm.swappiness)
#            $2 — value to store
# Returns:   0 — line updated or appended
#            1 — the underlying sed/tee write failed
# ───────────────────────────────────────────────────────────────────────────────
set_sysctl() {   # $1=key  $2=value
    local key_esc value_esc
    key_esc=${1//./\\.}
    # Replacement-string escaping: backslash first, then & and the "|" delimiter
    value_esc=${2//\\/\\\\}
    value_esc=${value_esc//&/\\&}
    value_esc=${value_esc//|/\\|}
    if sudo grep -qE "^[[:space:]]*${key_esc}[[:space:]]*=" "$SYSCTL_CONF" 2>/dev/null; then
        sudo sed -i "s|^[[:space:]]*${key_esc}[[:space:]]*=.*|$1 = $value_esc|" "$SYSCTL_CONF"
    else
        printf '%s = %s\n' "$1" "$2" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# apply_sysctl() — Reload all sysctl configuration files
#
# Runs `sysctl --system` with the output suppressed; problems surface only
# through the exit status, which callers verify.
#
# Arguments: none
# Returns:   0 — every configuration file applied cleanly
#            1 — sysctl rejected a setting somewhere
# ───────────────────────────────────────────────────────────────────────────────
apply_sysctl() {
    sudo sysctl --system > /dev/null 2>&1
}

# ───────────────────────────────────────────────────────────────────────────────
# get_active_connection() — Print the active NetworkManager connection
#
# Walks `nmcli con show --active`, skips loopback, and echoes the first
# connection matching the optional type filter. Short filter names are
# translated to nmcli's type strings (wireless/wifi → 802-11-wireless,
# ethernet → 802-3-ethernet) — a direct comparison would never match.
#
# Arguments: $1 — optional connection type filter (short name accepted)
# Returns:   0 — matching connection found (its name on stdout)
#            1 — no active connection matches
# ───────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2162  # read without -r on purpose: nmcli escapes are processed
get_active_connection() {
    local name dev type want="$1"
    case "$want" in
        wireless|wifi) want="802-11-wireless" ;;
        ethernet)      want="802-3-ethernet" ;;
    esac
    while IFS=: read name dev type; do
        [ "$dev" = "lo" ] && continue
        if [ -n "$want" ] && [ "$type" != "$want" ]; then continue; fi
        echo "$name"
        return 0
    done < <(nmcli -t -f NAME,DEVICE,TYPE con show --active 2>/dev/null)
    return 1
}

# ── Name/version helpers ────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# normalize_name() — Lowercase a name and strip non-alphanumeric chars
#
# Produces a comparison key ("My App-2" → "myapp2"). Pure Bash (no tr
# forks) because it runs inside loops over every snap/flatpak/pipx//opt
# entry — each saved process is multiplied hundreds of times in the
# listing and full-removal flows.
#
# Arguments: $1 — raw name
# Returns:   0 — always; the normalized key on stdout
# ───────────────────────────────────────────────────────────────────────────────
normalize_name() {
    local s="${1,,}"
    printf '%s' "${s//[![:alnum:]]/}"
}

# ───────────────────────────────────────────────────────────────────────────────
# guess_version() — Extract a version number from a file name
#
# Pure-Bash regex over the base name ("app-1.10.4.tar.gz" → "1.10.4");
# called once per candidate file in the Downloads update scan. Prints
# nothing when the name carries no version.
#
# Arguments: $1 — file path or file name
# Returns:   0 — always; the matched version (or empty) on stdout
# ───────────────────────────────────────────────────────────────────────────────
guess_version() {
    local base
    base=${1##*/}
    base=${base%.tar.gz}; base=${base%.tgz}
    if [[ "$base" =~ ([0-9]+(\.[0-9]+)+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _ver_gt() — true when version $1 is strictly newer than version $2
#
# Version-aware comparison via sort -V (GNU coreutils, always present on
# Ubuntu). Guards against the "downgrade as update" trap: the tar.gz update
# scan uses it so an older archive in ~/Downloads is never offered as an
# update. Equal versions and empty inputs count as "not newer".
#
# Arguments: $1 — candidate version
#            $2 — current version
# Returns:   0 — $1 is strictly newer than $2
#            1 — otherwise
# ───────────────────────────────────────────────────────────────────────────────
_ver_gt() {   # $1=candidate  $2=current
    [ -n "$1" ] && [ -n "$2" ] || return 1
    [ "$1" != "$2" ] || return 1
    [ "$(printf '%s\n' "$2" "$1" | sort -V | tail -n 1)" = "$1" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# name_from_archive() — Derive an app name from an archive file name
#
# Strips the archive extension, version numbers (keeping their "v" prefix
# out of the name) and platform/packaging tokens, then keeps lowercase
# alphanumerics only — "App-v1.2.3-linux-amd64.tar.gz" becomes "app".
# Pure Bash (no sed/tr forks): it runs once per candidate archive in the
# Downloads update scan, so the saved processes multiply quickly.
#
# Arguments: $1 — path to the archive
# Returns:   0 — always; the derived name on stdout
# ───────────────────────────────────────────────────────────────────────────────
name_from_archive() {
    local base
    base=${1##*/}
    base=${base%.tar.gz}; base=${base%.tgz}
    # "app-v1.2.3" → the "v" prefix of a version must not stay in the name ("appv")
    # Loop handles several occurrences; [-_.][vV][0-9] mirrors the old sed rule
    while [[ "$base" =~ ^(.*[-_.])[vV]([0-9].*)$ ]]; do
        base="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    done
    # Version numbers with at least one dot are removed (first occurrence per pass)
    while [[ "$base" =~ ([0-9]+(\.[0-9]+)+) ]]; do
        base="${base/"${BASH_REMATCH[0]}"/}"
    done
    # Platform/packaging tokens — lowercase once, then strip the fixed set
    # (the old sed list was case-insensitive: x86[_-]64 and i[0-9]86 included)
    base=${base,,}
    local tok
    for tok in linux amd64 arm64 aarch64 x86_64 x86-64 x64 i386 i486 i586 i686 \
               riscv64 portable appimage stable release final gnu; do
        base=${base//"$tok"/}
    done
    printf '%s' "${base//[![:alnum:]]/}"
}

# ───────────────────────────────────────────────────────────────────────────────
# derive_install_root() — Derive an install root from an executable path
#
# Drops the last path component and a trailing "bin" directory
# (/opt/app/bin/tool → /opt/app). Pure Bash — no dirname/basename forks;
# the input is always an absolute path.
#
# Arguments: $1 — absolute executable path
# Returns:   0 — always; the install root on stdout
# ───────────────────────────────────────────────────────────────────────────────
derive_install_root() {
    local root="${1%/*}"
    if [ "${root##*/}" = "bin" ]; then
        root="${root%/*}"
    fi
    printf '%s' "$root"
}

# ── tar.gz application registry ─────────────────────────────────────────────────
# Line format: name|version|install_dir|exec_path|desktop_file|source_archive

# ───────────────────────────────────────────────────────────────────────────────
# registry_add() — Add or replace an entry in the tar.gz app registry
#
# Rewrites $REGISTRY_DB through a temp file: awk drops any earlier entry
# with the same name, then the new line is appended and moved into place.
# On an awk failure the temp file is discarded, leaving the original db
# untouched (never replaced by an empty file).
#
# Globals:   REGISTRY_DIR, REGISTRY_DB (read)
# Arguments: $1 — app name
#            $2 — version (may be empty)
#            $3 — install directory
#            $4 — executable path
#            $5 — desktop file path
#            $6 — source archive
# Returns:   0 — entry stored
#            1 — awk failed; the registry is unchanged
# ───────────────────────────────────────────────────────────────────────────────
registry_add() {   # $1=name $2=version $3=dir $4=exec $5=desktop $6=source
    mkdir -p "$REGISTRY_DIR"
    touch "$REGISTRY_DB"
    local tmp="$REGISTRY_DB.tmp"
    if awk -F'|' -v n="$1" '$1 != n' "$REGISTRY_DB" > "$tmp" 2>/dev/null; then
        printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$tmp"
        mv "$tmp" "$REGISTRY_DB"
    else
        rm -f "$tmp"
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# registry_remove() — Drop an entry from the tar.gz app registry
#
# Rewrites $REGISTRY_DB without the named entry via a temp file; an awk
# failure leaves the original file untouched. A no-op when the db does
# not exist yet.
#
# Globals:   REGISTRY_DB (read)
# Arguments: $1 — app name to remove
# Returns:   0 — entry removed (or nothing to remove)
#            1 — awk failed; the registry is unchanged
# ───────────────────────────────────────────────────────────────────────────────
registry_remove() {   # $1=name
    [ -f "$REGISTRY_DB" ] || return 0
    local tmp="$REGISTRY_DB.tmp"
    if awk -F'|' -v n="$1" '$1 != n' "$REGISTRY_DB" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$REGISTRY_DB"
    else
        rm -f "$tmp"
        return 1
    fi
}
