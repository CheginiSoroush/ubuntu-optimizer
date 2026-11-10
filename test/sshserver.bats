# ───────────────────────────────────────────────────────────────────────────────
#   test/sshserver.bats — lib/sshserver.sh (v7.18.7, --ssh-server family)
#
#   Covers the remote-access OpenSSH server feature:
#     • ssh_server_installed   — /usr/sbin probe + SSH_SERVER_SSHD_BIN hook
#     • ssh_server_unit        — ssh.service preferred, sshd.service fallback
#     • ssh_server_setup       — apt/systemd pre-flights (refuse BEFORE
#                                prompting), package install (skipped when
#                                present), enable --now, UFW allow when the
#                                firewall is active and 22 closed, live
#                                verification + connect line, and the v7.18.5
#                                honesty pattern: real errors are printed,
#                                never swallowed
#     • ssh_server_status      — read-only report for every state combination
#     • cli end-to-end         — the real entry script wires --ssh-server-status
#
#   All privileged binaries are stubs (sudo logs + delegates: apt-get,
#   systemctl, ufw); behavior knobs are env vars so every test is hermetic
#   regardless of what the CI runner really ships.
# ───────────────────────────────────────────────────────────────────────────────

setup() {
    TEST_HOME="$(mktemp -d)"
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"

    SUDO_LOG="$TEST_HOME/sudo-calls.log"
    : > "$SUDO_LOG"

    # Stubs must win over whatever the runner really ships (CI runners have a
    # real systemctl binary) — prefix PATH once, for every test
    export PATH="$STUB_BIN:$PATH"

    # ── the sshd binary fixture: present/absent per-test via this path ──────
    export SSH_SERVER_SSHD_BIN="$TEST_HOME/sshd-absent"
    export SSH_SERVER_SYSTEMD_DIR="$TEST_HOME/run-systemd"
    mkdir -p "$TEST_HOME/run-systemd"

    # ── systemctl stub: list-unit-files / is-active / is-enabled / enable ───
    cat > "$STUB_BIN/systemctl" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    list-unit-files)
        for u in ${UNIT_EXISTS-ssh}; do
            printf '%s.service enabled enabled\n' "$u"
        done
        exit 0 ;;
    is-active)
        if [ "${SYSCTL_ACTIVE:-1}" = "1" ]; then printf 'active\n'; exit 0; fi
        printf 'inactive\n'; exit 3 ;;
    is-enabled)
        printf '%s\n' "${SYSCTL_ENABLED:-enabled}"; exit 0 ;;
    enable)
        if [ "${SYSCTL_ENABLE_FAIL:-0}" = "1" ]; then
            # one meaningful line — like real systemctl failures; the wizard
            # surfaces exactly the first line of the captured output
            printf 'Failed to enable unit: Unit ssh.service is masked\n' >&2
            exit 1
        fi
        exit 0 ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/systemctl"

    # ── ss stub: emits an sshd LISTEN line only when SS_STUB_PORT is set ────
    cat > "$STUB_BIN/ss" << 'EOF'
#!/usr/bin/env bash
if [ -n "${SS_STUB_PORT:-}" ]; then
    printf 'LISTEN 0 4096 0.0.0.0:%s 0.0.0.0:* users:(("sshd",pid=999,fd=3))\n' "$SS_STUB_PORT"
fi
exit 0
EOF
    chmod +x "$STUB_BIN/ss"

    # ── hostname stub: deterministic LAN IP ─────────────────────────────────
    cat > "$STUB_BIN/hostname" << 'EOF'
#!/usr/bin/env bash
[ "$1" = "-I" ] && printf '%s\n' "${HOSTNAME_STUB_IP:-192.168.1.10}"
exit 0
EOF
    chmod +x "$STUB_BIN/hostname"

    # ── apt-get stub: succeeds unless APT_FAIL=1 ────────────────────────────
    cat > "$STUB_BIN/apt-get" << 'EOF'
#!/usr/bin/env bash
if [ "${APT_FAIL:-0}" = "1" ]; then
    printf 'E: Unable to locate package openssh-server\n' >&2
    exit 100
fi
exit 0
EOF
    chmod +x "$STUB_BIN/apt-get"

    # ── ufw stub: canned status text, logged allow ──────────────────────────
    cat > "$STUB_BIN/ufw" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    status)
        case "${UFW_STUB:-inactive}" in
            active-allowed) printf 'Status: active\n\nTo                         Action         From\n--                         ------         ----\nOpenSSH                    ALLOW          Anywhere\n' ;;
            active-closed)  printf 'Status: active\n\nTo                         Action         From\n--                         ------         ----\n25/tcp                     ALLOW          Anywhere\n' ;;
            *)              printf 'Status: inactive\n' ;;
        esac ;;
    allow)
        printf 'ufw allow %s\n' "$2" >> "${SUDO_LOG:-/dev/null}"
        exit 0 ;;
esac
exit 0
EOF
    chmod +x "$STUB_BIN/ufw"

    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/sshserver.sh"

    # ── sudo stub: logs every privileged call, delegates the stubbed ones ───
    # (defined AFTER the source — sourcing redefines confirm_action, and the
    #  stubs must win over the real interactive versions)
    sudo() {
        printf 'sudo %s\n' "$*" >> "$SUDO_LOG"
        case "$1" in
            apt-get)  "$STUB_BIN/apt-get" "${@:2}";  return $? ;;
            systemctl) "$STUB_BIN/systemctl" "${@:2}"; return $? ;;
            ufw)      "$STUB_BIN/ufw" "${@:2}";      return $? ;;
        esac
        return 0
    }

    # ── confirmations auto-accept (tests may override per-test) ─────────────
    confirm_action() { return 0; }
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# ---------- pure helpers ----------

@test "ssh_server_installed: probes the absolute sshd path via the hook" {
    : > "$TEST_HOME/fake-sshd"; chmod +x "$TEST_HOME/fake-sshd"
    SSH_SERVER_SSHD_BIN="$TEST_HOME/fake-sshd" run ssh_server_installed
    [ "$status" -eq 0 ]

    SSH_SERVER_SSHD_BIN="$TEST_HOME/no-sshd-here" run ssh_server_installed
    [ "$status" -eq 1 ]
}

@test "ssh_server_unit: prefers ssh.service and falls back to sshd.service" {
    UNIT_EXISTS="ssh sshd" run ssh_server_unit
    [ "$status" -eq 0 ]
    [ "$output" = "ssh" ]

    UNIT_EXISTS="sshd" run ssh_server_unit
    [ "$status" -eq 0 ]
    [ "$output" = "sshd" ]

    UNIT_EXISTS="" run ssh_server_unit
    [ "$status" -eq 1 ]
}

@test "ssh_server_listen_port: parses the ss LISTEN line, empty when silent" {
    SS_STUB_PORT="22" run ssh_server_listen_port
    [ "$status" -eq 0 ]
    [ "$output" = "22" ]

    SS_STUB_PORT="" run ssh_server_listen_port
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------- status report ----------

@test "ssh_server_status: not installed → honest warning with the install hint" {
    run ssh_server_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT installed"* ]]
    [[ "$output" == *"uo --ssh-server"* ]]
}

@test "ssh_server_status: fully green → running, listening, firewall, connect line" {
    : > "$TEST_HOME/sshd-present"; chmod +x "$TEST_HOME/sshd-present"
    export SSH_SERVER_SSHD_BIN="$TEST_HOME/sshd-present"
    export SS_STUB_PORT="22"
    export UFW_STUB="active-allowed"
    run ssh_server_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"openssh-server is installed."* ]]
    [[ "$output" == *"Service ssh is running"* ]]
    [[ "$output" == *"Listening on port 22."* ]]
    [[ "$output" == *"UFW is active and OpenSSH is allowed."* ]]
    [[ "$output" == *"Connect from another machine:  ssh "* ]]
    [[ "$output" == *"@192.168.1.10 -p 22"* ]]
}

@test "ssh_server_status: active firewall without an OpenSSH rule → warns with the fix" {
    : > "$TEST_HOME/sshd-present"; chmod +x "$TEST_HOME/sshd-present"
    export SSH_SERVER_SSHD_BIN="$TEST_HOME/sshd-present"
    export SS_STUB_PORT="22"
    export UFW_STUB="active-closed"
    run ssh_server_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"UFW is active but OpenSSH is NOT allowed"* ]]
    [[ "$output" == *"sudo ufw allow OpenSSH"* ]]
}

@test "ssh_server_status: service down and silent socket are reported honestly" {
    : > "$TEST_HOME/sshd-present"; chmod +x "$TEST_HOME/sshd-present"
    export SSH_SERVER_SSHD_BIN="$TEST_HOME/sshd-present"
    export SYSCTL_ACTIVE="0"
    export SS_STUB_PORT=""
    run ssh_server_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT running"* ]]
    [[ "$output" == *"sudo systemctl start ssh"* ]]
    [[ "$output" == *"Not listening on any TCP port"* ]]
}

# ---------- setup wizard: pre-flights ----------

@test "ssh_server_setup: refuses BEFORE anything privileged when systemd is missing" {
    export SSH_SERVER_SYSTEMD_DIR="$TEST_HOME/no-systemd-dir"
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "systemd is not running" "$MSG_LOG"
    grep -q "WSL2 enable systemd" "$MSG_LOG"
    [ ! -s "$SUDO_LOG" ]
}

@test "ssh_server_setup: refuses honestly on non-apt distributions" {
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    command() {   # no apt-get, no apt — even if the runner ships them
        if [ "$1" = "-v" ] && { [ "$2" = "apt-get" ] || [ "$2" = "apt" ]; }; then return 1; fi
        builtin command "$@"
    }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "No apt found" "$MSG_LOG"
    grep -q "Debian/Ubuntu" "$MSG_LOG"
    [ ! -s "$SUDO_LOG" ]
}

@test "ssh_server_setup: a declined confirmation changes nothing" {
    confirm_action() { return 1; }
    MSG_LOG="$TEST_HOME/msg.log"
    warn() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    info() { :; }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "Cancelled — nothing was changed" "$MSG_LOG"
    [ ! -s "$SUDO_LOG" ]
}

# ---------- setup wizard: the happy and broken paths ----------

@test "ssh_server_setup: installs, enables, opens UFW and verifies — full happy path" {
    export SS_STUB_PORT="22"
    export UFW_STUB="active-closed"
    MSG_LOG="$TEST_HOME/msg.log"
    header() { :; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    success() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    run ssh_server_setup
    [ "$status" -eq 0 ]
    grep -q "sudo apt-get install -y openssh-server" "$SUDO_LOG"
    grep -q "sudo systemctl enable --now ssh" "$SUDO_LOG"
    grep -q "ufw allow OpenSSH" "$SUDO_LOG"
    grep -q "openssh-server installed." "$MSG_LOG"
    grep -q "enabled and started (survives reboots)" "$MSG_LOG"
    grep -q "UFW now allows OpenSSH." "$MSG_LOG"
    grep -q "SSH server is up on port 22." "$MSG_LOG"
    grep -q "Connect from another machine" "$MSG_LOG"
}

@test "ssh_server_setup: already-installed machines skip the apt step entirely" {
    : > "$TEST_HOME/sshd-present"; chmod +x "$TEST_HOME/sshd-present"
    export SSH_SERVER_SSHD_BIN="$TEST_HOME/sshd-present"
    export SS_STUB_PORT="22"
    MSG_LOG="$TEST_HOME/msg.log"
    header() { :; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    success() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    run ssh_server_setup
    [ "$status" -eq 0 ]
    ! grep -q "apt-get install" "$SUDO_LOG"
    grep -q "already installed — skipping the package step" "$MSG_LOG"
    grep -q "sudo systemctl enable --now ssh" "$SUDO_LOG"
}

@test "ssh_server_setup: a failed apt install surfaces the real error line" {
    export APT_FAIL="1"
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "Could not install openssh-server." "$MSG_LOG"
    grep -q "E: Unable to locate package openssh-server" "$MSG_LOG"
}

@test "ssh_server_setup: a failed systemctl enable surfaces the real error too" {
    export SYSCTL_ENABLE_FAIL="1"
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "Could not enable/start the ssh service." "$MSG_LOG"
    grep -q "Failed to enable unit: Unit ssh.service is masked" "$MSG_LOG"
}

@test "ssh_server_setup: inactive UFW → no firewall call, explains why" {
    export SS_STUB_PORT="22"
    export UFW_STUB="inactive"
    MSG_LOG="$TEST_HOME/msg.log"
    header() { :; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    success() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    run ssh_server_setup
    [ "$status" -eq 0 ]
    ! grep -q "ufw allow" "$SUDO_LOG"
    grep -q "UFW is inactive — no firewall change needed." "$MSG_LOG"
}

@test "ssh_server_setup: service that never reaches active is a failure, not a lie" {
    export SS_STUB_PORT=""
    export SYSCTL_ACTIVE="0"
    MSG_LOG="$TEST_HOME/msg.log"
    failure() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    info() { printf '%s\n' "$*" >> "$MSG_LOG"; }
    header() { :; }
    success() { :; }
    run ssh_server_setup
    [ "$status" -eq 1 ]
    grep -q "did not reach 'active'" "$MSG_LOG"
}

# ---------- cli wiring ----------

@test "cli: --ssh-server-status runs end-to-end through the real entry script" {
    export PATH="$STUB_BIN:$PATH"
    run run_uo --ssh-server-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT installed"* ]]
    [[ "$output" == *"uo --ssh-server"* ]]
}

@test "cli: usage lists both ssh-server flags" {
    run run_uo --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--ssh-server        Install & enable the OpenSSH server"* ]]
    [[ "$output" == *"--ssh-server-status OpenSSH server status"* ]]
}
