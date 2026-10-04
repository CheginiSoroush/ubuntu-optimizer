# shellcheck shell=bash
# ============================================================
#   lib/snapflatpak.sh — snap/flatpak management and updates
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

snap_list_apps() {
    header "List Snap Apps"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap is not installed on this system."
        return 0
    fi
    local out
    out=$(snap list 2>/dev/null)
    if [ -n "$out" ]; then
        # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
        echo "$out" | sed 's/^/   /'
    else
        echo "   (no snaps installed)"
    fi
    return 0
}

update_snap() {
    header "Update All Snaps"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap is not installed on this system."
        return 0
    fi
    if sudo snap refresh; then
        success "All snaps updated."
        return 0
    else
        failure "Failed to update snaps."
        info "If an app is running (e.g. snap-store), close it and try again."
        return 1
    fi
}

snap_install_app() {
    header "Install a Snap"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap is not installed on this system."
        return 0
    fi
    local name
    # EOF (Ctrl+D) → cancel
    read -r -p "   Snap name (e.g. spotify): " name || return 1
    [ -z "$name" ] && { failure "No name entered."; return 1; }
    if sudo snap install "$name"; then
        success "Snap installed."
        return 0
    else
        failure "Failed to install the snap."
        info "If the app needs classic confinement: sudo snap install $name --classic"
        return 1
    fi
}

snap_remove_app() {
    header "Remove a Snap"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap is not installed on this system."
        return 0
    fi
    local name
    # EOF (Ctrl+D) → cancel
    read -r -p "   Snap name to remove: " name || return 1
    [ -z "$name" ] && { failure "No name entered."; return 1; }
    # Exact fixed-string match (-F) — the input name is not a regex
    if ! snap list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qxF "$name"; then
        failure "This snap is not installed."
        return 1
    fi
    confirm_action "Fully remove snap '$name'?" || { info "Cancelled."; return 0; }
    if sudo snap remove --purge "$name"; then
        success "Removed."
        return 0
    else
        failure "Failed to remove."
        return 1
    fi
}

snap_clean_revisions() {
    header "Clean Old Snap Revisions (Reclaim Disk Space)"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap is not installed on this system."
        return 0
    fi
    local disabled
    disabled=$(snap list --all 2>/dev/null | awk '/disabled/ {print $1" "$3}')
    if [ -z "$disabled" ]; then
        success "No old snap revisions to remove."
        return 0
    fi
    local count
    count=$(echo "$disabled" | wc -l)
    info "These old revisions can be removed:"
    # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
    echo "$disabled" | sed 's/^/      • /'
    if ! confirm_action "Remove $count revision(s)?"; then
        info "Cancelled."
        return 0
    fi
    local name rev had_fail=0
    while read -r name rev; do
        [ -z "$name" ] && continue
        if sudo snap remove "$name" --revision="$rev" > /dev/null 2>&1; then
            success "$name (revision $rev) removed."
        else
            failure "Failed to remove $name revision $rev."
            had_fail=1
        fi
    done <<< "$disabled"
    [ "$had_fail" = "1" ] && warn "Some revisions could not be removed."
    return 0
}

flatpak_list_apps() {
    header "List Flatpak Apps"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak is not installed on this system."
        return 0
    fi
    local out
    out=$(flatpak list --app 2>/dev/null)
    if [ -n "$out" ]; then
        # shellcheck disable=SC2001  # sed is the right tool for prefixing multi-line output
        echo "$out" | sed 's/^/   /'
    else
        echo "   (no flatpak apps installed)"
    fi
    return 0
}

update_flatpak() {
    header "Update All Flatpaks"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak is not installed on this system."
        return 0
    fi
    if flatpak update -y; then
        success "All flatpaks updated."
        return 0
    else
        failure "Failed to update flatpaks."
        info "In an SSH session polkit may deny access — run from the desktop."
        return 1
    fi
}

flatpak_install_app() {
    header "Install a Flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak is not installed on this system."
        return 0
    fi
    local id
    # EOF (Ctrl+D) → cancel
    read -r -p "   App ID (e.g. org.mozilla.firefox): " id || return 1
    [ -z "$id" ] && { failure "No ID entered."; return 1; }
    if flatpak install -y flathub "$id"; then
        success "Flatpak installed."
        return 0
    else
        failure "Failed to install the flatpak."
        info "If the flathub remote is missing:"
        info "  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
        return 1
    fi
}

flatpak_remove_app() {
    header "Remove a Flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak is not installed on this system."
        return 0
    fi
    local id
    # EOF (Ctrl+D) → cancel
    read -r -p "   App ID to remove: " id || return 1
    [ -z "$id" ] && { failure "No ID entered."; return 1; }
    # Exact fixed-string match (-F)
    if ! flatpak list --app --columns=application 2>/dev/null | grep -qxF "$id"; then
        failure "This flatpak app is not installed."
        return 1
    fi
    confirm_action "Remove '$id' including its data?" || { info "Cancelled."; return 0; }
    if flatpak uninstall -y --delete-data "$id"; then
        success "Removed."
        return 0
    else
        failure "Failed to remove."
        return 1
    fi
}

flatpak_clean_unused() {
    header "Clean Unused Flatpak Runtimes and Packages"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak is not installed on this system."
        return 0
    fi
    if flatpak uninstall --unused -y; then
        success "Cleanup complete."
        return 0
    else
        failure "Cleanup failed."
        return 1
    fi
}

clean_snap_flatpak_junk() {
    snap_clean_revisions
    flatpak_clean_unused
}

# ============================================================
#   App updates
# ============================================================

update_apt() {
    header "Update apt (System & deb Packages)"
    info "Checking for updates..."
    sudo apt update || { failure "apt update failed."; return 1; }
    # In -y mode, dpkg questions (config file conflicts) get the default answer
    local -a upgrade_cmd=(apt upgrade -y)
    [ "$ASSUME_YES" = "1" ] && upgrade_cmd=(env DEBIAN_FRONTEND=noninteractive apt upgrade -y)
    if ! sudo "${upgrade_cmd[@]}"; then
        failure "Failed to upgrade packages."
        return 1
    fi
    success "apt update complete."
    info "Cleaning unused dependencies (autoremove)..."
    sudo apt autoremove -y > /dev/null 2>&1
    return 0
}

# Check tar.gz app updates — Downloads scan + manual path/URL
# Self-healing: version-less entries whose path matches another (versioned)
# entry are removed before the scan.
# GitHub-tracked apps are skipped here: the GitHub flow checks them online.
update_targz_apps() {
    header "Check tar.gz App Updates"

    if [ ! -s "$REGISTRY_DB" ]; then
        info "No apps are registered yet."
        info "Apps installed with older script versions have no registry entry;"
        info "reinstall them once to enable update tracking."
        return 0
    fi

    # Stale-entry self-healing
    local -a db_lines=()
    mapfile -t db_lines < "$REGISTRY_DB"
    local l n1 v1 d1 n2 v2 d2 i clean_removed=0
    for l in "${db_lines[@]}"; do
        IFS='|' read -r n1 v1 d1 <<< "$l"
        [ -z "$v1" ] || continue
        for i in "${!db_lines[@]}"; do
            IFS='|' read -r n2 v2 d2 <<< "${db_lines[$i]}"
            if [ -n "$v2" ] && [ "$d2" = "$d1" ]; then
                info "Stale entry '$n1' (no version, duplicate path) removed."
                registry_remove "$n1"
                clean_removed=1
                break
            fi
        done
    done
    [ "$clean_removed" = "1" ] && mapfile -t db_lines < "$REGISTRY_DB"

    # Full db snapshot before the loop — interactive reads must not
    # consume the file's own lines, and rewriting the db mid-loop
    # (while installing a new version) stays safe
    local -a reg_lines=()
    mapfile -t reg_lines < "$REGISTRY_DB"

    local line name ver dir sel f idx j mark
    for line in "${reg_lines[@]}"; do
        IFS='|' read -r name ver dir _ <<< "$line"
        [ -z "$name" ] && continue

        # Self-healing: drop entries whose install directory no longer exists
        if [ ! -d "$dir" ]; then
            warn "'$name': install directory missing ($dir) — registry entry removed."
            registry_remove "$name"
            continue
        fi

        # GitHub-tracked apps are fully managed by the GitHub update flow —
        # their online check and install happen in the GitHub section
        if gh_db_has "$name"; then
            info "App: $name — GitHub-tracked; handled by the GitHub update check."
            continue
        fi

        echo ""
        info "App: $name (version: $( [ -n "$ver" ] && echo "$ver" || echo "unknown")) → $dir"

        # Scan the Downloads folder for a new version (tar.gz and tgz)
        local -a match=() mver=()
        local sname fbase fpath
        sname=$(normalize_name "$name")
        while IFS= read -r fpath; do
            [ -f "$fpath" ] || continue
            fbase=$(name_from_archive "$fpath")
            if [[ "$fbase" == *"$sname"* ]] || [[ "$sname" == *"$fbase"* ]]; then
                match+=("$fpath")
                mver+=("$(guess_version "$fpath")")
            fi
        done < <(find "$HOME/Downloads" -maxdepth 1 -type f \
                    \( -iname "*.tar.gz" -o -iname "*.tgz" \) 2>/dev/null)

        if [ ${#match[@]} -gt 0 ]; then
            info "These files were found in Downloads:"
            j=1
            for idx in "${!match[@]}"; do
                mark=""
                if [ -n "${mver[$idx]}" ] && [ "${mver[$idx]}" != "$ver" ]; then
                    mark="  → version ${mver[$idx]}"
                fi
                echo "   $j) $(basename "${match[$idx]}")$mark"
                j=$((j + 1))
            done
        else
            info "No new file for this app in ~/Downloads."
        fi

        # Automatic mode (-y in CLI): no questions — the first file with a different version is installed
        if [ "$CLI_MODE" = "1" ] && [ "$ASSUME_YES" = "1" ]; then
            local auto_file="" auto_idx=-1
            for idx in "${!match[@]}"; do
                if [ -n "${mver[$idx]}" ] && [ "${mver[$idx]}" != "$ver" ]; then
                    auto_file="${match[$idx]}"
                    auto_idx=$idx
                    break
                fi
            done
            if [ -n "$auto_file" ]; then
                info "New version ${mver[$auto_idx]} found — installing automatically."
                targz_install_from_file "$auto_file" "$name"
            else
                info "Skipped."
            fi
            continue
        fi

        echo "   m) I will provide the new file path or download URL myself"
        echo "   Enter) Skip this app"

        # EOF (Ctrl+D) → skip
        read -r -p "   Select: " sel || sel=""
        if [ "${sel,,}" = "m" ]; then
            read -r -p "   File path or URL: " f || f=""
            f=${f/#\~/$HOME}
            if [[ "$f" == http* ]]; then
                if ! command -v curl > /dev/null 2>&1; then
                    failure "curl is not installed (sudo apt install curl)."
                    continue
                fi
                local dl
                dl="$HOME/Downloads/$(basename "$f")"
                info "Downloading $f ..."
                if curl -fL --progress-bar -o "$dl" "$f"; then
                    f="$dl"
                else
                    failure "Download failed."
                    continue
                fi
            fi
            [ -f "$f" ] || { failure "File not found."; continue; }
            targz_install_from_file "$f" "$name"
        elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#match[@]} ]; then
            targz_install_from_file "${match[$((sel-1))]}" "$name"
        else
            info "Skipped."
        fi
    done
    return 0
}

# Update all sources
update_all() {
    header "🔄 Update Everything (apt + snap + flatpak + tar.gz + github)"
    local had_fail=0
    update_apt        || had_fail=1
    update_snap       || had_fail=1
    update_flatpak    || had_fail=1
    update_targz_apps || had_fail=1
    github_update_apps || had_fail=1
    echo ""
    if [ "$had_fail" = "1" ]; then
        warn "The update cycle finished but some steps had errors."
    else
        success "Update cycle complete."
    fi
    return 0
}
