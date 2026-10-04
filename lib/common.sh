# shellcheck shell=bash
# ============================================================
#   lib/common.sh — constants, shared helpers, registry, logging
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#   This file is never executed directly; it is sourced by the main script.
# ============================================================

# ---------- Version (single source of truth for the whole project) ----------
readonly SCRIPT_VERSION="7.0"

# ---------- Constants ----------
readonly SYSCTL_CONF="/etc/sysctl.d/99-ubuntu-optimizer.conf"
readonly JOURNALD_DROPIN="/etc/systemd/journald.conf.d/99-optimizer.conf"
readonly SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/99-optimizer-timeout"
readonly POLKIT_RULE_FILE="/etc/polkit-1/rules.d/10-disable-password-timeout.rules"
readonly REGISTRY_DIR="$HOME/.local/share/ubuntu-optimizer"
readonly REGISTRY_DB="$REGISTRY_DIR/apps.db"

# ---------- Logging ----------
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

# ---------- Colors ----------
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

# ============================================================
#   Logging system
# ============================================================

# Strip ANSI color codes from text (no sed fork)
_strip_ansi() {
    printf '%s' "${1//$'\e'\[*([0-9;])m/}"
}

# Rotate the log file when it exceeds the size limit
_log_rotate() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.old"
    fi
    return 0
}

# Append one line to the log — $1=level  $2=message
# Fully built-in Bash: no date or sed fork
log_write() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%(%Y-%m-%d %H:%M:%S)T] %-8s %s\n' -1 "$1" "${2//$'\e'\[*([0-9;])m/}" >> "$LOG_FILE"
}

# Start a session — $1=mode (cli/interactive), rest=arguments
log_session_start() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    _log_rotate
    local mode="$1"
    shift
    local extra=""
    [ $# -gt 0 ] && extra=" | args: $*"
    log_write "SESSION" "════ session start ($mode)$extra ════"
}

# End the session and log the counter summary
log_session_end() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    log_write "SESSION" "session summary: ok=$LOG_OK_COUNT  errors=$LOG_FAIL_COUNT  warnings=$LOG_WARN_COUNT"
    log_write "SESSION" "════ session end ════"
}

# Print this run's counter summary to the terminal
print_session_summary() {
    echo ""
    echo -e "${BOLD}── Session summary ──${NC}"
    echo -e "   ✓ OK: $LOG_OK_COUNT     ✗ Errors: $LOG_FAIL_COUNT     ⚠ Warnings: $LOG_WARN_COUNT"
    if [ "$LOG_ENABLED" = "1" ]; then
        echo -e "   ℹ Full log: $LOG_FILE"
    fi
    return 0
}

# Show the last log lines (interactive menu)
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

# ---------- Output (terminal + simultaneous logging) ----------
success() {
    echo -e "${GREEN}   ✓ $1${NC}"
    LOG_OK_COUNT=$((LOG_OK_COUNT + 1))
    log_write "OK" "$1"
}

failure() {
    echo -e "${RED}   ✗ $1${NC}"
    LOG_FAIL_COUNT=$((LOG_FAIL_COUNT + 1))
    log_write "ERROR" "$1"
}

info() {
    echo -e "${YELLOW}   ℹ $1${NC}"
    log_write "INFO" "$1"
}

warn() {
    echo -e "${MAGENTA}   ⚠ $1${NC}"
    LOG_WARN_COUNT=$((LOG_WARN_COUNT + 1))
    log_write "WARN" "$1"
}

header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}   $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    log_write "SECTION" "$1"
}

press_enter() {
    if [ "$CLI_MODE" = "1" ]; then echo; return 0; fi
    echo ""
    read -r -p "   Press Enter to continue..." _ || true
    return 0
}

# Ask a yes/no question — auto-confirmed in -y mode
# Uses a local variable so the caller's REPLY is not overwritten
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

# Abort immediately with a logged error — $1=message  $2=exit code (default 1)
die() {
    failure "$1"
    exit "${2:-1}"
}

# Check whether a command exists in PATH — logs an error and returns 1 if missing
require_cmd() {   # $1=command  $2=optional detail
    if command -v "$1" > /dev/null 2>&1; then
        return 0
    fi
    failure "Command '$1' not found${2:+ — $2}"
    return 1
}

# ---------- Dry-run mode ----------
# When DRY_RUN=1, the sudo wrapper below intercepts mutating commands and
# prints them instead of executing them. Read-only subcommands (test/grep)
# still run so state detection keeps working. Only the optimization flows
# (--optimize / --network / --system / --security / --time) are supported.
DRY_RUN="${DRY_RUN:-0}"

# Shadow of the sudo binary — a function takes precedence over PATH, so all
# sourced modules go through this wrapper without a single change.
# The plan line goes to the terminal directly (/dev/tty) so the caller's
# `> /dev/null` / `2>&1` redirects cannot hide it; stderr is the fallback
# for pipes and CI. Every line is also written to the log.
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

# ---------- Sudo pre-authentication ----------
# Validate sudo access BEFORE a long flow (download + install), so the
# password is requested while the user is attentive — not mid-flow after a
# slow download. A cached ticket is used silently (sudo -n); otherwise the
# prompt is cancelled after $1 seconds (default 600 = 10 minutes).
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

# ---------- System helpers ----------

# Is the deb package installed?
# The status string is matched in Bash (no grep fork) — pkg_installed is one
# of the most frequently called helpers (cleanup, doctor, update flows).
pkg_installed() {
    local st
    st=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)
    [[ $st == *"install ok installed"* ]]
}

# Set/update a sysctl parameter in the script's dedicated config file
set_sysctl() {   # $1=key  $2=value
    local key_esc value_esc
    key_esc=${1//./\\.}
    value_esc=${2//&/\\&}
    if sudo grep -qE "^[[:space:]]*${key_esc}[[:space:]]*=" "$SYSCTL_CONF" 2>/dev/null; then
        sudo sed -i "s|^[[:space:]]*${key_esc}[[:space:]]*=.*|$1 = $value_esc|" "$SYSCTL_CONF"
    else
        printf '%s = %s\n' "$1" "$2" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    fi
}

# Apply all sysctl parameters
apply_sysctl() {
    sudo sysctl --system > /dev/null 2>&1
}

# Name of the active NetworkManager connection — $1: optional connection type filter
# Short names are accepted: wireless/wifi → 802-11-wireless, ethernet → 802-3-ethernet
# (nmcli's type string differs from the short name; a direct comparison would never match)
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

# ---------- Name/version helpers ----------

# Normalize a name for comparison (strip spaces/dashes/uppercase)
# Pure Bash (no tr forks): this helper is called inside loops over every
# snap/flatpak/pipx//opt entry, so each saved process is multiplied hundreds
# of times in the listing and full-removal flows.
normalize_name() {
    local s="${1,,}"
    printf '%s' "${s//[![:alnum:]]/}"
}

# Extract a version from a file name (e.g. 1.10.4) — pure Bash regex, no fork
# (called once per candidate file in the Downloads update scan)
guess_version() {
    local base
    base=${1##*/}
    base=${base%.tar.gz}; base=${base%.tgz}
    if [[ "$base" =~ ([0-9]+(\.[0-9]+)+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# Extract the application name from an archive file name (strip version/platform)
name_from_archive() {
    local base
    base=$(basename "$1")
    base=${base%.tar.gz}; base=${base%.tgz}
    # "app-v1.2.3" → the "v" prefix of a version must not stay in the name ("appv")
    base=$(printf '%s' "$base" | sed -E 's/[-_.][vV]([0-9])/-\1/g')
    base=$(printf '%s' "$base" | sed -E 's/[0-9]+(\.[0-9]+)+//g')
    base=$(printf '%s' "$base" | sed -E 's/(linux|amd64|arm64|aarch64|x86[_-]64|x64|i[0-9]86|riscv64|portable|appimage|stable|release|final|gnu)//gi')
    printf '%s' "$base" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

# Derive the install root from an executable path (e.g. /opt/app/bin/x → /opt/app)
# Pure Bash (no dirname/basename forks); input is always an absolute path
derive_install_root() {
    local root="${1%/*}"
    if [ "${root##*/}" = "bin" ]; then
        root="${root%/*}"
    fi
    printf '%s' "$root"
}

# ---------- tar.gz application registry ----------
# Line format: name|version|install_dir|exec_path|desktop_file|source_archive
# The db is rewritten through a temp file; on an awk failure the original
# file is left untouched (never replaced by an empty file).

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
