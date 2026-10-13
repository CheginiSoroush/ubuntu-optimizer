# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/autostart.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Startup application manager for the XDG autostart layer — exactly the set
#  the desktop's "Startup Applications" (gnome-tweaks / gnome-session-properties)
#  edits: the .desktop entries in the user autostart dir and the system-wide
#  autostart dirs. Toggling never touches a system file: disabling a system
#  entry writes a user-level override (Hidden=true + X-GNOME-Autostart-
#  enabled=false), enabling removes that override again — every change is
#  one reversible file operation in the user's own home. systemd user
#  services are a separate layer and deliberately out of scope.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_user_dir() — the user autostart directory
#
# Arguments: none
# Returns:   prints the directory path
# ───────────────────────────────────────────────────────────────────────────────
_autostart_user_dir() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_system_dirs() — every system autostart directory
#
# Follows the XDG autostart spec: $XDG_CONFIG_DIRS/autostart for each element
# (default /etc/xdg). XDG_CONFIG_DIRS stays overridable — that is also what
# the test suite uses to pin a fake system tree.
#
# Arguments: none
# Returns:   prints one directory per line
# ───────────────────────────────────────────────────────────────────────────────
_autostart_system_dirs() {
    local dirs="${XDG_CONFIG_DIRS:-/etc/xdg}" d
    # an empty or ":"-only value falls back to the default per the XDG spec
    case "$dirs" in
        ""|":") dirs="/etc/xdg" ;;
    esac
    local IFS=":"
    for d in $dirs; do
        [ -n "$d" ] && printf '%s\n' "$d/autostart"
    done
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_system_has() — does a system autostart dir provide this entry?
#
# Arguments: $1 — file base name (e.g. "update-notifier.desktop")
# Returns:   0 — a system copy exists · 1 — none
# ───────────────────────────────────────────────────────────────────────────────
_autostart_system_has() {
    local d
    while IFS= read -r d; do
        [ -f "$d/$1" ] && return 0
    done < <(_autostart_system_dirs)
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_field() — extract a key's value from the [Desktop Entry] section
#
# Only the first matching "KEY=" line inside the [Desktop Entry] section
# counts — other sections ([Desktop Action], translations) are ignored, so
# "Name=" never leaks the localized names of an action block.
#
# Arguments: $1 — desktop file · $2 — key (e.g. Name, Exec, Hidden)
# Returns:   prints the value (empty when the key is absent)
# ───────────────────────────────────────────────────────────────────────────────
_autostart_field() {
    awk -v key="$2" '
        $0 == "[Desktop Entry]" { inentry = 1; next }
        /^\[/                   { inentry = 0 }
        inentry && index($0, key "=") == 1 {
            sub("^[^=]*=", "", $0)
            print
            exit
        }
    ' "$1" 2> /dev/null
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_disabled() — is a desktop entry turned off?
#
# A file is "disabled" when either the legacy Hidden=true or the
# X-GNOME-Autostart-enabled=false marker is set inside [Desktop Entry].
#
# Arguments: $1 — desktop file
# Returns:   0 — disabled · 1 — enabled
# ───────────────────────────────────────────────────────────────────────────────
_autostart_disabled() {
    [ "$(_autostart_field "$1" "Hidden")" = "true" ] && return 0
    [ "$(_autostart_field "$1" "X-GNOME-Autostart-enabled")" = "false" ] && return 0
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_resolve() — resolve a user-supplied name to its effective file
#
# Accepts the name with or without the .desktop extension, strips any path
# component (so "--autostart-off ../../etc/x" can never escape the autostart
# dirs) and prints the effective file: the user override when present, the
# first matching system file otherwise. Refuses unknown names.
#
# Arguments: $1 — user-supplied name
# Returns:   prints "<file><TAB><origin>" — origin: user | override | system
#            0 — found · 1 — unknown name
# ───────────────────────────────────────────────────────────────────────────────
_autostart_resolve() {
    local name="${1%.desktop}" base udir
    name="${name##*/}"          # basename only — no traversal
    [ -n "$name" ] || return 1
    base="${name}.desktop"
    udir=$(_autostart_user_dir)
    if [ -f "$udir/$base" ]; then
        # override = a user file that mirrors a system file of the same name
        if _autostart_system_has "$base"; then
            printf '%s\toverride\n' "$udir/$base"
        else
            printf '%s\tuser\n' "$udir/$base"
        fi
        return 0
    fi
    if _autostart_system_has "$base"; then
        local d
        while IFS= read -r d; do
            if [ -f "$d/$base" ]; then
                printf '%s\tsystem\n' "$d/$base"
                return 0
            fi
        done < <(_autostart_system_dirs)
    fi
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# _autostart_rewrite() — write final Hidden/enable values into a desktop file
#
# Rewrites only the [Desktop Entry] section: existing Hidden= and
# X-GNOME-Autostart-enabled= lines are stripped and both keys are written
# canonically right after the section header. Atomic via a temp file +
# rename; a failed write leaves the original untouched.
#
# Arguments: $1 — desktop file · $2 — Hidden value · $3 — enable value
# Returns:   0 — written · 1 — write failed (original preserved)
# ───────────────────────────────────────────────────────────────────────────────
_autostart_rewrite() {
    local file="$1" hidden="$2" enabled="$3" tmp="${1}.uo-tmp.$$"
    awk -v hidden="$hidden" -v enabled="$enabled" '
        $0 == "[Desktop Entry]" {
            inentry = 1
            print
            print "Hidden=" hidden
            print "X-GNOME-Autostart-enabled=" enabled
            next
        }
        /^\[/ { inentry = 0; print; next }
        inentry && (index($0, "Hidden=") == 1 || index($0, "X-GNOME-Autostart-enabled=") == 1) { next }
        { print }
    ' "$file" > "$tmp" && mv -f "$tmp" "$file"
}

# ───────────────────────────────────────────────────────────────────────────────
# autostart_set() — enable or disable one startup application
#
# Core of the module. Off:
#   • system entry  → copy it into the user autostart dir + disable there
#                     (the system file itself is never modified)
#   • user/override → disable in place (override files are user-owned)
# On:
#   • override of an enabled system entry → the override is removed (restore)
#   • override of a system entry that is disabled by default → the override
#     is forced to enabled (the system file still stays untouched)
#   • system entry that is disabled by default → a user override is created
#     and force-enabled (the system file still stays untouched)
#   • user entry → enabled in place
# Asks for confirmation unless -y was given.
#
# Arguments: $1 — application name (with/without .desktop) · $2 — on | off
# Returns:   0 — changed (or already in the wanted state) · 1 — error
# ───────────────────────────────────────────────────────────────────────────────
autostart_set() {
    local name="$1" state="$2" res file origin udir base disp
    if [ "$state" != "on" ] && [ "$state" != "off" ]; then
        failure "autostart_set: state must be on or off (got '$state')"
        return 1
    fi
    if ! res=$(_autostart_resolve "$name"); then
        failure "Startup application not found: $name"
        info "list the known entries with: uo --autostart"
        return 1
    fi
    file="${res%%$'\t'*}"
    origin="${res##*$'\t'}"
    base="${file##*/}"
    disp="$(_autostart_field "$file" "Name")"
    disp="${disp:-$base}"
    udir=$(_autostart_user_dir)

    case "$state" in
        off)
            if _autostart_disabled "$file"; then
                info "'$disp' is already disabled"
                return 0
            fi
            if [ "$origin" = "system" ]; then
                mkdir -p "$udir" 2> /dev/null || { failure "Cannot create $udir"; return 1; }
                if ! cp -f "$file" "$udir/$base"; then
                    failure "Cannot copy $file to $udir"
                    return 1
                fi
                file="$udir/$base"
            fi
            if ! confirm_action "Disable '$disp' at startup?"; then
                info "Cancelled — '$disp' stays enabled"
                return 0
            fi
            if ! _autostart_rewrite "$file" "true" "false"; then
                failure "Cannot write $file"
                return 1
            fi
            success "'$disp' disabled at startup (override: $file)"
            ;;
        on)
            if [ "$origin" = "override" ]; then
                # does the system default itself start disabled?
                local sdir sysfile=""
                while IFS= read -r sdir; do
                    if [ -f "$sdir/$base" ]; then sysfile="$sdir/$base"; break; fi
                done < <(_autostart_system_dirs)
                if [ -n "$sysfile" ] && ! _autostart_disabled "$sysfile"; then
                    if ! confirm_action "Enable '$disp' (remove the user override, restore the system default)?"; then
                        info "Cancelled — '$disp' stays disabled"
                        return 0
                    fi
                    if rm -f "$file"; then
                        success "'$disp' enabled (override removed — system default restored)"
                    else
                        failure "Cannot remove $file"
                        return 1
                    fi
                    return 0
                fi
            fi
            if [ "$origin" = "system" ]; then
                # a system entry that is disabled by default: force-enable
                # through a user override — the system file stays untouched
                mkdir -p "$udir" 2> /dev/null || { failure "Cannot create $udir"; return 1; }
                if ! cp -f "$file" "$udir/$base"; then
                    failure "Cannot copy $file to $udir"
                    return 1
                fi
                file="$udir/$base"
            fi
            if ! _autostart_disabled "$file"; then
                info "'$disp' is already enabled"
                return 0
            fi
            if ! confirm_action "Enable '$disp' at startup?"; then
                info "Cancelled — '$disp' stays disabled"
                return 0
            fi
            if ! _autostart_rewrite "$file" "false" "true"; then
                failure "Cannot write $file"
                return 1
            fi
            success "'$disp' enabled at startup ($file)"
            ;;
    esac
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# autostart_show() — list every startup application (read-only)
#
# One line per entry: state icon (✓ enabled / ✗ disabled), the application
# name, its state and origin (system · user · user override) and the command.
# Ends with a usage hint for the two toggle flags.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
autostart_show() {
    header "Startup Applications"
    local udir sdir d f base
    local name exec_cmd origin state_icon state_txt
    local enabled_n=0 disabled_n=0 found=0
    local -a seen=()
    local -A listed=()

    # collect: user entries first (they win), then the system dirs
    local -a dirs=()
    udir=$(_autostart_user_dir)
    [ -d "$udir" ] && dirs+=("$udir")
    while IFS= read -r sdir; do
        [ -d "$sdir" ] && dirs+=("$sdir")
    done < <(_autostart_system_dirs)

    for d in "${dirs[@]}"; do
        for f in "$d"/*.desktop; do
            [ -f "$f" ] || continue
            base="${f##*/}"
            [ -n "${listed[$base]:-}" ] && continue
            listed[$base]=1
            seen+=("$f")
        done
    done

    if [ ${#seen[@]} -eq 0 ]; then
        info "No autostart entries found in:"
        info "  $udir  ·  $(_autostart_system_dirs | tr '\n' ' ')"
        return 0
    fi

    for f in "${seen[@]}"; do
        base="${f##*/}"
        name="$(_autostart_field "$f" "Name")"
        name="${name:-$base}"
        exec_cmd="$(_autostart_field "$f" "Exec")"
        exec_cmd="${exec_cmd:--}"
        # shorten long commands to keep the table on one line
        if [ ${#exec_cmd} -gt 52 ]; then
            exec_cmd="${exec_cmd:0:49}..."
        fi
        if _autostart_disabled "$f"; then
            state_icon="✗"
            state_txt="disabled"
            disabled_n=$((disabled_n + 1))
        else
            state_icon="✓"
            state_txt="enabled"
            enabled_n=$((enabled_n + 1))
        fi
        case "$f" in
            "$udir"/*) if _autostart_system_has "$base"; then
                           origin="user override"
                       else
                           origin="user"
                       fi ;;
            *) origin="system" ;;
        esac
        printf '   %s %-36s %-22s %-9s (%s) %s\n' \
            "$state_icon" "$base" "$name" "$state_txt" "$origin" "$exec_cmd"
        found=$((found + 1))
    done

    echo ""
    success "$found startup application(s): $enabled_n enabled, $disabled_n disabled"
    info "toggle: uo --autostart-off NAME  ·  uo --autostart-on NAME"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# autostart_toggle_menu() — shared numbered picker behind the two menu entries
#
# Lists only the entries matching the requested target state (enabled for
# "off", disabled for "on"), reads a choice and hands it to autostart_set —
# which asks its own confirmation.
#
# Arguments: $1 — on | off (the state to SET)
# Returns:   0 — always (an invalid/empty selection just returns)
# ───────────────────────────────────────────────────────────────────────────────
autostart_toggle_menu() {
    local state="$1" pick d f
    header "Startup Applications"
    local udir sdir
    local -a dirs=() files=()
    udir=$(_autostart_user_dir)
    [ -d "$udir" ] && dirs+=("$udir")
    while IFS= read -r sdir; do
        [ -d "$sdir" ] && dirs+=("$sdir")
    done < <(_autostart_system_dirs)

    local i=0 name
    for d in "${dirs[@]}"; do
        for f in "$d"/*.desktop; do
            [ -f "$f" ] || continue
            if [ "$state" = "off" ] && _autostart_disabled "$f"; then continue; fi
            if [ "$state" = "on" ] && ! _autostart_disabled "$f"; then continue; fi
            i=$((i + 1))
            name="$(_autostart_field "$f" "Name")"
            name="${name:-${f##*/}}"
            files+=("${f##*/}")
            printf '   %d) %-36s %s\n' "$i" "${f##*/}" "$name"
        done
    done
    if [ "$i" -eq 0 ]; then
        info "Nothing to $([ "$state" = "off" ] && echo disable || echo enable)"
        return 0
    fi
    read -r -p "   Select (0 = cancel): " pick || return 0
    [[ "$pick" =~ ^[0-9]+$ ]] || { warn "Invalid choice"; return 0; }
    [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ] || return 0
    autostart_set "${files[$((pick-1))]}" "$state"
}

# ───────────────────────────────────────────────────────────────────────────────
# autostart_disable_menu() — interactive: pick an enabled entry to disable
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
autostart_disable_menu() {
    autostart_toggle_menu off
}

# ───────────────────────────────────────────────────────────────────────────────
# autostart_enable_menu() — interactive: pick a disabled entry to enable
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
autostart_enable_menu() {
    autostart_toggle_menu on
}
