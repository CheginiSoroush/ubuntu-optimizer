# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/ports.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Read-only listening-port report: which sockets are open, which process owns
#  them and — the security-relevant part — which ones bind all interfaces
#  (0.0.0.0 / :: / *) instead of loopback only. Prefers ss (iproute2), falls
#  back to netstat, and degrades to an install hint when neither exists.
#  Without root the process column may be empty — that is reported honestly.
#  Entry points: the CLI flag --ports and the "Monitor & inspect" submenu.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _ports_is_exposed() — does this bind address reach every interface?
#
# Pure classifier for the local-address part of a socket: the wildcard binds
# ("0.0.0.0", "::", "*", "[::]") are reachable from any network, while
# loopback ("127.0.0.1", "[::1]") and LAN addresses ("192.168.1.5") are not.
#
# Arguments: $1 — bind address (no port)
# Returns:   0 — binds all interfaces (exposed) · 1 — bound to a specific one
# ───────────────────────────────────────────────────────────────────────────────
_ports_is_exposed() {
    case "$1" in
        "0.0.0.0"|"::"|"*"|"[::]") return 0 ;;
        *) return 1 ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# _ports_proc_name() — extract the owning process name from one listener line
#
# ss prints the owner as users:(("nginx",pid=1,fd=3)); netstat prints
# "pid/name" as the last column (or "-" without root). Returns an empty
# string when the line carries no process info — which is normal without
# root — so callers can render a placeholder instead of garbage.
#
# Arguments: $1 — the raw line · $2 — tool mode (ss | netstat)
# Returns:   prints the process name (may be empty)
# ───────────────────────────────────────────────────────────────────────────────
_ports_proc_name() {
    local line="$1" mode="$2" proc
    if [ "$mode" = "ss" ]; then
        sed -n 's/.*users:(("\([^"]*\)".*/\1/p' <<< "$line"
        return 0
    fi
    # netstat: the process is the last space-separated field, "pid/name".
    # A line without a process column ends with the peer address, a state
    # word or "-" — none of those is a process name.
    proc="${line##* }"
    case "$proc" in
        *:*|LISTEN|UNCONN|""|-|"*") return 0 ;;
        *) printf '%s\n' "${proc##*/}" ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# ports_show() — list the listening sockets (read-only)
#
# One line per listening socket: exposure marker (⚠ for all-interface binds),
# protocol, local address:port and the owning process (may be "-" without
# root). Ends with a count summary and — when something is exposed — a hint
# to review it with 'uo --security' or ufw. Always exits 0.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
ports_show() {
    header "Listening Ports"

    # ── pick the tool: ss first, netstat as the fallback ──────────────────────
    local mode=""
    if command -v ss > /dev/null 2>&1; then
        mode="ss"
    elif command -v netstat > /dev/null 2>&1; then
        mode="netstat"
    else
        info "Neither 'ss' nor 'netstat' found — install iproute2 (sudo apt install iproute2)"
        return 0
    fi

    local raw_out
    if [ "$mode" = "ss" ]; then
        raw_out=$(ss -tulnpH 2> /dev/null)
    else
        raw_out=$(netstat -tulnp 2> /dev/null)
    fi
    if [ -z "$raw_out" ]; then
        info "No listening sockets found (or the tool returned nothing)."
        return 0
    fi

    local line proto state local_addr proc marker
    local total=0 exposed=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # split off the leading fields — the column layout differs per tool
        if [ "$mode" = "ss" ]; then
            # ss:  tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",...))
            read -r proto state _ _ local_addr _ <<< "$line"
            case "$state" in
                LISTEN|UNCONN) ;;
                *) continue ;;
            esac
        else
            # netstat:  tcp 0 0 0.0.0.0:22 0.0.0.0:* LISTEN 800/sshd
            # udp lines carry no LISTEN state — the proto column decides
            read -r proto _ _ local_addr _ state _ <<< "$line"
            case "$proto" in
                tcp|tcp6) [ "$state" = "LISTEN" ] || continue ;;
                udp|udp6) ;;
                *) continue ;;
            esac
        fi
        total=$(( total + 1 ))
        proc=$(_ports_proc_name "$line" "$mode")
        [ -n "$proc" ] || proc="-"
        marker=""
        if _ports_is_exposed "${local_addr%:*}"; then
            marker="⚠"
            exposed=$(( exposed + 1 ))
        fi
        printf '   %-2s %-5s %-25s %s\n' "$marker" "$proto" "$local_addr" "$proc"
    done <<< "$raw_out"

    echo ""
    if [ "$total" -eq 0 ]; then
        info "No listening sockets found."
        return 0
    fi
    if [ "$exposed" -gt 0 ]; then
        warn "$exposed of $total listening socket(s) bind all interfaces (⚠)"
        info "Review what they serve: 'uo --security' · sudo ufw status — close what you do not need"
    else
        success "$total listening socket(s), none binds all interfaces"
    fi
    return 0
}
