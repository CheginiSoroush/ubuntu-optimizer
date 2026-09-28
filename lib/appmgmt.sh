# shellcheck shell=bash
# ============================================================
#   lib/appmgmt.sh — manage and fully remove apps from all sources
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Sources searched: tar.gz registry, apt (exact and fuzzy), snap,
#   flatpak, /opt directories and desktop files. /opt directories
#   owned by deb packages are detected so removal goes through the
#   right path.
# ============================================================

# Deb package owning a path — empty if it belongs to no package
deb_owner_of() {   # $1=path (e.g. /opt/Obsidian)
    dpkg -S "$1" 2>/dev/null | head -1 | cut -d: -f1 | awk '{print $1}' | tr -d ','
}

# Escape glob characters in raw input for a find -iname pattern
_glob_escape() {   # $1=raw string
    printf '%s' "$1" | sed 's/[][*?]/\\&/g'
}

# Extract the executable path from the Exec line of a desktop file
# Quotes and escaped spaces (\ ) are supported
_desktop_exec_path() {   # $1=desktop file path → output: path or empty
    grep -m1 '^Exec=' "$1" 2>/dev/null | cut -d= -f2- | tr -d '"' | awk '
    {
        path = ""
        n = split($0, tok, " ")
        for (i = 1; i <= n; i++) {
            if (tok[i] == "" && path != "") break
            if (tok[i] == "") continue
            if (path == "") { path = tok[i]; continue }
            # The previous token ended with "\" → it is the same path
            if (substr(path, length(path), 1) == "\\") {
                path = substr(path, 1, length(path) - 1) " " tok[i]
            } else break
        }
        print path
    }'
}

# Search for an app across all sources → FOUND_LINES array
# Entry format: type|id|description|optional_path
# Types: apt | snap | flatpak | targz | opt | manual
find_app_instances() {
    FOUND_LINES=()
    local raw="$1"
    local norm
    norm=$(normalize_name "$raw")
    [ -z "$norm" ] && return 1

    local rname rver rdir rexec rdesk rsrc n2 pn low name fn bn bnorm rn dup f d exec_path root owner fl vtxt
    local -a reg_names=() fuzzy=()

    # 1) tar.gz registry
    if [ -f "$REGISTRY_DB" ]; then
        while IFS='|' read -r rname rver rdir rexec rdesk rsrc; do
            [ -z "$rname" ] && continue
            n2=$(normalize_name "$rname")
            reg_names+=("$n2")
            if [ "$n2" = "$norm" ] || [[ "$n2" == *"$norm"* ]] || [[ "$norm" == *"$n2"* ]]; then
                vtxt=""
                [ -n "$rver" ] && vtxt=" (version $rver)"
                FOUND_LINES+=("targz|$rname|installed by this script$vtxt|$rdir")
            fi
        done < "$REGISTRY_DB"
    fi

    # 2) apt — exact match, otherwise a prefix search
    if pkg_installed "$raw"; then
        FOUND_LINES+=("apt|$raw|installed deb package|")
    else
        while IFS= read -r pn; do
            [ -z "$pn" ] && continue
            low=${pn,,}
            case "$low" in
                lib*|python3-*|*-dev|*-doc|*-common|*-data|*-dbg|*-bin|fonts-*|*-l10n|*-i18n|language-*|*-locale*) continue ;;
            esac
            [[ "$low" == "${raw,,}"* ]] && fuzzy+=("$pn")
            [ ${#fuzzy[@]} -ge 6 ] && break
        done < <(dpkg -l 2>/dev/null | awk '/^ii/ {sub(/:.*/, "", $2); print $2}')
        for pn in "${fuzzy[@]}"; do
            FOUND_LINES+=("apt|$pn|deb package (fuzzy name match)|")
        done
    fi

    # 3) snap
    if command -v snap > /dev/null 2>&1; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            [ "$(normalize_name "$name")" = "$norm" ] && FOUND_LINES+=("snap|$name|snap app|")
        done < <(snap list 2>/dev/null | awk 'NR > 1 {print $1}')
    fi

    # 4) flatpak
    if command -v flatpak > /dev/null 2>&1; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            fn=$(normalize_name "$name")
            if [[ "$fn" == *"$norm"* ]] || [[ "$norm" == *"$fn"* ]]; then
                FOUND_LINES+=("flatpak|$name|flatpak app|")
            fi
        done < <(flatpak list --app --columns=application 2>/dev/null)
    fi

    # 5) /opt directories — a dir owned by a deb package must be removed via apt
    #    so the package is not left in a broken state
    for d in /opt/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        bn=$(basename "$d")
        bnorm=$(normalize_name "$bn")
        [ -z "$bnorm" ] && continue
        if [ "$bnorm" = "$norm" ] || [[ "$bnorm" == *"$norm"* ]] || [[ "$norm" == *"$bnorm"* ]]; then
            owner=$(deb_owner_of "$d")
            if [ -n "$owner" ]; then
                dup=0
                for fl in "${FOUND_LINES[@]}"; do
                    [[ "$fl" == "apt|$owner|"* ]] && { dup=1; break; }
                done
                [ "$dup" = "1" ] || FOUND_LINES+=("apt|$owner|deb package (installed in $d)|")
                continue
            fi
            dup=0
            for rn in "${reg_names[@]}"; do
                [ "$rn" = "$bnorm" ] && { dup=1; break; }
            done
            [ "$dup" = "1" ] && continue
            FOUND_LINES+=("opt|$bn|manual install in /opt|$d")
        fi
    done

    # 6) Desktop files with an Exec inside the home dir (manual installs outside /opt)
    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        exec_path=$(_desktop_exec_path "$f")
        [ -z "$exec_path" ] && continue
        [ "${exec_path:0:1}" = "/" ] || continue
        [[ "$exec_path" == "$HOME"/* ]] || continue
        [[ "$exec_path" == "$HOME"/*/* ]] || continue
        root=$(derive_install_root "$exec_path")
        [ "$root" = "$HOME" ] && continue
        # Match: raw name in Name/Exec, or the normalized install-dir name
        if grep -E '^(Name|Exec)=' "$f" 2>/dev/null | grep -qiF "$raw" \
           || [ "$(normalize_name "$(basename "$root")")" = "$norm" ]; then
            FOUND_LINES+=("manual|$(basename "$root")|manual install: $exec_path|$root")
        fi
    done

    return 0
}

# Fully remove a directory install: symlinks + desktop files + registry
remove_dir_app() {   # $1=install root  $2=app name
    local dir="$1" name="$2"

    # Sensitive paths can never be removed
    case "$dir" in
        ""|"/"|"/opt"|"$HOME"|"$HOME"/)
            failure "Invalid removal path: $dir"
            return 1
            ;;
    esac

    # Remove /usr/local/bin symlinks pointing into this directory
    local l target removed_links=0
    for l in /usr/local/bin/*; do
        [ -L "$l" ] || continue
        target=$(readlink -f "$l" 2>/dev/null)
        if [ -n "$target" ] && { [ "$target" = "$dir" ] || [[ "$target" == "$dir"/* ]]; }; then
            sudo rm -f "$l"
            removed_links=$((removed_links + 1))
        fi
    done

    # Remove desktop files pointing to this path
    local f
    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        if grep -qF "$dir/" "$f" 2>/dev/null; then
            if [[ "$f" == "$HOME"/* ]]; then rm -f "$f"; else sudo rm -f "$f"; fi
        fi
    done

    if [ -d "$dir" ]; then
        sudo rm -rf "$dir"
    else
        info "$dir does not exist (maybe already removed)."
    fi

    registry_remove "$name"
    success "App removed: $dir"
    [ "$removed_links" -gt 0 ] && info "$removed_links shortcut(s) removed from /usr/local/bin."
    return 0
}

# Find and remove user data (config/cache/share)
offer_user_data_cleanup() {   # $1=app name
    local raw="$1"
    local -a dirs=()
    local base d pat

    # mindepth=1: the base dirs themselves (e.g. ~/.local/share) never match the pattern
    # The input name is escaped so glob characters cannot alter the pattern
    pat=$(_glob_escape "$raw")
    for base in "$HOME/.config" "$HOME/.local/share" "$HOME/.cache"; do
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -iname "${pat}*" 2>/dev/null)
    done

    # Flatpak data
    if [ -d "$HOME/.var/app" ]; then
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$HOME/.var/app" -mindepth 1 -maxdepth 1 -type d -iname "*${pat}*" 2>/dev/null)
    fi

    # Known app data paths
    case "${raw,,}" in
        firefox|firefox-esr)
            for d in "$HOME/.mozilla" "$HOME/.cache/mozilla" \
                     "$HOME/.config/firefox" "$HOME/.cache/firefox"; do
                [ -d "$d" ] && dirs+=("$d")
            done
            ;;
        thunderbird)
            [ -d "$HOME/.thunderbird" ] && dirs+=("$HOME/.thunderbird")
            ;;
        nodejs|npm)
            for d in "$HOME/.npm" "$HOME/.cache/npm"; do
                [ -d "$d" ] && dirs+=("$d")
            done
            ;;
    esac

    # Global npm packages — system-wide, needs sudo
    if [[ "${raw,,}" == "nodejs" || "${raw,,}" == "npm" ]] && [ -d /usr/lib/node_modules ]; then
        info "Global npm packages: /usr/lib/node_modules"
        if [ "$PURGE_DATA" = "1" ] || confirm_action "Remove the global npm packages too?"; then
            sudo rm -rf /usr/lib/node_modules
            success "Global npm packages removed."
        else
            info "Global npm packages kept."
        fi
    fi

    if [ ${#dirs[@]} -eq 0 ]; then
        info "No related user data found."
        return 0
    fi

    info "This user data was found:"
    printf '      • %s\n' "${dirs[@]}"
    if [ "$PURGE_DATA" = "1" ] || confirm_action "Remove these directories too?"; then
        rm -rf "${dirs[@]}"
        success "User data removed."
    else
        info "User data kept."
    fi
    return 0
}

# Fully remove an app from any source — interactive or via CLI --cleanup
cleanup_app() {   # $1 optional = app name
    header "🧹 Fully Remove an App"

    local raw
    if [ -n "${1:-}" ]; then
        raw="$1"
    else
        # EOF (Ctrl+D) → cancel
        read -r -p "   App name (e.g. abdownloadmanager or firefox): " raw || return 1
    fi
    [ -z "$raw" ] && { failure "No name entered."; return 1; }

    find_app_instances "$raw"
    if [ ${#FOUND_LINES[@]} -eq 0 ]; then
        failure "No app named '$raw' found in any source."
        info "Sources searched: apt, snap, flatpak, tar.gz registry, /opt and desktop files"
        return 1
    fi

    info "These items were found:"
    local i line typ id desc extra
    i=1
    for line in "${FOUND_LINES[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        echo "   $i) [$typ] $id — $desc"
        i=$((i + 1))
    done
    echo "   a) Remove all of the above"
    echo "   0) Cancel"
    echo ""

    local sel
    if [ "$CLI_MODE" = "1" ] && [ "$ASSUME_YES" = "1" ]; then
        sel="a"
        info "(auto-selecting all items with -y)"
    else
        # EOF (Ctrl+D) → cancel
        read -r -p "   Which one to remove? (number / comma-separated numbers / a / 0): " sel || sel="0"
    fi
    if [ -z "$sel" ] || [ "$sel" = "0" ]; then
        info "Cancelled."
        return 0
    fi

    local -a todo=()
    if [ "${sel,,}" = "a" ]; then
        todo=("${FOUND_LINES[@]}")
    else
        local s
        local -a parts=()
        IFS=',' read -ra parts <<< "$sel"
        for s in "${parts[@]}"; do
            s=$(printf '%s' "$s" | tr -d ' ')
            if [[ "$s" =~ ^[0-9]+$ ]] && [ "$s" -ge 1 ] && [ "$s" -le ${#FOUND_LINES[@]} ]; then
                todo+=("${FOUND_LINES[$((s-1))]}")
            fi
        done
    fi
    [ ${#todo[@]} -eq 0 ] && { failure "Invalid selection."; return 1; }

    echo ""
    warn "These items will be removed:"
    for line in "${todo[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        echo "      • [$typ] $id"
    done
    if ! confirm_action "Are you sure?"; then
        info "Cancelled."
        return 0
    fi

    local any_apt=0 had_fail=0
    for line in "${todo[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        case "$typ" in
            apt)
                info "Removing deb package: $id"
                if sudo apt purge -y "$id" > /dev/null 2>&1; then
                    success "$id removed."
                    any_apt=1
                else
                    failure "Failed to remove $id"
                    had_fail=1
                fi
                ;;
            snap)
                info "Removing snap: $id"
                if sudo snap remove --purge "$id" > /dev/null 2>&1; then
                    success "$id removed."
                else
                    failure "Failed to remove snap $id"
                    had_fail=1
                fi
                ;;
            flatpak)
                info "Removing flatpak: $id"
                if flatpak uninstall -y --delete-data "$id" > /dev/null 2>&1; then
                    success "$id removed."
                else
                    failure "Failed to remove flatpak $id"
                    had_fail=1
                fi
                ;;
            targz)
                info "Removing from $extra"
                remove_dir_app "$extra" "$id" || had_fail=1
                ;;
            opt)
                info "Removing from /opt/$id"
                remove_dir_app "/opt/$id" "$id" || had_fail=1
                ;;
            manual)
                info "Removing from $extra"
                remove_dir_app "$extra" "$(basename "$extra")" || had_fail=1
                ;;
        esac
    done

    if [ "$any_apt" = "1" ]; then
        info "Cleaning unused dependencies (autoremove)..."
        sudo apt autoremove -y > /dev/null 2>&1
    fi
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1

    echo ""
    info "Checking for leftover user data..."
    offer_user_data_cleanup "$raw"
    if [ "$had_fail" = "1" ]; then
        warn "Finished, but some items could not be removed."
    else
        success "Removal complete."
    fi
    return 0
}

# Clean leftover configs of removed deb packages (dpkg rc state)
cleanup_deb_residuals() {
    header "Clean Leftover deb Configs"
    local -a rc=()
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && rc+=("$p")
    done < <(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')

    if [ ${#rc[@]} -eq 0 ]; then
        success "No leftover configs."
        return 0
    fi

    info "${#rc[@]} removed packages still have configs:"
    printf '      • %s\n' "${rc[@]}" | head -30
    [ ${#rc[@]} -gt 30 ] && echo "      ... and $((${#rc[@]} - 30)) more"

    confirm_action "Purge all of them?" || { info "Cancelled."; return 0; }
    if sudo apt purge -y "${rc[@]}" > /dev/null 2>&1; then
        success "Leftover configs purged."
    else
        failure "Purge failed — inspect with: dpkg -l | grep ^rc"
    fi
    return 0
}

# Remove desktop files that point to a non-existent program
cleanup_desktop_orphans() {
    header "Check for Orphan Desktop Files"
    local -a orphans=()
    local f exec_path

    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        exec_path=$(_desktop_exec_path "$f")
        [ -z "$exec_path" ] && continue
        if [[ "$exec_path" == /* ]]; then
            [ -e "$exec_path" ] || orphans+=("$f")
        else
            command -v "$exec_path" > /dev/null 2>&1 || orphans+=("$f")
        fi
    done

    if [ ${#orphans[@]} -eq 0 ]; then
        success "No orphan desktop files."
        return 0
    fi

    info "These files point to a non-existent program:"
    printf '      • %s\n' "${orphans[@]}"
    if ! confirm_action "Remove all of them?"; then
        info "Cancelled."
        return 0
    fi
    for f in "${orphans[@]}"; do
        if [[ "$f" == "$HOME"/* ]]; then rm -f "$f"; else sudo rm -f "$f"; fi
    done
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1
    success "${#orphans[@]} desktop file(s) removed."
    return 0
}

# List all apps from all sources
list_all_apps() {
    header "Installed Apps (All Sources)"

    local rname rn out d bn owner bnn isreg found found_deb
    local -a reg_names=() manual_dirs=()
    if [ -s "$REGISTRY_DB" ]; then
        while IFS='|' read -r rname _; do
            [ -n "$rname" ] && reg_names+=("$(normalize_name "$rname")")
        done < "$REGISTRY_DB"
    fi

    echo -e "${BOLD}── Installed by this script (tar.gz / registry) ──${NC}"
    if [ -s "$REGISTRY_DB" ]; then
        awk -F'|' '{printf "   %-24s %-12s %s\n", $1, ($2 == "" ? "-" : $2), $3}' "$REGISTRY_DB"
    else
        echo "   (empty)"
    fi
    echo ""

    echo -e "${BOLD}── deb apps installed in /opt ──${NC}"
    found_deb=0
    for d in /opt/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        bn=$(basename "$d")
        owner=$(deb_owner_of "$d")
        if [ -n "$owner" ]; then
            echo "   $bn  →  deb package: $owner  (remove via apt)"
            found_deb=1
        else
            manual_dirs+=("$bn")
        fi
    done
    [ "$found_deb" = "0" ] && echo "   (empty)"
    echo ""

    echo -e "${BOLD}── Manual installs in /opt (no registry, no deb package) ──${NC}"
    found=0
    for bn in "${manual_dirs[@]}"; do
        bnn=$(normalize_name "$bn")
        isreg=0
        for rn in "${reg_names[@]}"; do
            [ "$rn" = "$bnn" ] && { isreg=1; break; }
        done
        [ "$isreg" = "1" ] && continue
        echo "   $bn  →  /opt/$bn"
        found=1
    done
    [ "$found" = "0" ] && echo "   (empty)"
    echo ""

    echo -e "${BOLD}── snap ──${NC}"
    if command -v snap > /dev/null 2>&1; then
        out=$(snap list 2>/dev/null)
        if [ -n "$out" ]; then
            # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
            echo "$out" | sed 's/^/   /'
        else
            echo "   (no snaps installed)"
        fi
    else
        echo "   (snap is not installed)"
    fi
    echo ""

    echo -e "${BOLD}── flatpak ──${NC}"
    if command -v flatpak > /dev/null 2>&1; then
        out=$(flatpak list --app 2>/dev/null)
        if [ -n "$out" ]; then
            # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
            echo "$out" | sed 's/^/   /'
        else
            echo "   (no flatpak apps installed)"
        fi
    else
        echo "   (flatpak is not installed)"
    fi
    echo ""

    echo -e "${BOLD}── Latest apt-installed packages ──${NC}"
    if [ -f /var/log/dpkg.log ]; then
        grep " install " /var/log/dpkg.log 2>/dev/null \
            | awk '{sub(/:.*/, "", $4); print $4}' \
            | grep -viE '^(lib|python|perl|fonts|language|gcc|binutils|dpkg|install-info|adduser|passwd)' \
            | tail -15 | sed 's/^/   /'
    else
        echo "   (apt log unavailable)"
    fi
    return 0
}
