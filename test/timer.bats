#!/usr/bin/env bats
# ============================================================
#   test/timer.bats — tests for the systemd timer (lib/timer.sh)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The timer module is exercised at two levels:
#     • CLI level — the real entry script with --timer-preview,
#       --timer-status, --timer-remove, --timer-install (the
#       sandbox has no systemd, which exercises the graceful
#       degradation path) and the modifier cross-validation.
#     • Function level — lib/common.sh + lib/timer.sh sourced
#       into the test shell with a temp HOME; systemctl is a
#       recording stub on PATH so install/remove are verified
#       end-to-end without a real systemd bus.
#   Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Pin the XDG config dir to the temp HOME: lib/timer.sh resolves the user
    # unit dir as ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user, and CI
    # runners export XDG_CONFIG_HOME=/home/runner/.config — pinning it makes
    # $UNIT_DIR the one true location on every machine
    export XDG_CONFIG_HOME="$TEST_HOME/.config"
    # Targeted copy: ubuntu-optimizer.sh + lib/*.sh only — a full-tree cp
    # would drag website/node_modules (~700 MB when present) and stall tests
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    UNIT_DIR="$TEST_HOME/.config/systemd/user"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules a timer test needs, into the test shell
load_timer() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/timer.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# ---------- CLI: --timer-preview rendering ----------

@test "cli: preview apply mode contains ExecStart with --update -y --no-color" {
    run run_uo --timer-preview weekly
    [ "$status" -eq 0 ]
    [[ "$output" == *"ExecStart="*"ubuntu-optimizer.sh --update -y --no-color"* ]]
}

@test "cli: preview renders both units with their names" {
    run run_uo --timer-preview weekly
    [ "$status" -eq 0 ]
    [[ "$output" == *"── uo-update.service"* ]]
    [[ "$output" == *"── uo-update.timer"* ]]
}

@test "cli: preview maps the four periods onto OnCalendar" {
    local period
    for period in hourly daily weekly monthly; do
        run run_uo --timer-preview "$period"
        [ "$status" -eq 0 ]
        [[ "$output" == *"OnCalendar=$period"* ]]
    done
}

@test "cli: preview without a period defaults to weekly" {
    run run_uo --timer-preview
    [ "$status" -eq 0 ]
    [[ "$output" == *"OnCalendar=weekly"* ]]
}

@test "cli: preview rejects an unknown period" {
    run run_uo --timer-preview yearly
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid timer period"* ]]
}

@test "cli: preview timer unit is Persistent with randomized delay" {
    run run_uo --timer-preview daily
    [ "$status" -eq 0 ]
    [[ "$output" == *"Persistent=true"* ]]
    [[ "$output" == *"RandomizedDelaySec=15m"* ]]
    [[ "$output" == *"WantedBy=timers.target"* ]]
}

@test "cli: preview monitor mode runs --timer-tick, never -y" {
    run run_uo --timer-preview weekly --timer-notify-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"ExecStart="*"ubuntu-optimizer.sh --timer-tick --no-color"* ]]
    [[ "$output" != *"--update -y"* ]]
    [[ "$output" == *"monitor"* ]]
}

@test "cli: preview system scope declares network-online, user scope does not" {
    run run_uo --timer-preview weekly --timer-system
    [ "$status" -eq 0 ]
    [[ "$output" == *"After=network-online.target"* ]]
    run run_uo --timer-preview weekly
    [ "$status" -eq 0 ]
    [[ "$output" != *"After=network-online.target"* ]]
}

# ---------- CLI: modifier cross-validation ----------

@test "cli: --timer-system alone is rejected" {
    run run_uo --timer-system
    [ "$status" -eq 1 ]
    [[ "$output" == *"only valid together with --timer-install or --timer-preview"* ]]
}

@test "cli: --timer-notify-only alone is rejected" {
    run run_uo --timer-notify-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"only valid together with --timer-install or --timer-preview"* ]]
}

@test "cli: --timer-log with a non-numeric argument is rejected" {
    run run_uo --timer-log abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid line count"* ]]
}

# ---------- CLI: graceful degradation without systemd ----------

@test "cli: status reports not-installed when no units exist" {
    run run_uo --timer-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Not installed"* ]]
    [[ "$output" == *"uo --timer-install weekly"* ]]
}

@test "cli: remove is a clean no-op when not installed" {
    run run_uo --timer-remove -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to remove"* ]]
}

# Hide systemctl from the CLI child so the graceful no-systemd path is
# exercised hermetically — the sandbox happens to lack systemd, but CI
# runners have a live systemd (/run/systemd/system exists) and would install
# a REAL unit. The shim dir mirrors the system bin dirs minus systemctl.
make_nosystemd_path() {
    local nopath="$TEST_HOME/nopath"
    mkdir -p "$nopath"
    local d f b
    # /usr/local/bin is mirrored too — the bash:X CI images keep bash
    # there, so a PATH built from /usr/bin + /bin alone would not even
    # have a bash to run
    for d in /usr/bin /bin /usr/local/bin; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            b="$(basename "$f")"
            [ -e "$nopath/$b" ] || ln -s "$f" "$nopath/$b"
        done
    done
    rm -f "$nopath/systemctl"
    printf '%s' "$nopath"
}

@test "cli: install without systemd fails gracefully with a preview hint" {
    local nopath
    nopath=$(make_nosystemd_path)
    run env PATH="$nopath" bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log --timer-install weekly
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemd is not available for the user scope"* ]]
    [[ "$output" == *"--timer-preview"* ]]
}

@test "cli: install system scope without systemd names the system scope" {
    local nopath
    nopath=$(make_nosystemd_path)
    run env PATH="$nopath" bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log --timer-install daily --timer-system
    [ "$status" -eq 1 ]
    [[ "$output" == *"systemd is not available for the system scope"* ]]
}

# ---------- function level: pure rendering helpers ----------

@test "fn: period whitelist accepts exactly the four periods" {
    load_timer
    timer_period_is_valid hourly && timer_period_is_valid daily \
        && timer_period_is_valid weekly && timer_period_is_valid monthly
    ! timer_period_is_valid yearly
    ! timer_period_is_valid ""
    ! timer_period_is_valid "weekly; rm -rf /"
}

@test "fn: timer_resolve_period fills the weekly default" {
    load_timer
    TIMER_PERIOD=""
    timer_resolve_period
    [ "$TIMER_PERIOD" = "weekly" ]
    TIMER_PERIOD="monthly"
    timer_resolve_period
    [ "$TIMER_PERIOD" = "monthly" ]
}

@test "fn: unit dir honours XDG_CONFIG_HOME for user scope" {
    load_timer
    TIMER_SCOPE="user"
    XDG_CONFIG_HOME="$TEST_HOME/xdg" run timer_unit_dir
    [ "$output" = "$TEST_HOME/xdg/systemd/user" ]
}

@test "fn: unit dir is /etc/systemd/system for system scope" {
    load_timer
    TIMER_SCOPE="system"
    run timer_unit_dir
    [ "$output" = "/etc/systemd/system" ]
}

@test "fn: render service — apply mode ExecStart, no network-online for user scope" {
    load_timer
    TIMER_SCOPE="user"; TIMER_NOTIFY=0; TIMER_PERIOD="weekly"
    run timer_render_service
    [ "$status" -eq 0 ]
    [[ "$output" == *"--update -y --no-color"* ]]
    [[ "$output" != *"network-online"* ]]
    [[ "$output" == *"SyslogIdentifier=uo-update"* ]]
}

@test "fn: render service — monitor mode and network-online for system scope" {
    load_timer
    TIMER_SCOPE="system"; TIMER_NOTIFY=1; TIMER_PERIOD="daily"
    run timer_render_service
    [ "$status" -eq 0 ]
    [[ "$output" == *"--timer-tick --no-color"* ]]
    [[ "$output" != *"--update -y"* ]]
    [[ "$output" == *"After=network-online.target"* ]]
    [[ "$output" == *"Wants=network-online.target"* ]]
}

@test "fn: render timer — Persistent, randomized delay, timers.target" {
    load_timer
    TIMER_SCOPE="user"; TIMER_NOTIFY=0; TIMER_PERIOD="monthly"
    run timer_render_timer
    [ "$status" -eq 0 ]
    [[ "$output" == *"OnCalendar=monthly"* ]]
    [[ "$output" == *"Persistent=true"* ]]
    [[ "$output" == *"RandomizedDelaySec=15m"* ]]
    [[ "$output" == *"WantedBy=timers.target"* ]]
}

@test "fn: timer_installed tracks the unit files" {
    load_timer
    TIMER_SCOPE="user"
    run timer_installed
    [ "$status" -eq 1 ]
    mkdir -p "$UNIT_DIR"
    touch "$UNIT_DIR/uo-update.service" "$UNIT_DIR/uo-update.timer"
    run timer_installed
    [ "$status" -eq 0 ]
}

# ---------- function level: install & remove with a systemctl stub ----------

# Installs a fake systemctl that records every invocation into $STUB_LOG
make_systemctl_stub() {
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
exit 0
EOF
    chmod +x "$STUB_BIN/systemctl"
    export STUB_LOG="$TEST_HOME/stub.log"
    : > "$STUB_LOG"
    # The stub must win over any real systemctl on the machine
    export PATH="$STUB_BIN:$PATH"
}

@test "fn: install (user scope) writes units and enables the timer" {
    load_timer
    TIMER_SCOPE="user"; TIMER_NOTIFY=0; TIMER_PERIOD="weekly"; ASSUME_YES=1; DRY_RUN=0
    timer_systemd_available() { return 0; }
    make_systemctl_stub
    run timer_cli_install
    [ "$status" -eq 0 ]
    [ -f "$UNIT_DIR/uo-update.service" ]
    [ -f "$UNIT_DIR/uo-update.timer" ]
    grep -q -- "--update -y --no-color" "$UNIT_DIR/uo-update.service"
    grep -q "OnCalendar=weekly" "$UNIT_DIR/uo-update.timer"
    grep -q "daemon-reload" "$STUB_LOG"
    grep -q "enable --now uo-update.timer" "$STUB_LOG"
    [[ "$output" == *"Timer installed and enabled"* ]]
}

@test "fn: re-install over existing units asks for confirmation first" {
    load_timer
    TIMER_SCOPE="user"; TIMER_NOTIFY=0; TIMER_PERIOD="daily"; ASSUME_YES=0; DRY_RUN=0
    timer_systemd_available() { return 0; }
    make_systemctl_stub
    timer_cli_install < /dev/null >/dev/null 2>&1
    [ -f "$UNIT_DIR/uo-update.timer" ]
    # Answer "n" → the existing timer must stay untouched
    run timer_cli_install <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"existing timer is untouched"* ]]
    grep -q "OnCalendar=daily" "$UNIT_DIR/uo-update.timer"
    # Answer "y" → overwrite proceeds
    run timer_cli_install <<< "y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timer installed and enabled"* ]]
}

@test "fn: remove disables the timer and deletes both units" {
    load_timer
    TIMER_SCOPE="user"; ASSUME_YES=1
    mkdir -p "$UNIT_DIR"
    touch "$UNIT_DIR/uo-update.service" "$UNIT_DIR/uo-update.timer"
    make_systemctl_stub
    run timer_cli_remove
    [ "$status" -eq 0 ]
    [ ! -f "$UNIT_DIR/uo-update.service" ]
    [ ! -f "$UNIT_DIR/uo-update.timer" ]
    grep -q "disable --now uo-update.timer" "$STUB_LOG"
    grep -q "daemon-reload" "$STUB_LOG"
    [[ "$output" == *"Timer removed"* ]]
}

@test "fn: install aborts cleanly when a unit file cannot be placed" {
    load_timer
    TIMER_SCOPE="user"; TIMER_NOTIFY=0; TIMER_PERIOD="weekly"; ASSUME_YES=1; DRY_RUN=0
    timer_systemd_available() { return 0; }
    # A read-only unit dir makes mkdir succeed but the mv fail
    timer_unit_dir() { printf '%s' "/proc/nonexistent/systemd/user"; }
    run timer_cli_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot write"* ]] || [[ "$output" == *"Cannot create"* ]]
}

# ---------- function level: monitor tick ----------

# A fixed report document the tick can digest — status/ram/disk/failed are
# extracted with the same grep pipeline the real module uses.
fixed_report() {
    local status="$1" ram="$2" disk="$3" failed="$4"
    printf '{"tool":"ubuntu-optimizer","version":"9.9","generated_at":"2026-01-01T00:00:00+00:00","summary":{"status":"%s","optimizations_ok":10,"optimizations_total":12,"failed_services":%d,"ram_percent":%d,"swap_percent":10,"disk_warnings":%d,"internet":true},"memory":{},"disks":[],"services":{},"optimizations":[],"network":{},"top_memory":[],"log_events":[]}\n' \
        "$status" "$failed" "$ram" "$disk"
}

@test "fn: monitor tick appends a JSONL snapshot and reports the verdict" {
    load_timer
    system_report_json() { fixed_report critical 91 2 3; }
    run timer_tick
    [ "$status" -eq 0 ]
    [ -f "$TIMER_REPORT_LOG" ]
    [ "$(wc -l < "$TIMER_REPORT_LOG")" -eq 1 ]
    grep -q '"status":"critical"' "$TIMER_REPORT_LOG"
    [[ "$output" == *"status=critical"* ]]
    [[ "$output" == *"RAM=91%"* ]]
}

@test "fn: two ticks append two lines — the series grows monotonically" {
    load_timer
    system_report_json() { fixed_report good 40 0 0; }
    timer_tick >/dev/null 2>&1
    timer_tick >/dev/null 2>&1
    [ "$(wc -l < "$TIMER_REPORT_LOG")" -eq 2 ]
    # both lines are valid JSON documents (they end with the log_events brace)
    while IFS= read -r line; do
        [[ "$line" == *'"log_events":[]}' ]]
    done < "$TIMER_REPORT_LOG"
}

@test "fn: healthy verdict raises no notification" {
    load_timer
    system_report_json() { fixed_report good 40 0 0; }
    NOTIFY_LOG="$TEST_HOME/notify.log"; : > "$NOTIFY_LOG"
    notify-send() { echo "$*" >> "$NOTIFY_LOG"; }
    export DISPLAY=:0
    run timer_tick
    [ "$status" -eq 0 ]
    [ ! -s "$NOTIFY_LOG" ]
    [[ "$output" == *"no notification raised"* ]]
}

@test "fn: critical verdict suggests attention and fires the notification" {
    load_timer
    system_report_json() { fixed_report critical 91 2 3; }
    NOTIFY_LOG="$TEST_HOME/notify.log"; : > "$NOTIFY_LOG"
    notify-send() { echo "$*" >> "$NOTIFY_LOG"; }
    export DISPLAY=:0
    run timer_tick
    [ "$status" -eq 0 ]
    [ -s "$NOTIFY_LOG" ]
    grep -q "critical" "$NOTIFY_LOG"
    [[ "$output" == *"Attention suggested"* ]]
}

@test "fn: a failing report aborts the tick without writing the series" {
    load_timer
    system_report_json() { return 1; }
    run timer_tick
    [ "$status" -eq 1 ]
    [ ! -f "$TIMER_REPORT_LOG" ]
    [[ "$output" == *"could not produce a report"* ]]
}
