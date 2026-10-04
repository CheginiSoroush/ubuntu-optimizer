# shellcheck shell=bash
# ============================================================
#   lib/github.sh — install & update apps from GitHub Releases
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   Install flow: pre-auth sudo → fetch the latest release → automatic
#   asset pick → temporary download → install → register in github.db →
#   cleanup. Updates: one question per app; after confirmation everything
#   else is automatic.
# ============================================================

readonly GITHUB_DB="$REGISTRY_DIR/github.db"

# ---------- GitHub app database ----------
# Line format: name|owner/repo|installed_tag

# The db is rewritten through a temp file; on an awk failure the original
# file is left untouched (never replaced by an empty file).
gh_db_add() {   # $1=name $2=repo $3=tag
    mkdir -p "$REGISTRY_DIR"
    touch "$GITHUB_DB"
    local tmp="$GITHUB_DB.tmp"
    if awk -F'|' -v n="$1" '$1 != n' "$GITHUB_DB" > "$tmp" 2>/dev/null; then
        printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$tmp"
        mv "$tmp" "$GITHUB_DB"
    else
        rm -f "$tmp"
        return 1
    fi
}

gh_db_remove() {   # $1=name
    [ -f "$GITHUB_DB" ] || return 0
    local tmp="$GITHUB_DB.tmp"
    if awk -F'|' -v n="$1" '$1 != n' "$GITHUB_DB" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$GITHUB_DB"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Is the app registered in the GitHub database? — exact field match
gh_db_has() {   # $1=name
    [ -f "$GITHUB_DB" ] || return 1
    awk -F'|' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$GITHUB_DB" 2>/dev/null
}

# Build the curl auth arguments from GH_TOKEN / GITHUB_TOKEN (if set).
# A token raises the API rate limit from 60/hour (per IP) to 5000/hour
# (per token). Auth is only sent to api.github.com — release asset
# downloads stay anonymous (they are not rate-limited).
gh_set_auth() {
    GH_CURL_AUTH=()
    if [ -n "${GH_TOKEN:-}" ]; then
        GH_CURL_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        GH_CURL_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    return 0
}

# ---------- Fetch the latest release ----------
# Output: GH_TAG (version) and the GH_URLS array (asset URLs)
gh_fetch_latest() {   # $1 = OWNER/REPO or a full URL
    GH_TAG=""
    GH_URLS=()

    if ! command -v curl > /dev/null 2>&1; then
        info "Installing curl..."
        sudo apt install -y curl > /dev/null 2>&1 || { failure "Failed to install curl."; return 1; }
    fi

    local repo="$1" resp
    repo=${repo#https://github.com/}
    repo=${repo#git@github.com:}
    repo=${repo%/}
    repo=${repo%.git}

    if ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        failure "Invalid repository format: '$repo'"
        info "Correct format: OWNER/REPO or https://github.com/OWNER/REPO"
        return 1
    fi

    gh_set_auth

    info "Checking the latest release of $repo ..."
    # stderr is kept separate so a curl failure shows as an empty response, not broken JSON
    if ! resp=$(curl -sSL --connect-timeout 15 --max-time 30 "${GH_CURL_AUTH[@]}" \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || [ -z "$resp" ]; then
        failure "Failed to get a response from the GitHub API — check your internet connection."
        return 1
    fi

    # Errors are matched on the API's "message" field only — release notes
    # (the "body" field) may legitimately contain words like "rate limit"
    if printf '%s' "$resp" | grep -q '"message": *"Bad credentials"'; then
        failure "GitHub rejected the token (Bad credentials) — check GH_TOKEN / GITHUB_TOKEN."
        return 1
    fi
    if printf '%s' "$resp" | grep -q '"message": *"Not Found"'; then
        failure "Repository not found or has no public release (404)."
        info "Check the repository name: $repo"
        return 1
    fi
    if printf '%s' "$resp" | grep -qi '"message": *"API rate limit exceeded'; then
        warn "GitHub API rate limit reached (60 requests/hour per IP without a token)."
        info "Tip: setting GH_TOKEN raises the limit to 5000/hour — see the README."
        return 1
    fi

    if command -v jq > /dev/null 2>&1; then
        GH_TAG=$(printf '%s' "$resp" | jq -r '.tag_name // empty')
        mapfile -t GH_URLS < <(printf '%s' "$resp" | jq -r '.assets[].browser_download_url' 2>/dev/null)
    else
        GH_TAG=$(printf '%s' "$resp" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
        mapfile -t GH_URLS < <(printf '%s' "$resp" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*: *"//; s/"$//')
    fi

    if [ -z "$GH_TAG" ]; then
        failure "The API response could not be parsed (private repository?)."
        return 1
    fi
    return 0
}

# ---------- Automatic asset pick ----------
# Scoring:
#   matching arch +40 | deb format +10 | AppImage +8 | tar.gz/tgz +5
#   no arch tag -15   | musl -8        | incompatible arch -200
# The highest score wins; on a tie the first file.
gh_pick_asset() {
    GH_PICKED_URL=""
    local sys_arch
    sys_arch=$(uname -m)

    local -a urls=() scores=()
    local u f low score best i

    for u in "${GH_URLS[@]}"; do
        f=$(basename "$u")
        low=${f,,}
        score=0

        # Format — $low is lowercase, so every pattern here must be lowercase too
        case "$low" in
            *.deb)          score=$((score + 10)) ;;
            *.appimage)     score=$((score + 8)) ;;
            *.tar.gz|*.tgz) score=$((score + 5)) ;;
            *)              continue ;;
        esac

        # OS filter — non-Linux builds are never eligible
        case "$low" in
            *darwin*|*macos*|*osx*|*apple*|*windows*|*win32*|*win64*|*mingw*|*cygwin*|*freebsd*)
                continue
                ;;
        esac

        # Architecture
        if [ "$sys_arch" = "x86_64" ]; then
            case "$low" in
                *amd64*|*x86_64*|*x64*)     score=$((score + 40)) ;;
                *i386*|*i686*|*80386*|*x86*) score=$((score + 20)) ;;
                *arm64*|*aarch64*|*armv5*|*armv6*|*armv7*|*arm*|*riscv64*|*ppc64le*|*s390x*|*loong64*) score=$((score - 200)) ;;
                *)                          score=$((score - 15)) ;;
            esac
        elif [ "$sys_arch" = "aarch64" ]; then
            case "$low" in
                *arm64*|*aarch64*)           score=$((score + 40)) ;;
                *armv5*|*armv6*|*armv7*|*arm*) score=$((score + 20)) ;;
                *amd64*|*x86_64*|*x64*|*i386*|*i686*|*riscv64*|*ppc64le*|*s390x*|*loong64*) score=$((score - 200)) ;;
                *)                           score=$((score - 15)) ;;
            esac
        else
            case "$low" in
                *arm64*|*aarch64*|*amd64*|*x86_64*|*x64*|*armv5*|*armv6*|*armv7*|*riscv64*|*ppc64le*|*s390x*|*loong64*)
                    score=$((score - 200)) ;;
            esac
        fi

        [[ "$low" == *musl* ]] && score=$((score - 8))
        [ "$score" -le -100 ] && continue

        urls+=("$u")
        scores+=("$score")
    done

    if [ ${#urls[@]} -eq 0 ]; then
        failure "No compatible installable file found."
        info "Assets of this release (for manual inspection/install):"
        for u in "${GH_URLS[@]}"; do
            echo "      • $(basename "$u")"
        done
        return 1
    fi

    best=0
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" -gt "${scores[$best]}" ] && best=$i
    done
    local -a ties=()
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" = "${scores[$best]}" ] && ties+=("$i")
    done
    [ ${#ties[@]} -gt 1 ] && info "(multiple equally-scored files — picked the first)"

    GH_PICKED_URL="${urls[$best]}"
    return 0
}

# ---------- Download, install, register and clean up ----------
gh_download_and_install() {   # $1=url $2=name $3=repo $4=tag
    local url="$1" name="$2" repo="$3" tag="$4"
    local base ext d tmpfile installed=0

    base=$(basename "$url")
    # ${base,,} is lowercase — the AppImage pattern must be lowercase as well
    case "${base,,}" in
        *.deb)      ext=".deb" ;;
        *.tgz)      ext=".tgz" ;;
        *.appimage) ext=".AppImage" ;;
        *)          ext=".tar.gz" ;;
    esac

    # Authenticate sudo BEFORE the download — the password is requested up
    # front (while the user is attentive), with a 10-minute prompt timeout.
    # A cached ticket skips the prompt entirely.
    sudo_precheck 600 || return 1

    # Download into a mktemp dir — a predictable /tmp path is a symlink risk;
    # the original file name is kept so version detection still works
    d=$(mktemp -d) || return 1
    tmpfile="$d/$base"

    info "Downloading $base ..."
    if ! curl -fL --connect-timeout 15 --progress-bar -o "$tmpfile" "$url"; then
        failure "Download failed."
        rm -rf "$d"
        return 1
    fi
    success "Download complete."

    if [ "$ext" = ".AppImage" ]; then
        info "Installing AppImage..."
        UO_AUTO=1
        if appimage_install_from_file "$tmpfile" "$name"; then
            installed=1
        fi
        unset UO_AUTO
    elif [ "$ext" = ".deb" ]; then
        info "Installing the deb package..."
        if sudo apt install -y "$tmpfile" > /dev/null 2>&1; then
            installed=1
        else
            warn "apt install failed; trying dpkg..."
            if sudo dpkg -i "$tmpfile" 2>/dev/null; then
                sudo apt --fix-broken install -y > /dev/null 2>&1
                installed=1
            fi
        fi
    else
        # tar.gz install in automatic mode — no interactive questions
        UO_AUTO=1
        if targz_install_from_file "$tmpfile" "$name"; then
            installed=1
        fi
        unset UO_AUTO
    fi

    if [ "$installed" = "1" ]; then
        gh_db_add "$name" "$repo" "$tag"
        rm -rf "$d"
        success "Downloaded file removed: $tmpfile"
        return 0
    fi

    # Install failed — keep the downloaded file in ~/Downloads (a findable,
    # persistent location) instead of a random mktemp dir, and print the
    # exact retry command
    local kept=""
    if [ -f "$tmpfile" ]; then
        mkdir -p "$HOME/Downloads"
        if mv -f "$tmpfile" "$HOME/Downloads/$base" 2>/dev/null; then
            kept="$HOME/Downloads/$base"
        fi
        rm -rf "$d"
    fi
    if [ -n "$kept" ]; then
        failure "Install failed — the downloaded file is kept: $kept"
        case "$ext" in
            .deb)      info "Retry: sudo apt install \"$kept\"" ;;
            .AppImage) info "Retry: uo menu → Install packages → Install from AppImage file" ;;
            *)         info "Retry: uo --install-targz \"$kept\" \"$name\"" ;;
        esac
    else
        failure "Install failed — the downloaded file is kept for inspection: $tmpfile"
    fi
    return 1
}

# ---------- Install an app from GitHub (fully automatic) ----------
github_install_repo() {   # $1=repo (optional in the menu)  $2=optional name
    header "🐙 Install an App from GitHub"

    local repo="$1" name="$2"

    if [ -z "$repo" ]; then
        read -r -p "   Repository (OWNER/REPO or a full github.com/OWNER/REPO link): " repo || return 1
    fi
    [ -z "$repo" ] && { failure "No repository entered."; return 1; }

    repo=${repo#https://github.com/}
    repo=${repo#git@github.com:}
    repo=${repo%/}
    repo=${repo%.git}

    if ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        failure "Invalid repository format: '$repo'"
        info "Correct example: amir1376/ab-download-manager"
        return 1
    fi

    if [ -z "$name" ]; then
        name=$(basename "$repo")
        info "App name (from the repo): $name"
    fi

    if ! gh_fetch_latest "$repo"; then
        return 1
    fi
    info "Latest version: $GH_TAG"

    if ! gh_pick_asset; then
        return 1
    fi
    info "Selected file: $(basename "$GH_PICKED_URL")"

    gh_download_and_install "$GH_PICKED_URL" "$(sanitize_app_name "$name")" "$repo" "$GH_TAG"
}

# ---------- Remove a GitHub app ----------
# Removes the app from the system (all sources, via cleanup_app) and drops
# the GitHub db entry. cleanup_app removes the entry itself when the app is
# fully gone; the still-installed check below covers cancelled/partial
# removals (the entry is then kept for the update self-heal).
github_remove_app() {   # $1 optional = app name
    header "🐙 Remove a GitHub App"

    local raw
    if [ -n "${1:-}" ]; then
        raw="$1"
    else
        if [ -s "$GITHUB_DB" ]; then
            info "Tracked apps:"
            awk -F'|' '{printf "      • %s (%s) ← %s\n", $1, $3, $2}' "$GITHUB_DB"
            echo ""
        fi
        read -r -p "   App name to remove: " raw || return 1
    fi
    [ -z "$raw" ] && { failure "No name entered."; return 1; }

    if ! gh_db_has "$raw"; then
        failure "No app named '$raw' in the GitHub list."
        info "Current list: uo --github-list"
        return 1
    fi

    # A stale entry (the app is not installed anywhere) is removed directly —
    # running the full cleanup flow would only report "not found" errors
    if ! app_still_installed "$raw"; then
        gh_db_remove "$raw"
        success "Stale entry removed: $raw is not installed anywhere."
        return 0
    fi

    # Remove the app from the system — all sources, with user data
    cleanup_app "$raw"

    # Verify actual removal (cleanup may have been cancelled)
    if app_still_installed "$raw"; then
        warn "The app was not removed (or was cancelled) — the GitHub entry is kept."
        return 1
    fi

    gh_db_remove "$raw"
    success "Entry '$raw' removed from the GitHub tracking list."
    return 0
}

# ---------- Update check ----------
# One question per app: "update?" — after confirmation the download
# and install are automatic; declining moves on to the next app
github_update_apps() {
    header "🔄 Check GitHub App Updates"

    if [ ! -s "$GITHUB_DB" ]; then
        info "No GitHub apps installed/tracked yet."
        info "Install with: uo --github-install OWNER/REPO"
        return 0
    fi

    # Full snapshot of the db before the loop — interactive reads must not
    # consume the file's own lines
    local -a lines=()
    mapfile -t lines < "$GITHUB_DB"

    local line name repo tag latest
    for line in "${lines[@]}"; do
        IFS='|' read -r name repo tag <<< "$line"
        [ -z "$name" ] && continue

        echo ""
        info "App: $name (installed: ${tag:-unknown}) ← $repo"

        # Self-healing: uninstalled apps are dropped from the tracking list
        if ! app_still_installed "$name"; then
            warn "This app is no longer installed — removed from the tracking list."
            gh_db_remove "$name"
            continue
        fi

        if ! gh_fetch_latest "$repo"; then
            warn "Failed to fetch info for $repo — skipped."
            continue
        fi
        latest=$GH_TAG

        if [ "${latest#v}" = "${tag#v}" ]; then
            success "Up to date ($latest)."
            continue
        fi

        info "New version available: $latest (current: ${tag:-unknown})"
        if ! confirm_action "Update '$name' to $latest?"; then
            info "Declined — continuing with the next app."
            continue
        fi

        if ! gh_pick_asset; then
            continue
        fi
        gh_download_and_install "$GH_PICKED_URL" "$name" "$repo" "$latest"
    done
    return 0
}

# ---------- List GitHub apps ----------
github_list_apps() {
    header "🐙 Tracked GitHub Apps"
    if [ ! -s "$GITHUB_DB" ]; then
        info "(empty) — install with: uo --github-install OWNER/REPO"
        return 0
    fi
    awk -F'|' '{printf "   %-24s %-14s %s\n", $1, ($3 == "" ? "-" : $3), $2}' "$GITHUB_DB"
    return 0
}
