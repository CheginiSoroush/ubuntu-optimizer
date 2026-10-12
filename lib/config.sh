# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/config.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Optional user configuration file: ~/.config/uo/config.conf (respects
#  $XDG_CONFIG_HOME). Lets recurring setups (cron jobs, shared machines)
#  persist their preferences — ASSUME_YES, NO_COLOR, NO_LOG, DRY_RUN and
#  DNS_SERVERS — without repeating flags on every invocation.
#
#  Parsing is deliberately paranoid: the file is NEVER sourced or eval'd.
#  Only KEY=VALUE lines are accepted (blank lines and '#' comments allowed,
#  optional matching quotes stripped), every value is validated against its
#  key, unknown keys and malformed lines are reported and skipped. Precedence
#  is documented and enforced:
#      built-in defaults < config file < environment (UO_DNS_SERVERS)
#      < explicit CLI flags (-y, --dry-run, --no-color, --no-log)
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uo"
CONFIG_FILE="$CONFIG_DIR/config.conf"

CONFIG_LOADED_PATH=""    # path of the config actually applied ("" = none)
CONFIG_WAS_FOUND=0       # 1 when the applied file existed
declare -A CONFIG_SOURCES=()   # key → "default" | "config" | "cli" | "env"

# ───────────────────────────────────────────────────────────────────────────────
# uo_config_example() — print an annotated, safe-to-copy template config
#
# Every line is commented out, so redirecting the output straight onto an
# existing config file cannot change behavior until the user edits it.
#
# Arguments: none
# Returns:   0 — always; the template goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
uo_config_example() {
    cat << 'EOF'
# Ubuntu Optimizer & Fixer — user configuration
# Location: ~/.config/uo/config.conf   (respects $XDG_CONFIG_HOME)
# Format:   KEY=VALUE, one per line; blank lines and '#' comments allowed;
#           values may be wrapped in single or double quotes.
# Precedence: built-in defaults < this file < environment (UO_DNS_SERVERS)
#             < explicit CLI flags (-y, --dry-run, --no-color, --no-log).
# Use a custom file for one run:   uo --config /path/to/config.conf …
# Ignore every config for one run: uo --no-config …
# Inspect what is in effect:       uo --config-show

# Auto-confirm every question (same as passing -y on every run)
#ASSUME_YES=0

# Disable colored output
#NO_COLOR=0

# Do not write log files for runs
#NO_LOG=0

# Always run in preview mode — commands are printed, nothing is changed
# (combine with ASSUME_YES=1 for a fully non-interactive dry-run cron)
#DRY_RUN=0

# Custom DNS servers for --network/--optimize (space-separated IPv4)
# The UO_DNS_SERVERS environment variable wins over this key.
#DNS_SERVERS="1.1.1.1 9.9.9.9"
EOF
}

# ───────────────────────────────────────────────────────────────────────────────
# uo_config_value_is_valid() — validate a value against its known key
#
# Single source of truth for every key's accepted format. Booleans must be
# exactly 0 or 1; DNS_SERVERS mirrors the strict IPv4+space rule that
# lib/network.sh enforces before nmcli ever sees the value.
#
# Arguments: $1 — key, $2 — value
# Returns:   0 — valid; 1 — invalid for this key
# ───────────────────────────────────────────────────────────────────────────────
uo_config_value_is_valid() {
    local key="$1" value="$2"
    case "$key" in
        ASSUME_YES|NO_COLOR|NO_LOG|DRY_RUN)
            [[ "$value" == "0" || "$value" == "1" ]] ;;
        DNS_SERVERS)
            [ -n "$value" ] && [[ "$value" =~ ^[0-9.[:space:]]+$ ]] ;;
        *) return 1 ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# uo_config_apply_key() — apply one validated key honoring the precedence
#
# An explicit CLI flag always beats the config file (the CLI_* markers are
# set by the main parser). The DNS_SERVERS key loses to an already exported
# UO_DNS_SERVERS environment variable, mirroring the documented precedence.
# Each decision is recorded in CONFIG_SOURCES for `--config-show`.
#
# Arguments: $1 — key, $2 — validated value
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
uo_config_apply_key() {
    local key="$1" value="$2"
    case "$key" in
        ASSUME_YES)
            if [ "${CLI_YES:-0}" = "1" ]; then
                CONFIG_SOURCES[$key]="cli"
            else
                ASSUME_YES="$value"; CONFIG_SOURCES[$key]="config"
            fi
            ;;
        NO_COLOR)
            if [ "${CLI_NO_COLOR:-0}" = "1" ]; then
                CONFIG_SOURCES[$key]="cli"
            elif [ "$value" = "1" ]; then
                RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''
                CONFIG_SOURCES[$key]="config"
            else
                CONFIG_SOURCES[$key]="config"
            fi
            ;;
        NO_LOG)
            if [ "${CLI_NO_LOG:-0}" = "1" ]; then
                CONFIG_SOURCES[$key]="cli"
            else
                LOG_ENABLED=0; CONFIG_SOURCES[$key]="config"
            fi
            ;;
        DRY_RUN)
            if [ "${CLI_DRY_RUN:-0}" = "1" ]; then
                CONFIG_SOURCES[$key]="cli"
            else
                DRY_RUN="$value"; CONFIG_SOURCES[$key]="config"
            fi
            ;;
        DNS_SERVERS)
            if [ -n "${UO_DNS_SERVERS:-}" ]; then
                CONFIG_SOURCES[$key]="env"
            else
                UO_DNS_SERVERS="$value"; CONFIG_SOURCES[$key]="config"
            fi
            ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# uo_config_load() — locate, parse and apply the configuration file
#
# Resolution: --config FILE (already validated by the parser) wins over the
# default path; --no-config skips loading entirely. A missing default file
# is silently fine (the config is optional), a missing --config file cannot
# reach this function (the parser rejects it). Every malformed line reports
# the line number and is skipped — one bad line never aborts the run.
#
# Globals:   CONFIG_FILE, CONFIG_PATH_OVERRIDE, NO_CONFIG (read);
#            CONFIG_LOADED_PATH, CONFIG_WAS_FOUND, CONFIG_SOURCES (written)
# Arguments: none
# Returns:   0 — always (problems are reported, not fatal)
# ───────────────────────────────────────────────────────────────────────────────
uo_config_load() {
    # Seed every tracked key with its documented default source
    local k
    for k in ASSUME_YES NO_COLOR NO_LOG DRY_RUN DNS_SERVERS; do
        CONFIG_SOURCES[$k]="default"
    done
    # Explicit CLI preference flags are recorded even when no config file is
    # loaded (or loading is disabled) — --config-show must stay truthful
    [ "${CLI_YES:-0}" = "1" ]      && CONFIG_SOURCES[ASSUME_YES]="cli"
    [ "${CLI_NO_COLOR:-0}" = "1" ] && CONFIG_SOURCES[NO_COLOR]="cli"
    [ "${CLI_NO_LOG:-0}" = "1" ]   && CONFIG_SOURCES[NO_LOG]="cli"
    [ "${CLI_DRY_RUN:-0}" = "1" ]  && CONFIG_SOURCES[DRY_RUN]="cli"
    # An exported UO_DNS_SERVERS is the documented env-level override
    [ -n "${UO_DNS_SERVERS:-}" ]   && CONFIG_SOURCES[DNS_SERVERS]="env"

    [ "${NO_CONFIG:-0}" = "1" ] && return 0

    local path="${CONFIG_PATH_OVERRIDE:-$CONFIG_FILE}"
    if [ ! -f "$path" ]; then
        # A missing default config is normal; a missing --config file was
        # already rejected by the parser, so this only silences the default
        return 0
    fi
    if [ ! -r "$path" ]; then
        warn "Config file not readable: $path — ignoring it."
        return 0
    fi

    CONFIG_LOADED_PATH="$path"
    CONFIG_WAS_FOUND=1

    local line_no=0 line key value
    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        # Trim surrounding whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        # Skip blanks and full-line comments
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        # Only KEY=VALUE survives — anything else is reported and skipped
        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            warn "config: skipping line $line_no (not KEY=VALUE): $line"
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"
        # Strip one pair of matching outer quotes
        if [ "${#value}" -ge 2 ]; then
            if [[ "$value" == '"'*'"' || "$value" == "'"*"'" ]]; then
                value="${value:1:${#value}-2}"
            fi
        fi
        if ! uo_config_value_is_valid "$key" "$value"; then
            warn "config: line $line_no — invalid value for $key: $value"
            continue
        fi
        uo_config_apply_key "$key" "$value"
    done < "$path"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# uo_config_show() — print the effective configuration and its sources
#
# Read-only introspection for `uo --config-show`: every tracked key with its
# effective value and where that value came from (default / config / cli /
# env). The config line states which file was applied — or why none was.
#
# Globals:   CONFIG_SOURCES, CONFIG_LOADED_PATH, CONFIG_WAS_FOUND,
#            NO_CONFIG, UO_DNS_SERVERS (read)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
uo_config_show() {
    local default_dns="8.8.8.8 1.1.1.1"
    printf 'Ubuntu Optimizer & Fixer - v%s — effective configuration\n\n' "$SCRIPT_VERSION"
    if [ "${NO_CONFIG:-0}" = "1" ]; then
        echo "Config file: disabled with --no-config — defaults in use"
    elif [ "$CONFIG_WAS_FOUND" = "1" ]; then
        echo "Config file: $CONFIG_LOADED_PATH (applied)"
    else
        echo "Config file: $CONFIG_FILE (not found — defaults in use)"
    fi
    echo ""
    local k eff_no_color=0 eff_no_log=0
    # Effective values are derived from the real state, not from variables
    # that may not exist: colors were cleared when disabled, logging is
    # tracked by LOG_ENABLED (NO_LOG is its logical inverse).
    [ -z "$RED" ] && eff_no_color=1
    [ "$LOG_ENABLED" = "0" ] && eff_no_log=1
    for k in ASSUME_YES NO_COLOR NO_LOG DRY_RUN DNS_SERVERS; do
        case "$k" in
            DNS_SERVERS)
                printf '%s=%s (%s)\n' "$k" "${UO_DNS_SERVERS:-$default_dns}" "${CONFIG_SOURCES[$k]}"
                ;;
            NO_COLOR)
                printf '%s=%s (%s)\n' "$k" "$eff_no_color" "${CONFIG_SOURCES[$k]}"
                ;;
            NO_LOG)
                printf '%s=%s (%s)\n' "$k" "$eff_no_log" "${CONFIG_SOURCES[$k]}"
                ;;
            *)
                printf '%s=%s (%s)\n' "$k" "${!k}" "${CONFIG_SOURCES[$k]}"
                ;;
        esac
    done
    echo ""
    info "Template: uo --config-example · precedence: defaults < config < env < CLI flags"
    return 0
}
