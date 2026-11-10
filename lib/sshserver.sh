# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/sshserver.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Remote-access SSH server: install, enable and report. openssh-server is
#  what makes THIS machine reachable via `ssh user@ip` from laptops, phones
#  or other servers — a completely different thing from openssh-client (the
#  GitHub key wizard in lib/gitssh.sh, which only lets you reach OUT).
#
#  ssh_server_setup() walks the whole path honestly:
#    1. pre-flight apt + a running systemd (refuses BEFORE prompting — a
#       container/WSL1 box can install the package but can never start it)
#    2. apt install openssh-server (skipped when already installed)
#    3. systemctl enable --now ssh (the Ubuntu unit; sshd is the fallback
#       name on other distros) — this is what makes it survive reboots
#    4. UFW: when the firewall is ACTIVE and OpenSSH is not allowed yet,
#       offer `ufw allow OpenSSH` (an active firewall silently eating port
#       22 is the #1 "I installed ssh but can't connect" cause)
#    5. verify the service is really up and the port is really listening,
#       then print the exact connect line for this machine
#  ssh_server_status() is the read-only version of all of the above.
#
#  Every privileged step captures stderr and prints it verbatim on failure
#  (the v7.18.5 honesty pattern) — a wrong password, a missing package or a
#  refused service each say exactly what happened.
#
#  Test hooks (not part of the user-facing configuration):
#      SSH_SERVER_SSHD_BIN     — override the sshd binary path (default
#                                /usr/sbin/sshd) so tests can install/uninstall
#                                it without touching the real filesystem
#      SSH_SERVER_SYSTEMD_DIR  — override the systemd runtime directory
#                                (default /run/systemd/system) to simulate
#                                containers/WSL1 without systemd
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# ssh_server_unit() — resolve the OpenSSH server systemd unit name
#
# Ubuntu ships it as ssh.service (sshd.service is an alias that only exists
# when openssh-server is installed); Debian and most other distros use
# sshd.service. The first unit that exists in systemd's eyes wins, ssh is
# probed first (the Ubuntu name).
#
# Returns:   0 — unit name printed
#            1 — neither unit exists (systemctl missing or no unit)
# ───────────────────────────────────────────────────────────────────────────────
ssh_server_unit() {
    local u
    for u in ssh sshd; do
        if systemctl list-unit-files "$u.service" 2> /dev/null | grep -q "$u.service"; then
            printf '%s\n' "$u"
            return 0
        fi
    done
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# ssh_server_installed() — is the OpenSSH SERVER package present?
#
# The sshd binary lives in /usr/sbin, which is often outside a normal
# user's PATH — probe the absolute path first (SSH_SERVER_SSHD_BIN hook
# for tests) and only then fall back to command -v.
#
# Returns:   0 — installed
#            1 — not installed
# ───────────────────────────────────────────────────────────────────────────────
ssh_server_installed() {
    local bin=${SSH_SERVER_SSHD_BIN:-/usr/sbin/sshd}
    [ -x "$bin" ] && return 0
    command -v sshd > /dev/null 2>&1
}

# ───────────────────────────────────────────────────────────────────────────────
# ssh_server_listen_port() — the TCP port sshd is actually listening on
#
# Parses `ss -tln` for the sshd process line ("users:(("sshd"..."))") and
# prints the port of the first LISTEN socket; nothing printed when sshd
# is not listening (or ss is unavailable).
#
# Returns:   0 — port printed (or nothing when not listening)
# ───────────────────────────────────────────────────────────────────────────────
ssh_server_listen_port() {
    command -v ss > /dev/null 2>&1 || return 0
    ss -tlnp 2> /dev/null | awk '/sshd/ {match($4, /:[0-9]+$/); if (RSTART) print substr($4, RSTART+1); exit}'
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# ssh_server_status() — read-only report of the whole remote-access stack
#
# Prints: package installed or not, systemd unit state (active/enabled),
# the listening port and the UFW verdict — plus the ready-to-paste connect
# line when everything is green.
#
# Arguments: none
# Returns:   0 — always (a status report is never an error)
# ───────────────────────────────────────────────────────────────────────────────
ssh_server_status() {
    header "🛰 SSH Server Status (remote access)"

    if ssh_server_installed; then
        success "openssh-server is installed."
    else
        warn "openssh-server is NOT installed — this machine cannot be reached over SSH."
        info "Install it with:  uo --ssh-server"
        return 0
    fi

    local unit
    unit=$(ssh_server_unit || true)
    if [ -z "$unit" ]; then
        warn "No systemd unit for sshd found — the service cannot start on boot."
    else
        local state enabled
        state=$(systemctl is-active "$unit" 2> /dev/null || true)
        enabled=$(systemctl is-enabled "$unit" 2> /dev/null || true)
        if [ "$state" = "active" ]; then
            success "Service $unit is running${enabled:+ (starts on boot: $enabled)}."
        else
            warn "Service $unit is NOT running (state: ${state:-unknown}) — start it with:  sudo systemctl start $unit"
        fi
    fi

    local port
    port=$(ssh_server_listen_port)
    if [ -n "$port" ]; then
        success "Listening on port $port."
    else
        warn "Not listening on any TCP port (service down, or ss unavailable)."
    fi

    if command -v ufw > /dev/null 2>&1; then
        local ufw_out
        ufw_out=$(sudo ufw status 2> /dev/null || ufw status 2> /dev/null || true)
        case "$ufw_out" in
            *"Status: active"*)
                if printf '%s' "$ufw_out" | grep -qiE "OpenSSH|22/tcp"; then
                    success "UFW is active and OpenSSH is allowed."
                else
                    warn "UFW is active but OpenSSH is NOT allowed — connections will time out."
                    info "Fix with:  sudo ufw allow OpenSSH"
                fi
                ;;
            *"Status: inactive"*)
                info "UFW is inactive — no firewall is blocking port 22."
                ;;
            *)
                info "UFW state unknown (run as root to see it: sudo ufw status)."
                ;;
        esac
    fi

    local ip
    ip=$(hostname -I 2> /dev/null | awk '{print $1}')
    if [ -n "$ip" ]; then
        info "Connect from another machine:  ssh ${USER:-$USER}@${ip}${port:+ -p $port}"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# ssh_server_setup() — install, enable and open the firewall (the wizard)
#
# Pre-flights BEFORE asking for the password: apt must exist (Debian/Ubuntu
# family) and systemd must be running (a container or WSL1 without systemd
# can never start the service — refusing early beats installing something
# that can't run). Then: package (skipped when present) → systemctl
# enable --now → UFW allow (only when the firewall is active and OpenSSH
# missing) → live verification + the connect line.
#
# Arguments: none
# Returns:   0 — server installed/enabled and verified
#            1 — pre-flight refused, install or enable failed, or
#                verification could not confirm a listening port
# ───────────────────────────────────────────────────────────────────────────────
ssh_server_setup() {
    header "🛰 SSH Server Setup (remote access)"

    # ── Pre-flight 1: Debian/Ubuntu package manager ─────────────────────────
    if ! command -v apt-get > /dev/null 2>&1 && ! command -v apt > /dev/null 2>&1; then
        failure "No apt found — this tool installs openssh-server via the Debian/Ubuntu package manager only."
        info "  └ Install openssh-server with your distribution's package manager instead."
        return 1
    fi

    # ── Pre-flight 2: a running systemd (containers/WSL1 can't start sshd) ──
    if [ ! -d "${SSH_SERVER_SYSTEMD_DIR:-/run/systemd/system}" ]; then
        failure "systemd is not running — the ssh service cannot be enabled or started here."
        info "  └ Common in containers and WSL1. In WSL2 enable systemd in /etc/wsl.conf ([boot] systemd=true) and retry."
        return 1
    fi

    # ── Step 1: the package (skipped when already present) ──────────────────
    if ssh_server_installed; then
        info "openssh-server is already installed — skipping the package step."
    else
        confirm_action "Install the OpenSSH server (this machine becomes reachable via ssh)?" \
            || { warn "Cancelled — nothing was changed."; return 1; }
        local _out=""
        _out=$(sudo apt-get install -y openssh-server 2>&1) || {
            failure "Could not install openssh-server."
            [ -n "$_out" ] && info "  └ $(printf '%s' "$_out" | head -n 1)"
            return 1
        }
        success "openssh-server installed."
    fi

    # ── Step 2: enable + start now (survives reboots) ────────────────────────
    local unit
    unit=$(ssh_server_unit || true)
    if [ -z "$unit" ]; then
        failure "No ssh/sshd systemd unit was found after installation."
        info "  └ Something removed the unit file — reinstall:  sudo apt-get install --reinstall openssh-server"
        return 1
    fi
    local _enable_out=""
    _enable_out=$(sudo systemctl enable --now "$unit" 2>&1) || {
        failure "Could not enable/start the $unit service."
        [ -n "$_enable_out" ] && info "  └ $(printf '%s' "$_enable_out" | head -n 1)"
        return 1
    }
    success "Service $unit enabled and started (survives reboots)."

    # ── Step 3: firewall — only when UFW is active and 22 is closed ─────────
    if command -v ufw > /dev/null 2>&1; then
        local _ufw=""
        _ufw=$(sudo ufw status 2> /dev/null || true)
        case "$_ufw" in
            *"Status: active"*)
                if printf '%s' "$_ufw" | grep -qiE "OpenSSH|22/tcp"; then
                    info "UFW is active and OpenSSH is already allowed."
                else
                    confirm_action "UFW is active but port 22 is closed — allow OpenSSH in the firewall?" \
                        || { warn "Skipped the firewall change — SSH may be unreachable from other machines."; }
                    if sudo ufw allow OpenSSH > /dev/null 2>&1; then
                        success "UFW now allows OpenSSH."
                    else
                        warn "Could not add the UFW rule — allow it by hand:  sudo ufw allow OpenSSH"
                    fi
                fi
                ;;
            *"Status: inactive"*)
                info "UFW is inactive — no firewall change needed."
                ;;
            *)
                info "UFW state unknown — if the firewall is active, allow SSH with:  sudo ufw allow OpenSSH"
                ;;
        esac
    fi

    # ── Step 4: verify for real, then hand the user the connect line ────────
    local state port ip
    state=$(systemctl is-active "$unit" 2> /dev/null || true)
    port=$(ssh_server_listen_port)
    if [ "$state" != "active" ]; then
        failure "The $unit service did not reach 'active' — check:  systemctl status $unit"
        return 1
    fi
    if [ -z "$port" ]; then
        failure "The service is active but nothing is listening yet (ss sees no sshd socket)."
        info "  └ Give it a second and check:  uo --ssh-server-status"
        return 1
    fi
    ip=$(hostname -I 2> /dev/null | awk '{print $1}')
    success "SSH server is up on port $port."
    [ -n "$ip" ] && info "Connect from another machine:  ssh ${USER:-$USER}@${ip}${port:+ -p $port}"
    info "Check anytime:  uo --ssh-server-status"
    return 0
}
