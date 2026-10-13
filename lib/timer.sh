# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/timer.sh
# ───────────────────────────────────────────────────────────────────────────────
#  A systemd timer that keeps the system updated on a schedule — without any
#  cron syntax and with journald as the log store. Two scopes and two modes:
#
#    Scope (who owns the timer):
#      user   (default)  units in ~/.config/systemd/user — no root needed;
#                        enable-linger is suggested so the timer also fires
#                        while nobody is logged in.
#      system            units in /etc/systemd/system — root via sudo, the
#                        classical place for headless servers.
#
#    Mode (what the scheduled run does):
#      apply  (default)  ExecStart = uo --update -y --no-color
#                        applies pending updates unattended and logs to the
#                        journal — the "keeps itself up to date" promise.
#      monitor           ExecStart = uo --timer-tick --no-color
#                        (--timer-notify-only) — mutates NOTHING: appends a
#                        read-only JSON report snapshot to
#                        ~/.local/share/ubuntu-optimizer/report-log.jsonl
#                        (the same JSONL series the dashboard Trends tab
#                        charts) and sends a desktop notification only when
#                        the system genuinely needs attention.
#
#  Safety:
#    • The schedule period is a strict whitelist (hourly/daily/weekly/monthly)
#      mapped to systemd calendar keywords — user input never reaches the
#      unit files, so there is nothing to inject.
#    • Unit files are rendered from static templates; the only variable
#      content is this script's own resolved path.
#    • Preview (--timer-preview) works everywhere — including machines and
#      containers without systemd — and prints exactly what would be
#      installed, byte for byte.
#    • Persistent=true lets systemd catch up a missed run after downtime;
#      RandomizedDelaySec spreads the load on mirrors.
#
#  Control:
#    --timer-install [PERIOD]   install + enable (default period: weekly)
#    --timer-remove             disable + remove the units
#    --timer-status             installed? enabled? next runs? last result?
#    --timer-log [N]            last N journal lines of the run (default 50)
#    --timer-preview [PERIOD]   print the unit files that would be installed
#    --timer-tick               internal: one monitor tick (report snapshot)
#    --timer-system             (modifier) system scope instead of user
#    --timer-notify-only        (modifier) monitor mode instead of apply
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ── Constants & run state ──────────────────────────────────────────────────────
readonly TIMER_UNIT_NAME="uo-update"
TIMER_DATA_DIR="${REGISTRY_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-optimizer}"
TIMER_REPORT_LOG="$TIMER_DATA_DIR/report-log.jsonl"
TIMER_PERIOD=""      # resolved at install/preview time (default: weekly)
TIMER_SCOPE="user"   # user | system   (--timer-system)
TIMER_NOTIFY=0       # 0=apply mode, 1=monitor mode (--timer-notify-only)
TIMER_LOG_LINES=50   # --timer-log [N]

# ───────────────────────────────────────────────────────────────────────────────
# timer_period_is_valid() — strict schedule whitelist
#
# The period becomes the systemd OnCalendar value. A whitelist mapping keeps
# every unit file template static — arbitrary strings can never be embedded.
#
# Arguments: $1 — candidate period
# Returns:   0 — one of hourly | daily | weekly | monthly
#            1 — anything else
# ───────────────────────────────────────────────────────────────────────────────
timer_period_is_valid() {
    case "$1" in
        hourly|daily|weekly|monthly) return 0 ;;
        *)                           return 1 ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_calendar_for() — map a validated period to its calendar keyword
#
# Arguments: $1 — validated period
# Returns:   0 — the OnCalendar value is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
timer_calendar_for() {
    printf '%s' "$1"
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_resolve_period() — fill TIMER_PERIOD with the default if unset
#
# Both --timer-install and --timer-preview accept an optional period; when
# none was given on the command line, weekly is the sane default (weekly is
# frequent enough to matter, rare enough to stay invisible).
#
# Globals:   TIMER_PERIOD (read/write)
# Returns:   0 — TIMER_PERIOD is valid afterwards
#            1 — the configured period is not whitelisted (defensive; the
#                CLI parser already rejects invalid values)
# ───────────────────────────────────────────────────────────────────────────────
timer_resolve_period() {
    [ -z "$TIMER_PERIOD" ] && TIMER_PERIOD="weekly"
    timer_period_is_valid "$TIMER_PERIOD"
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_unit_dir() — where the units live for the active scope
#
# Globals:   TIMER_SCOPE (read)
# Returns:   0 — the directory is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
timer_unit_dir() {
    if [ "$TIMER_SCOPE" = "system" ]; then
        printf '%s' "/etc/systemd/system"
    else
        printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_script_path() — absolute path of the entry script
#
# SCRIPT_DIR is resolved by ubuntu-optimizer.sh itself (readlink -f), so
# relative installs and symlinked launches both land in the unit file as
# absolute paths. Standalone sourcing (tests) falls back to $PWD.
#
# Returns:   0 — the path is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
timer_script_path() {
    printf '%s' "${SCRIPT_DIR:-$PWD}/ubuntu-optimizer.sh"
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_render_service() — print the uo-update.service unit
#
# A pure text function: no files are touched, no commands executed. That is
# what makes --timer-preview byte-identical to the real install and lets the
# dashboard render the true unit content.
#
# Globals:   TIMER_SCOPE, TIMER_NOTIFY (read), SCRIPT_DIR (read, optional)
# Returns:   0 — the unit file content is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
timer_render_service() {
    local script
    script=$(timer_script_path)
    if [ "$TIMER_NOTIFY" = "1" ]; then
        local exec_line="$script --timer-tick --no-color"
        local desc="Ubuntu Optimizer — scheduled monitor tick (read-only report snapshot)"
    else
        local exec_line="$script --update -y --no-color"
        local desc="Ubuntu Optimizer — scheduled update run"
    fi
    cat << EOF
[Unit]
Description=$desc
Documentation=https://github.com/CheginiSoroush/ubuntu-optimizer
EOF
    if [ "$TIMER_SCOPE" = "system" ]; then
        echo "After=network-online.target"
        echo "Wants=network-online.target"
    fi
    cat << EOF

[Service]
Type=oneshot
ExecStart=$exec_line
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$TIMER_UNIT_NAME
EOF
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_render_timer() — print the uo-update.timer unit
#
# Persistent=true replays a missed run after downtime (laptops that were
# suspended at the scheduled moment); RandomizedDelaySec spreads a fleet of
# machines over 15 minutes so mirrors are not hammered at the same second.
#
# Globals:   TIMER_PERIOD, TIMER_NOTIFY (read)
# Returns:   0 — the unit file content is printed to stdout
# ───────────────────────────────────────────────────────────────────────────────
timer_render_timer() {
    local mode="apply updates"
    [ "$TIMER_NOTIFY" = "1" ] && mode="monitor (report snapshots)"
    cat << EOF
[Unit]
Description=Ubuntu Optimizer — $mode schedule ($TIMER_PERIOD)

[Timer]
OnCalendar=$(timer_calendar_for "$TIMER_PERIOD")
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_systemd_available() — is systemd actually reachable for this scope?
#
# Checking for running systemd by its runtime directory is reliable even in
# minimal containers where systemctl exists but only answers "System has not
# been booted with systemd".
#
# Globals:   TIMER_SCOPE (read)
# Returns:   0 — systemctl exists and the scope's runtime dir is present
#            1 — systemd cannot manage units for this scope
# ───────────────────────────────────────────────────────────────────────────────
timer_systemd_available() {
    command -v systemctl >/dev/null 2>&1 || return 1
    if [ "$TIMER_SCOPE" = "system" ]; then
        [ -d "/run/systemd/system" ]
    else
        [ -d "/run/user/$(id -u)/systemd" ]
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_installed() — do both units exist for the active scope?
#
# Globals:   TIMER_SCOPE (read)
# Returns:   0 — both unit files are present
#            1 — not (fully) installed
# ───────────────────────────────────────────────────────────────────────────────
timer_installed() {
    local dir
    dir=$(timer_unit_dir)
    [ -f "$dir/$TIMER_UNIT_NAME.service" ] && [ -f "$dir/$TIMER_UNIT_NAME.timer" ]
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_place_file() — move a rendered unit into place (sudo for system scope)
#
# The unit is fully rendered into a temp file in user space first; placing it
# is a single mv (user scope) or a single sudo mv (system scope). A half
# written unit can therefore never exist in the unit directory.
#
# Arguments: $1 — temp file with the rendered content
#            $2 — destination path
# Returns:   0 — placed
#            1 — the move failed
# ───────────────────────────────────────────────────────────────────────────────
timer_place_file() {
    if [ "$TIMER_SCOPE" = "system" ]; then
        sudo mv -f "$1" "$2" 2>/dev/null
    else
        mv -f "$1" "$2" 2>/dev/null
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_reload_and_enable() — daemon-reload + enable --now for the scope
#
# Globals:   TIMER_SCOPE (read)
# Returns:   0 — both systemctl calls succeeded
#            1 — a call failed (error already reported by the caller)
# ───────────────────────────────────────────────────────────────────────────────
timer_reload_and_enable() {
    if [ "$TIMER_SCOPE" = "system" ]; then
        sudo systemctl daemon-reload 2>/dev/null || return 1
        sudo systemctl enable --now "$TIMER_UNIT_NAME.timer" 2>/dev/null || return 1
    else
        systemctl --user daemon-reload 2>/dev/null || return 1
        systemctl --user enable --now "$TIMER_UNIT_NAME.timer" 2>/dev/null || return 1
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_cli_install() — CLI action behind --timer-install [PERIOD]
#
# Validates the period, checks systemd, renders both units into temp files
# and places them atomically, then daemon-reloads and enables the timer. An
# existing installation is overwritten only after confirmation (skipped with
# -y) — re-installing is the supported way to change the period or mode.
#
# Globals:   TIMER_PERIOD, TIMER_SCOPE, TIMER_NOTIFY, ASSUME_YES (read)
# Returns:   0 — installed and enabled
#            1 — validation, systemd, or placement failure
# ───────────────────────────────────────────────────────────────────────────────
timer_cli_install() {
    if ! timer_resolve_period; then
        failure "Invalid timer period: $TIMER_PERIOD"
        info "Valid periods: hourly · daily · weekly · monthly"
        return 1
    fi
    header "Install the Update Timer ($TIMER_PERIOD · $TIMER_SCOPE scope)"
    if ! timer_systemd_available; then
        failure "systemd is not available for the $TIMER_SCOPE scope."
        info "A user timer needs a running user session: /run/user/\$(id -u)/systemd"
        info "Preview the unit files anywhere (no systemd needed): uo --timer-preview $TIMER_PERIOD"
        return 1
    fi
    local dir
    dir=$(timer_unit_dir)
    if timer_installed && [ "$ASSUME_YES" != "1" ]; then
        confirm_action "A $TIMER_UNIT_NAME timer already exists. Overwrite its unit files?" || {
            info "Aborted — the existing timer is untouched."
            return 0
        }
    fi
    if [ "$TIMER_SCOPE" = "system" ] && [ "$DRY_RUN" != "1" ]; then
        sudo_precheck || return 1
    fi
    if ! mkdir -p "$dir" 2>/dev/null; then
        failure "Cannot create the unit directory: $dir"
        return 1
    fi
    local tmp
    tmp=$(mktemp) || { failure "Cannot create a temp file."; return 1; }
    timer_render_service > "$tmp" || { rm -f "$tmp"; failure "Rendering failed."; return 1; }
    if ! timer_place_file "$tmp" "$dir/$TIMER_UNIT_NAME.service"; then
        rm -f "$tmp"; failure "Cannot write: $dir/$TIMER_UNIT_NAME.service"
        return 1
    fi
    tmp=$(mktemp) || { failure "Cannot create a temp file."; return 1; }
    timer_render_timer > "$tmp" || { rm -f "$tmp"; failure "Rendering failed."; return 1; }
    if ! timer_place_file "$tmp" "$dir/$TIMER_UNIT_NAME.timer"; then
        rm -f "$tmp"; failure "Cannot write: $dir/$TIMER_UNIT_NAME.timer"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "DRY RUN — units rendered, nothing enabled."
        info "$dir/$TIMER_UNIT_NAME.service"
        info "$dir/$TIMER_UNIT_NAME.timer"
        return 0
    fi
    if ! timer_reload_and_enable; then
        failure "systemctl failed — units are written but not enabled."
        info "Retry manually: systemctl $([ "$TIMER_SCOPE" = "user" ] && echo --user) daemon-reload"
        info "Then:        systemctl $([ "$TIMER_SCOPE" = "user" ] && echo --user) enable --now $TIMER_UNIT_NAME.timer"
        return 1
    fi
    success "Timer installed and enabled — schedule: $TIMER_PERIOD."
    if [ "$TIMER_NOTIFY" = "1" ]; then
        info "Mode: monitor — read-only report snapshots, no changes are applied."
        info "Series: $TIMER_REPORT_LOG (chart it in the dashboard's Trends tab)"
    else
        info "Mode: apply — 'uo --update -y --no-color' runs unattended on schedule."
    fi
    if [ "$TIMER_SCOPE" = "user" ]; then
        if command -v loginctl >/dev/null 2>&1 && \
           [ "$(loginctl show-user "$(id -un)" --property=Linger 2>/dev/null)" = "Linger=no" ]; then
            info "Hint: sudo loginctl enable-linger $(id -un) — lets the timer also run while you are logged out."
        fi
        info "Status: systemctl --user list-timers $TIMER_UNIT_NAME.timer"
        info "Logs:   journalctl --user-unit=$TIMER_UNIT_NAME.service"
    else
        info "Status: systemctl list-timers $TIMER_UNIT_NAME.timer"
        info "Logs:   journalctl -u $TIMER_UNIT_NAME.service"
    fi
    info "Remove: uo --timer-remove"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_cli_remove() — CLI action behind --timer-remove
#
# Disables the timer first (so no run fires between the two steps), removes
# both unit files and reloads the daemon. A missing installation is a clean
# no-op, not an error.
#
# Globals:   TIMER_SCOPE, TIMER_UNIT_NAME, ASSUME_YES (read)
# Returns:   0 — removed (or nothing to remove)
#            1 — a systemctl call failed while units still exist
# ───────────────────────────────────────────────────────────────────────────────
timer_cli_remove() {
    header "Remove the Update Timer"
    if ! timer_installed; then
        info "No $TIMER_UNIT_NAME timer installed for the $TIMER_SCOPE scope — nothing to remove."
        return 0
    fi
    if [ "$ASSUME_YES" != "1" ]; then
        confirm_action "Disable and remove the $TIMER_UNIT_NAME timer?" || {
            info "Aborted — the timer stays installed."
            return 0
        }
    fi
    local rc=0
    if [ "$TIMER_SCOPE" = "system" ]; then
        sudo systemctl disable --now "$TIMER_UNIT_NAME.timer" >/dev/null 2>&1 || rc=1
    else
        systemctl --user disable --now "$TIMER_UNIT_NAME.timer" >/dev/null 2>&1 || rc=1
    fi
    local dir
    dir=$(timer_unit_dir)
    if [ "$TIMER_SCOPE" = "system" ]; then
        sudo rm -f "$dir/$TIMER_UNIT_NAME.service" "$dir/$TIMER_UNIT_NAME.timer" 2>/dev/null
        sudo systemctl daemon-reload 2>/dev/null
    else
        rm -f "$dir/$TIMER_UNIT_NAME.service" "$dir/$TIMER_UNIT_NAME.timer" 2>/dev/null
        systemctl --user daemon-reload 2>/dev/null
    fi
    if [ "$rc" -eq 1 ]; then
        failure "systemctl disable failed — the timer may still be enabled."
        info "Check: systemctl $([ "$TIMER_SCOPE" = "user" ] && echo --user) list-timers $TIMER_UNIT_NAME.timer"
        return 1
    fi
    success "Timer removed — no scheduled runs remain."
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_cli_status() — CLI action behind --timer-status
#
# Read-only introspection: unit file presence, enablement, the systemd view
# of upcoming runs and the last journal verdict. Works (with reduced
# information) even when systemd is not reachable.
#
# Globals:   TIMER_SCOPE, TIMER_UNIT_NAME (read)
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
timer_cli_status() {
    header "Update Timer Status ($TIMER_SCOPE scope)"
    local dir
    dir=$(timer_unit_dir)
    if ! timer_installed; then
        info "Not installed — no $TIMER_UNIT_NAME units in $dir."
        info "Install: uo --timer-install weekly"
        return 0
    fi
    success "Unit files present: $dir/$TIMER_UNIT_NAME.{service,timer}"
    if ! timer_systemd_available; then
        warn "systemd is not reachable right now — enablement and next runs unknown."
        return 0
    fi
    local enabled
    if [ "$TIMER_SCOPE" = "system" ]; then
        enabled=$(systemctl is-enabled "$TIMER_UNIT_NAME.timer" 2>/dev/null)
    else
        enabled=$(systemctl --user is-enabled "$TIMER_UNIT_NAME.timer" 2>/dev/null)
    fi
    if [ "$enabled" = "enabled" ]; then
        success "Enabled: yes — the schedule is active."
    else
        warn "Enabled: ${enabled:-unknown} — no runs will fire until it is enabled."
    fi
    echo ""
    if [ "$TIMER_SCOPE" = "system" ]; then
        systemctl list-timers "$TIMER_UNIT_NAME.timer" --no-pager 2>/dev/null || true
    else
        systemctl --user list-timers "$TIMER_UNIT_NAME.timer" --no-pager 2>/dev/null || true
    fi
    echo ""
    local last
    if [ "$TIMER_SCOPE" = "system" ]; then
        last=$(journalctl -u "$TIMER_UNIT_NAME.service" -n 1 --no-pager -o cat 2>/dev/null)
    else
        last=$(journalctl --user-unit="$TIMER_UNIT_NAME.service" -n 1 --no-pager -o cat 2>/dev/null)
    fi
    if [ -n "$last" ]; then
        info "Last run: $last"
    else
        info "No run recorded yet — the journal entry appears after the first scheduled tick."
    fi
    info "Full log: uo --timer-log"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_cli_log() — CLI action behind --timer-log [N]
#
# Prints the last TIMER_LOG_LINES journal lines of the scheduled runs.
#
# Globals:   TIMER_SCOPE, TIMER_UNIT_NAME, TIMER_LOG_LINES (read)
# Returns:   0 — lines printed (or nothing logged yet)
#            1 — journalctl is unavailable
# ───────────────────────────────────────────────────────────────────────────────
timer_cli_log() {
    header "Timer Run Log (last $TIMER_LOG_LINES lines)"
    if ! command -v journalctl >/dev/null 2>&1; then
        failure "journalctl is not available on this system."
        return 1
    fi
    local lines
    if [ "$TIMER_SCOPE" = "system" ]; then
        lines=$(journalctl -u "$TIMER_UNIT_NAME.service" -n "$TIMER_LOG_LINES" --no-pager 2>/dev/null)
    else
        lines=$(journalctl --user-unit="$TIMER_UNIT_NAME.service" -n "$TIMER_LOG_LINES" --no-pager 2>/dev/null)
    fi
    if [ -z "$lines" ]; then
        info "No journal entries yet — nothing has run under this timer."
        info "The first entry appears after the timer fires (or after: systemctl $([ "$TIMER_SCOPE" = "user" ] && echo --user) start $TIMER_UNIT_NAME.service)."
        return 0
    fi
    printf '%s\n' "$lines"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_cli_preview() — CLI action behind --timer-preview [PERIOD]
#
# Prints exactly the unit files an install would write — separators make the
# two documents greppable and the dashboard can render them directly. No
# systemd, no root, no confirmation: rendering is pure text.
#
# Globals:   TIMER_PERIOD, TIMER_SCOPE, TIMER_NOTIFY (read)
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
timer_cli_preview() {
    if ! timer_resolve_period; then
        failure "Invalid timer period: $TIMER_PERIOD"
        info "Valid periods: hourly · daily · weekly · monthly"
        return 1
    fi
    local mode="apply updates"
    [ "$TIMER_NOTIFY" = "1" ] && mode="monitor (report snapshots only)"
    echo "── $TIMER_UNIT_NAME.service ($TIMER_SCOPE scope · $mode) ──"
    timer_render_service
    echo ""
    echo "── $TIMER_UNIT_NAME.timer (OnCalendar=$(timer_calendar_for "$TIMER_PERIOD")) ──"
    timer_render_timer
    echo ""
    info "Install for real: uo --timer-install $TIMER_PERIOD"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# timer_tick() — CLI action behind --timer-tick (the monitor mode payload)
#
# One scheduled read-only check: generate the JSON report, append it to the
# JSONL time series (the exact document stream the dashboard Trends tab
# loads), log the verdict to the journal and — only when the summary is not
# "good" — raise a desktop notification. Nothing here mutates system state.
#
# Globals:   TIMER_REPORT_LOG, SCRIPT_VERSION (read)
# Returns:   0 — snapshot recorded
#            1 — the report itself failed
# ───────────────────────────────────────────────────────────────────────────────
timer_tick() {
    header "Scheduled Monitor Tick"
    local json
    if ! json=$(system_report_json); then
        failure "Monitor tick could not produce a report."
        return 1
    fi
    if ! mkdir -p "$TIMER_DATA_DIR" 2>/dev/null; then
        failure "Cannot create the data directory: $TIMER_DATA_DIR"
        return 1
    fi
    printf '%s\n' "$json" >> "$TIMER_REPORT_LOG" || {
        failure "Cannot append to: $TIMER_REPORT_LOG"
        return 1
    }
    local status ram disk_warn failed
    status=$(printf '%s' "$json" | grep -o '"status":"[a-z]*"' | head -n 1 | cut -d '"' -f 4)
    ram=$(printf '%s' "$json" | grep -o '"ram_percent":[0-9]*' | head -n 1 | cut -d ':' -f 2)
    disk_warn=$(printf '%s' "$json" | grep -o '"disk_warnings":[0-9]*' | head -n 1 | cut -d ':' -f 2)
    failed=$(printf '%s' "$json" | grep -o '"failed_services":[0-9]*' | head -n 1 | cut -d ':' -f 2)
    : "${status:=unknown}"
    : "${ram:=?}"
    : "${disk_warn:=?}"
    : "${failed:=?}"
    success "Snapshot appended: $TIMER_REPORT_LOG"
    info "Verdict: status=$status · RAM=${ram}% · disk_warnings=$disk_warn · failed_services=$failed"
    if [ "$status" != "good" ] && [ "$status" != "unknown" ]; then
        local msg="system status: $status"
        [ "$ram" != "?" ] && msg="$msg — RAM ${ram}%"
        [ "$disk_warn" != "?" ] && [ "$disk_warn" != "0" ] && msg="$msg — $disk_warn disk warning(s)"
        [ "$failed" != "?" ] && [ "$failed" != "0" ] && msg="$msg — $failed failed service(s)"
        warn "Attention suggested: $msg"
        info "Run: uo --report (details) · uo --optimize (fix)"
        if command -v notify-send >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
            notify-send -a "Ubuntu Optimizer" "uo needs attention" "$msg" 2>/dev/null || true
        fi
    else
        info "All comfortable — no notification raised."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_timer() — interactive menu behind main-menu entry 18
#
# A thin loop over the five relevant CLI actions so menu users get the same
# validated code paths (no duplicated logic).
#
# Globals:   TIMER_PERIOD, TIMER_SCOPE, TIMER_NOTIFY (read/write)
# Returns:   0 — on back
# ───────────────────────────────────────────────────────────────────────────────
menu_timer() {
    local choice
    while true; do
        clear
        echo -e "${BOLD}   ── Scheduled updates (systemd timer) ──${NC}"
        echo "    Scope: $TIMER_SCOPE · Mode: $([ "$TIMER_NOTIFY" = "1" ] && echo monitor || echo apply)"
        echo ""
        echo "    1) Install timer — apply updates weekly (default)"
        echo "    2) Install timer — monitor mode (report snapshots, no changes)"
        echo "    3) Preview the unit files"
        echo "    4) Status"
        echo "    5) Show run log"
        echo "    6) Remove timer"
        echo "    0) Back"
        echo ""
        read -r -p "   Select: " choice || return 0
        case $choice in
            1) TIMER_NOTIFY=0; timer_cli_install; press_enter ;;
            2) TIMER_NOTIFY=1; timer_cli_install; press_enter ;;
            3) timer_cli_preview; press_enter ;;
            4) timer_cli_status; press_enter ;;
            5) timer_cli_log; press_enter ;;
            6) timer_cli_remove; press_enter ;;
            0) return 0 ;;
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}
