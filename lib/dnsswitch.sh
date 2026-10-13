# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/dnsswitch.sh
# ───────────────────────────────────────────────────────────────────────────────
#  DNS preset switcher: one command swaps the system resolvers between
#  curated presets. The table covers the popular Iranian bypass resolvers
#  (shecan · 403online · radar · electro) and the international crowd
#  (cloudflare · google · quad9 · adguard) plus "auto" to hand control back
#  to DHCP. The apply path picks the best mechanism the machine offers —
#  NetworkManager, then systemd-resolved (resolvectl), and only as a last
#  resort a direct /etc/resolv.conf write with a timestamped backup — so
#  the module works on servers and desktops alike. Entry points: the CLI
#  flags --dns [PRESET] / --dns-list and main-menu item 22.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _dnsswitch_servers() — resolve a preset name to its resolver addresses
#
# The single source of truth for the preset table. "auto" resolves to an
# empty string — it does not set servers, it returns control to DHCP.
# Unknown names also resolve to an empty string; callers distinguish the
# two cases with dnsswitch_preset_valid.
#
# Arguments: $1 — preset name (e.g. shecan)
# Returns:   prints the space-separated IPv4 addresses (empty for auto)
# ───────────────────────────────────────────────────────────────────────────────
_dnsswitch_servers() {
    case "$1" in
        shecan)     echo "178.22.122.100 185.51.200.2" ;;
        403online)  echo "10.202.10.202 10.202.10.102" ;;
        radar)      echo "10.202.10.10 10.202.10.11" ;;
        electro)    echo "78.157.42.100 78.157.42.101" ;;
        cloudflare) echo "1.1.1.1 1.0.0.1" ;;
        google)     echo "8.8.8.8 8.8.4.4" ;;
        quad9)      echo "9.9.9.9 149.112.112.112" ;;
        adguard)    echo "94.140.14.14 94.140.15.15" ;;
        *)          echo "" ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# _dnsswitch_desc() — the one-line description of a preset
#
# Arguments: $1 — preset name
# Returns:   prints the description text
# ───────────────────────────────────────────────────────────────────────────────
_dnsswitch_desc() {
    case "$1" in
        shecan)     echo "Iranian bypass resolver — free, made for developers" ;;
        403online)  echo "Iranian bypass resolver — general purpose, free" ;;
        radar)      echo "Iranian bypass resolver — gaming / low latency" ;;
        electro)    echo "Iranian bypass resolver — general purpose" ;;
        cloudflare) echo "Cloudflare — fast and privacy-friendly" ;;
        google)     echo "Google — reliable everywhere" ;;
        quad9)      echo "Quad9 — blocks known malware domains" ;;
        adguard)    echo "AdGuard — blocks ads at the DNS level" ;;
        auto)       echo "Back to automatic DNS (DHCP)" ;;
        *)          echo "" ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_preset_valid() — is this a name the preset table knows?
#
# Arguments: $1 — candidate preset name
# Returns:   0 — valid preset name · 1 — unknown
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_preset_valid() {
    case "$1" in
        shecan|403online|radar|electro|cloudflare|google|quad9|adguard|auto) return 0 ;;
        *) return 1 ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_current() — print the resolvers currently in effect
#
# Priority: the per-link resolvectl view (systemd-resolved), then the
# NetworkManager connection settings, then a plain /etc/resolv.conf parse
# so even minimal containers get an answer. The output is the raw
# space-separated server list (or empty when nothing could be read) — the
# pretty rendering lives in dnsswitch_show.
#
# Documented disable (test hook): UO_DNS_FAKE_RESOLV points the parser at
# a different file than /etc/resolv.conf for the offline test suite.
#
# Arguments: none
# Returns:   0 — always (an unreadable system prints nothing, not an error)
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_current() {
    local line servers=""
    if command -v resolvectl > /dev/null 2>&1; then
        # "Global" and per-link "DNS Servers" lines; the stub 127.0.0.53 is skipped
        while IFS= read -r line; do
            case "$line" in
                *"DNS Servers"*) servers+="${line##*:*}" ;;
            esac
        done < <(resolvectl status 2> /dev/null)
        servers=$(printf '%s\n' "$servers" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
        servers=${servers//127.0.0.53/}
        [ -n "$servers" ] && { printf '%s\n' "$servers" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//'; echo; return 0; }
    fi
    if command -v nmcli > /dev/null 2>&1; then
        local conn
        # physical connection first — a VPN must never be inspected
        conn=$(get_active_connection ethernet)
        [ -z "$conn" ] && conn=$(get_active_connection wireless)
        [ -z "$conn" ] && conn=$(get_active_connection)
        if [ -n "$conn" ]; then
            servers=$(nmcli -g ipv4.dns connection show "$conn" 2> /dev/null | tr ',' ' ')
            servers=$(printf '%s\n' "$servers" | sed 's/^ *//;s/ *$//')
            if [ -n "$servers" ] && [ "$servers" != "--" ]; then
                printf '%s\n' "$servers" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//'; echo
                return 0
            fi
        fi
    fi
    # last resort: parse resolv.conf (skipping the localhost stub)
    local rc_file="${UO_DNS_FAKE_RESOLV:-/etc/resolv.conf}"
    if [ -r "$rc_file" ]; then
        local found=""
        while IFS= read -r line; do
            case "$line" in
                nameserver\ *127.0.0.53|nameserver\ *127.0.0.1|nameserver\ *::1) continue ;;
                nameserver\ *) found+="${line#nameserver } " ;;
            esac
        done < "$rc_file"
        found=$(printf '%s\n' "$found" | sed 's/ *$//')
        if [ -n "$found" ]; then
            printf '%s\n' "$found" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//'; echo
            return 0
        fi
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_show() — preset table + the resolvers currently in effect (read-only)
#
# Prints every preset with its addresses and one-line description, marks
# the preset that matches the current servers (if any), and closes with
# the current effective DNS from dnsswitch_current. Nothing is changed.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_show() {
    header "🌐 DNS Presets"
    local preset servers cur match
    cur=$(dnsswitch_current | tr -d '\n')
    echo ""
    echo -e "${BOLD}   ── Available presets ──${NC}"
    for preset in shecan 403online radar electro cloudflare google quad9 adguard auto; do
        servers=$(_dnsswitch_servers "$preset")
        [ -z "$servers" ] && servers="(DHCP)"
        match=""
        if [ -n "$cur" ] && [ -n "$servers" ] && [ "$servers" != "(DHCP)" ] \
           && [ "$(printf '%s\n' "$cur" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ *$//')" \
              = "$(printf '%s\n' "$servers" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ *$//')" ]; then
            match=" ${GREEN}(current)${NC}"
        fi
        printf '   • %-12s %-32s%s\n' "$preset" "$servers" "$match"
        printf '     %s\n' "$(_dnsswitch_desc "$preset")"
    done
    echo ""
    if [ -n "$cur" ]; then
        info "Currently effective resolvers: $cur"
    else
        info "Could not determine the current resolvers on this system."
    fi
    info "Apply one with: uo --dns <preset>   (e.g. uo --dns shecan)"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_apply_nm() — apply servers via NetworkManager (internal)
#
# Sets the resolvers on the active physical connection and flips
# ipv4.ignore-auto-dns; "auto" clears both back to DHCP. Returns 2 when
# nmcli or an active connection is unavailable, so the caller can fall
# through to the next mechanism.
#
# Arguments: $1 — "auto" or a servers string
# Returns:   0 — applied · 1 — the modify failed · 2 — mechanism unavailable
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_apply_nm() {
    command -v nmcli > /dev/null 2>&1 || return 2
    local conn
    # physical connection first — a VPN must never be modified
    conn=$(get_active_connection ethernet)
    [ -z "$conn" ] && conn=$(get_active_connection wireless)
    [ -z "$conn" ] && conn=$(get_active_connection)
    [ -n "$conn" ] || return 2
    if [ "$1" = "auto" ]; then
        sudo nmcli connection modify "$conn" ipv4.dns "" ipv4.ignore-auto-dns no || return 1
        sudo nmcli connection up "$conn" > /dev/null 2>&1
    else
        sudo nmcli connection modify "$conn" ipv4.dns "$1" ipv4.ignore-auto-dns yes || return 1
        sudo nmcli connection up "$conn" > /dev/null 2>&1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] Would apply on the NetworkManager connection '$conn'."
    else
        info "Applied on the NetworkManager connection '$conn'."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _dnsswitch_parse_links() — extract interfaces from `resolvectl list` output
#
# The list prints "Link <n> (<iface>)" lines — the interface name is inside
# the parentheses (the whole line is NOT "iface: something"). Loopback is
# skipped; the default-route interface ($1, when non-empty) comes first and
# is not repeated. Pure function: reads the listing on stdin, prints one
# interface per line.
#
# Arguments: $1 — the default-route interface ("" when there is none)
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_dnsswitch_parse_links() {
    local dr="$1" line iface
    if [ -n "$dr" ] && [ "$dr" != "lo" ]; then
        printf '%s\n' "$dr"
    fi
    while IFS= read -r line; do
        case "$line" in
            "Link "*")"*) ;;
            *) continue ;;
        esac
        iface="${line##* (}"
        iface="${iface%)}"
        [ -n "$iface" ] || continue
        [ "$iface" = "lo" ] && continue
        [ "$iface" = "$dr" ] && continue
        printf '%s\n' "$iface"
    done
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_apply_resolved() — apply servers via systemd-resolved (internal)
#
# resolvectl sets per-link resolvers; _dnsswitch_parse_links extracts the
# non-loopback links with the default-route interface first. "auto" reverts
# the links. Returns 2 when resolvectl or the systemd-resolved bus is
# missing.
#
# Arguments: $1 — "auto" or a servers string
# Returns:   0 — applied · 1 — the resolvectl call failed · 2 — unavailable
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_apply_resolved() {
    command -v resolvectl > /dev/null 2>&1 || return 2
    resolvectl status > /dev/null 2>&1 || return 2
    [ -d /run/systemd/system ] || return 2
    local -a servers=() ifaces=()
    local dr iface
    if [ "$1" != "auto" ]; then
        local s
        for s in $1; do servers+=("$s"); done
    fi
    # the interface with the default route is where DNS matters most
    dr=$(ip -o route show default 2> /dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
    mapfile -t ifaces < <(resolvectl list 2> /dev/null | _dnsswitch_parse_links "$dr")
    [ ${#ifaces[@]} -gt 0 ] || return 2
    for iface in "${ifaces[@]}"; do
        if [ "$1" = "auto" ]; then
            sudo resolvectl revert "$iface" || return 1
        else
            sudo resolvectl dns "$iface" "${servers[@]}" || return 1
        fi
    done
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] Would apply on systemd-resolved link(s): ${ifaces[*]}"
    else
        info "Applied on systemd-resolved link(s): ${ifaces[*]}"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_apply_resolvconf() — last-resort direct /etc/resolv.conf write
#
# Only ever used when neither NetworkManager nor systemd-resolved is
# available AND the file is a regular file (a symlink to the resolved stub
# must never be overwritten). A timestamped backup /etc/resolv.conf.bak-uo
# is kept; "auto" restores the newest backup when one exists.
#
# Arguments: $1 — "auto" or a servers string
# Returns:   0 — applied or restored · 1 — not possible / failed
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_apply_resolvconf() {
    local rc="/etc/resolv.conf"
    [ -e "$rc" ] && [ ! -L "$rc" ] || { warn "/etc/resolv.conf is a symlink or missing — refusing to write it directly."; return 1; }
    if [ "$1" = "auto" ]; then
        local backup
        # find + sort by mtime instead of "ls -1t | head" (SC2012); the
        # backup prefix is created by this tool, so the names are safe
        backup=$(find /etc -maxdepth 1 -name 'resolv.conf.bak-uo-*' -printf '%T@\t%p\n' 2>/dev/null \
            | sort -rn | head -n 1 | cut -f2-)
        if [ -n "$backup" ]; then
            sudo cp "$backup" "$rc" && { info "Restored $backup → $rc"; return 0; }
            return 1
        fi
        # no backup → this mechanism has nothing to restore. In dry-run the
        # preview must still succeed; a real run reports it could not act.
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] No resolv.conf backup exists — $rc would be left untouched."
            return 0
        fi
        warn "No backup exists to restore — leaving $rc untouched."
        return 1
    fi
    sudo cp "$rc" "$rc.bak-uo-$(date +%Y%m%d-%H%M%S)" || return 1
    {
        echo "# managed by ubuntu-optimizer (uo --dns)"
        local s
        for s in $1; do echo "nameserver $s"; done
    } | sudo tee "$rc" > /dev/null || return 1
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] /etc/resolv.conf would be rewritten with the preset resolvers (backup kept beside it)."
    else
        info "Written directly to /etc/resolv.conf (backup kept beside it)."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_apply() — apply the preset stored in DNS_PRESET
#
# The CLI parser validates and stores the preset name in DNS_PRESET (same
# pattern as PROFILE_NAME); without one the interactive picker runs first.
# Apply order: NetworkManager → systemd-resolved → resolv.conf. A quick
# name lookup afterwards reports whether the new resolvers actually answer
# (an offline machine gets an info note, never an error). With DRY_RUN=1
# the sudo wrapper prints every command and nothing is executed.
#
# Globals:   DNS_PRESET (read)
# Arguments: none
# Returns:   0 — applied (or nothing to do) · 1 — every mechanism failed
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_apply() {
    local preset="${DNS_PRESET:-}"
    if [ -z "$preset" ]; then
        dnsswitch_pick || return 0
        preset="${DNS_PRESET:-}"
        [ -n "$preset" ] || return 0
    fi
    header "🌐 Switch DNS → $preset"
    local servers rc=0
    servers=$(_dnsswitch_servers "$preset")
    info "$(_dnsswitch_desc "$preset")"

    if [ "$preset" = "auto" ]; then
        info "Returning DNS control to the network (DHCP)."
    else
        info "New resolvers: $servers"
    fi
    if ! confirm_action "Switch the system DNS to '$preset'?"; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! sudo_precheck; then
        return 1
    fi

    local target
    if [ "$preset" = "auto" ]; then target="auto"; else target="$servers"; fi
    dnsswitch_apply_nm "$target"
    rc=$?
    if [ "$rc" -eq 2 ]; then
        dnsswitch_apply_resolved "$target"
        rc=$?
    fi
    if [ "$rc" -eq 2 ]; then
        dnsswitch_apply_resolvconf "$target"
        rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        failure "Could not apply the DNS preset with any mechanism."
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        success "[dry-run] DNS preset '$preset' would be applied now."
        return 0
    fi

    # sanity check: does the new resolver actually answer? (offline → info)
    if command -v timeout > /dev/null 2>&1; then
        if timeout 5 getent hosts launchpad.net > /dev/null 2>&1; then
            success "DNS preset '$preset' is active and resolving."
        else
            info "Name lookup did not answer within 5s — if you are offline this is expected."
        fi
    else
        success "DNS preset '$preset' applied."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# dnsswitch_pick() — interactive preset picker (menu entry)
#
# Shows the preset table, reads one name (validated), stores it in
# DNS_PRESET and applies it. Declining or an empty answer leaves
# everything untouched.
#
# Globals:   DNS_PRESET (written)
# Arguments: none
# Returns:   0 — a preset was applied or the user backed out
# ───────────────────────────────────────────────────────────────────────────────
dnsswitch_pick() {
    dnsswitch_show
    local answer
    echo ""
    read -r -p "   Preset to apply (name, empty = cancel): " answer || return 0
    if [ -z "$answer" ]; then
        info "Cancelled — nothing was changed."
        return 0
    fi
    if ! dnsswitch_preset_valid "$answer"; then
        warn "Unknown preset: '$answer' — valid: shecan 403online radar electro cloudflare google quad9 adguard auto"
        return 0
    fi
    DNS_PRESET="$answer"
    dnsswitch_apply
    return 0
}
