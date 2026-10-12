# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/github.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Install, update, list and remove apps directly from GitHub Releases:
#  authenticate sudo up front, fetch the latest release, pick the best asset
#  automatically, download into a temp dir, verify the SHA-256 checksum when
#  the release ships one, install, register in github.db and clean up.
#  Updates ask one question per app; after confirmation everything else is
#  automatic.
#
#  Reached from the “Install Packages & Apps”, “Manage & Fully Remove Apps”
#  and “Update Apps” menus, and from the CLI flags --github-install
#  OWNER/REPO [NAME], --github-remove NAME, --github-update and --github-list.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

readonly GITHUB_DB="$REGISTRY_DIR/github.db"

# ── GitHub app database ────────────────────────────────────────────────────────
# Line format: name|owner/repo|installed_tag

# ───────────────────────────────────────────────────────────────────────────────
# gh_db_add() — add or replace an entry in the GitHub app database
#
# Rewrites github.db without any existing entry of the same name and appends
# the new record, so re-adding an app replaces it instead of duplicating it.
# The rewrite goes through a temp file: on an awk failure the original file
# is left untouched (never replaced by an empty file).
#
# Globals:   GITHUB_DB, REGISTRY_DIR — database file and its parent directory
# Arguments: $1 — app name
#            $2 — repository (owner/repo)
#            $3 — installed release tag
# Returns:   0 — entry written
#            1 — the awk filter failed (database unchanged)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# gh_db_remove() — drop an entry from the GitHub app database
#
# Rewrites github.db without the named entry, again through a temp file so
# an awk failure cannot destroy the database. A missing database is a
# silent no-op.
#
# Globals:   GITHUB_DB — database file rewritten in place
# Arguments: $1 — app name to drop
# Returns:   0 — entry removed (or nothing to remove)
#            1 — the awk filter failed (database unchanged)
# ───────────────────────────────────────────────────────────────────────────────
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

# ───────────────────────────────────────────────────────────────────────────────
# gh_db_has() — check whether an app is tracked in the GitHub database
#
# Exact first-field match against github.db; used by the removal flows to
# tell tracked apps apart from everything else on the system.
#
# Globals:   GITHUB_DB — database file read
# Arguments: $1 — app name (case-exact)
# Returns:   0 — the app is tracked
#            1 — not tracked (or the database does not exist)
# ───────────────────────────────────────────────────────────────────────────────
gh_db_has() {   # $1=name
    [ -f "$GITHUB_DB" ] || return 1
    awk -F'|' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$GITHUB_DB" 2>/dev/null
}

# ───────────────────────────────────────────────────────────────────────────────
# gh_set_auth() — build the curl auth arguments from an optional token
#
# Prefers GH_TOKEN, then GITHUB_TOKEN, and fills GH_CURL_AUTH with a Bearer
# header accordingly. A token raises the API rate limit from 60/hour (per
# IP) to 5000/hour (per token). Auth is only sent to api.github.com —
# release asset downloads stay anonymous (they are not rate-limited).
#
# Globals:   GH_TOKEN, GITHUB_TOKEN — read (optional environment variables)
#            GH_CURL_AUTH — written; curl argument array (empty when anonymous)
# ───────────────────────────────────────────────────────────────────────────────
gh_set_auth() {
    GH_CURL_AUTH=()
    if [ -n "${GH_TOKEN:-}" ]; then
        GH_CURL_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        GH_CURL_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    return 0
}

# ── Fetch the latest release ───────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# gh_fetch_latest() — fetch the latest release of a repository
#
# Normalizes OWNER/REPO input (URL and git-remote forms accepted), installs
# curl on demand and calls the releases/latest API with a 15 s connect /
# 30 s total timeout, then fills GH_TAG and the GH_URLS asset list,
# parsing with jq when available and with grep/sed otherwise. API errors
# are matched on the "message" field only — release notes (the "body"
# field) may legitimately contain words like "rate limit".
#
# The raw API response is TTL-cached (lib/cache.sh) under the key
# gh:latest:<owner>::<repo> for 5 minutes: the anonymous API allows only 60 requests/hour per IP,
# and repeated installs/update checks within the TTL now cost zero API
# calls. A cached response passes through the exact same validation and
# parsing as a fresh one; error responses and unparseable bodies are
# never cached. Bypass: --no-cache / NO_CACHE=1 / UO_NO_CACHE=1.
#
# Globals:   GH_CURL_AUTH — auth arguments consumed
#            GH_TAG, GH_URLS — written; release tag and asset URLs
# Arguments: $1 — OWNER/REPO or a full github.com URL
# Returns:   0 — release metadata parsed (fresh or cached)
#            1 — bad repository format, network/API failure, or an
#                unparseable response (private repository?)
# ───────────────────────────────────────────────────────────────────────────────
gh_fetch_latest() {   # $1 = OWNER/REPO or a full URL
    GH_TAG=""
    GH_URLS=()

    if ! command -v curl > /dev/null 2>&1; then
        info "Installing curl..."
        sudo apt install -y curl > /dev/null 2>&1 || { failure "Failed to install curl."; return 1; }
    fi

    local repo="$1" resp="" from_cache=0
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

    # The key joins owner and repo with "::" — a separator that cannot
    # occur inside the validated OWNER/REPO format, so no two repositories
    # can ever share an entry ("/" itself is not allowed in cache keys).
    if cache_lookup "gh:latest:${repo//\//::}"; then
        from_cache=1
        resp="$_CACHE_VALUE"
        info "Using cached release info for $repo (5 min TTL — bypass with --no-cache) ..."
    else
        info "Checking the latest release of $repo ..."
        # stderr is kept separate so a curl failure shows as an empty response, not broken JSON
        if ! resp=$(curl -sSL --connect-timeout 15 --max-time 30 "${GH_CURL_AUTH[@]}" \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || [ -z "$resp" ]; then
            failure "Failed to get a response from the GitHub API — check your internet connection."
            return 1
        fi
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
    # Only a fully validated response is cached — errors and parse
    # failures above already returned, so they are never stored
    [ "$from_cache" = "0" ] && cache_set "gh:latest:${repo//\//::}" "$resp" 300
    return 0
}

# ── Automatic asset pick ───────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# gh_pick_asset() — score release assets and pick the best one
#
# Every asset file name is lowercased and scored:
#   matching arch +40 | deb format +10 | AppImage +8 | tar.gz/tgz +5
#   no arch tag -15   | musl -8        | incompatible arch -200
# Non-Linux builds are excluded outright, and a score of -100 or less
# (wrong architecture) disqualifies the asset. The highest score wins; on a
# tie the first file is taken. With no eligible asset, the full asset list
# is printed so the user can pick manually.
#
# Globals:   GH_URLS — read; asset URLs to score
#            GH_PICKED_URL — written; the winning URL
# Returns:   0 — an asset was picked
#            1 — no compatible installable asset
# ───────────────────────────────────────────────────────────────────────────────
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

# ── SHA-256 verification of the downloaded asset ───────────────────────────────
#  Supply-chain check: when a release ships a checksum file (checksums.txt,
#  SHA256SUMS, fzf_checksums.txt, <file>.sha256 / .sha256sum / .dgst, ...),
#  the downloaded asset is verified against it before anything is installed.
#  A mismatch aborts the install and deletes the download. Releases without
#  any checksum file simply continue (with an info line). The check can be
#  skipped explicitly with UO_SKIP_CHECKSUM=1 for broken releases.

# ───────────────────────────────────────────────────────────────────────────────
# gh_is_checksum_asset() — does this release-asset name look like a checksum?
#
# Name-based detection (case-insensitive) covering the common conventions:
# checksums.txt / <project>_checksums.txt (goreleaser), SHA256SUMS,
# <file>.sha256, <file>.sha256sum, <file>.sha256sum.txt and <file>.dgst.
#
# Arguments: $1 — asset file name
# Returns:   0 — the name looks like a checksum file
#            1 — anything else (installable payload)
# ───────────────────────────────────────────────────────────────────────────────
gh_is_checksum_asset() {   # $1 = file name (any case)
    local low=${1,,}
    case "$low" in
        *checksums*|sha256sums*|*.sha256|*.sha256sum|*.sha256sum.txt|*.dgst) return 0 ;;
    esac
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# gh_extract_expected_hash() — pull the expected SHA-256 for a file from a
# checksum file
#
# Three formats are understood, tried in order:
#   1) sha256sum -c style:  "<64-hex>  <name>"  or  "<64-hex> *<name>"
#      (exact name match, binary-marker asterisk stripped)
#   2) any line that mentions the file name and carries a 64-hex token —
#      covers OpenSSL ".dgst" output like "SHA2-256(<name>)= <hash>"
#   3) a lone 64-hex token in the whole file (bare-hash ".sha256" files)
#
# Globals:   none
# Arguments: $1 — checksum file path
#            $2 — target file name to look up
# Returns:   0 — prints the expected hash (64 hex chars, any case)
#            1 — the file has no usable entry for $2
# ───────────────────────────────────────────────────────────────────────────────
gh_extract_expected_hash() {   # $1=checksum file  $2=target basename
    local ck="$1" target="$2" hash=""

    # 1) sha256sum format with exact name match
    hash=$(awk -v f="$target" '
        NF >= 2 {
            fn = $2; sub(/^\*/, "", fn)
            if (fn == f && $1 ~ /^[0-9a-fA-F]{64}$/) { print $1; exit }
        }' "$ck" 2>/dev/null)

    # 2) the target name is on the line and a 64-hex token is present
    if [ -z "$hash" ]; then
        hash=$(awk -v f="$target" '
            index($0, f) {
                n = split($0, toks, /[^0-9a-fA-F]+/)
                for (i = 1; i <= n; i++)
                    if (toks[i] ~ /^[0-9a-fA-F]{64}$/) { print toks[i]; exit }
            }' "$ck" 2>/dev/null)
    fi

    # 3) a single 64-hex token in the whole file (bare-hash style) — only
    #    when the file carries nothing else: if it holds non-hex text (a
    #    sha256sum list or a .dgst file), it simply has no entry for the
    #    target and falling through would risk picking ANOTHER file's hash
    if [ -z "$hash" ]; then
        if [ -n "$(sed 's/[0-9a-fA-F]//g; s/[[:space:]]//g' "$ck" 2>/dev/null)" ]; then
            return 1
        fi
        hash=$(grep -Eo '[0-9a-fA-F]{64}' "$ck" 2>/dev/null | sort -u)
        if [ "$(printf '%s\n' "$hash" | grep -c .)" != "1" ]; then
            hash=""
        fi
    fi

    [ -n "$hash" ] || return 1
    printf '%s\n' "$hash"
}

# ───────────────────────────────────────────────────────────────────────────────
# gh_verify_checksum() — verify a downloaded release asset against the
# release's own checksum file
#
# Looks for a checksum asset among GH_URLS, downloads the first one into the
# temp work dir, extracts the expected hash for the target file and compares
# it (case-insensitively) with sha256sum. On a mismatch the downloaded file
# must not be used: the caller is expected to abort and clean up. When the
# release ships no checksum file, or a checksum file without an entry for
# this particular file (multi-file releases), verification is skipped with a
# warning — never a hard failure. UO_SKIP_CHECKSUM=1 disables the check.
#
# Globals:   GH_URLS — read; all asset URLs of the current release
#            UO_SKIP_CHECKSUM — optional env escape hatch ("1" skips)
# Arguments: $1 — target file name (basename of the download)
#            $2 — target file path (the downloaded asset)
#            $3 — temp work dir the checksum file may be downloaded into
# Returns:   0 — verified OK, or verification not possible (skip)
#            1 — CHECKSUM MISMATCH — the asset must not be installed
# ───────────────────────────────────────────────────────────────────────────────
gh_verify_checksum() {   # $1=target basename $2=target path $3=work dir
    local base="$1" target="$2" workdir="$3"

    if [ "${UO_SKIP_CHECKSUM:-}" = "1" ]; then
        warn "Checksum verification skipped (UO_SKIP_CHECKSUM=1)."
        return 0
    fi

    local ck_url ck_name expected actual
    for ck_url in "${GH_URLS[@]}"; do
        ck_name=$(basename "$ck_url")
        [ "$ck_name" = "$base" ] && continue
        gh_is_checksum_asset "$ck_name" || continue

        info "Verifying checksum with $ck_name ..."
        if ! curl -fsSL --connect-timeout 15 --max-time 60 -o "$workdir/$ck_name" "$ck_url"; then
            warn "Checksum file could not be downloaded — verification skipped."
            continue
        fi

        if ! expected=$(gh_extract_expected_hash "$workdir/$ck_name" "$base"); then
            # This checksum file does not list our file (multi-asset releases
            # often ship several per-platform checksum files) — try the next one
            continue
        fi

        if ! actual=$(sha256sum "$target" 2>/dev/null | awk '{print $1}'); then
            warn "sha256sum failed — verification skipped."
            return 0
        fi

        if [ "${expected,,}" = "${actual,,}" ]; then
            success "Checksum verified — the download is intact."
            return 0
        fi

        failure "CHECKSUM MISMATCH for $base"
        info "  expected: $expected"
        info "  actual:   $actual"
        return 1
    done

    info "This release ships no matching checksum file — verification skipped."
    return 0
}

# ── Download, install, register and clean up ───────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# gh_download_and_install() — download an asset and install it end to end
#
# Downloads the chosen release asset, dispatches to the deb / AppImage /
# tar.gz install path (the latter two with UO_AUTO=1 so no questions are
# asked), registers the app in github.db on success and removes the temp
# download. On failure the downloaded file is kept in ~/Downloads — a
# findable, persistent location instead of a random mktemp dir — together
# with the exact retry command.
#
# Globals:   UO_AUTO — set to 1 around the install calls, then unset
#            GITHUB_DB — tracking entry written via gh_db_add on success
# Arguments: $1 — asset download URL
#            $2 — app name
#            $3 — repository (owner/repo)
#            $4 — release tag
# Returns:   0 — installed and registered
#            1 — download or install failed (file kept for manual retry)
# ───────────────────────────────────────────────────────────────────────────────
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

    # Supply-chain check — verify the SHA-256 checksum when the release
    # ships one (checksums.txt, SHA256SUMS, <file>.sha256, .dgst, ...).
    # A mismatch deletes the download and aborts before anything runs.
    if ! gh_verify_checksum "$base" "$tmpfile" "$d"; then
        rm -rf "$d"
        failure "Install aborted — the download did not match the release checksum."
        info "The file was deleted. Re-check the release or report it upstream."
        return 1
    fi

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

# ── Install an app from GitHub (fully automatic) ───────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# github_install_repo() — install an app from GitHub Releases
#
# Menu entry and CLI --github-install flow: prompts for the repository when
# it was not supplied, normalizes and validates it, derives the app name
# from the repository when absent, then chains gh_fetch_latest →
# gh_pick_asset → gh_download_and_install. Everything after the prompt is
# automatic (the install helpers run in UO_AUTO mode).
#
# Globals:   GH_TAG, GH_PICKED_URL — consumed from the fetch/pick helpers
# Arguments: $1 — repository (optional in the menu; prompted when empty)
#            $2 — app name (optional; derived from the repository name)
# Returns:   0 — installed
#            1 — invalid repository format, or a step failed
# ───────────────────────────────────────────────────────────────────────────────
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

# ── Remove a GitHub app ────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# github_remove_app() — remove a GitHub app and its tracking entry
#
# Removes the app from the system (all sources, via cleanup_app) and drops
# the GitHub db entry. cleanup_app removes the entry itself when the app is
# fully gone; the still-installed check below covers cancelled or partial
# removals — the entry is then kept for the update flow's self-heal. A
# stale entry (the app gone from every source) is removed directly,
# without running the full cleanup flow.
#
# Globals:   GITHUB_DB — read for the tracked-apps listing and the lookup
# Arguments: $1 — app name (optional; prompted from the tracked list when empty)
# Returns:   0 — app and entry removed (or a stale entry was dropped)
#            1 — not tracked, no name, or the removal failed or was cancelled
# ───────────────────────────────────────────────────────────────────────────────
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

# ── Update check ───────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# github_update_apps() — check updates for every tracked GitHub app
#
# Iterates over a snapshot of github.db (a full copy, so the interactive
# reads cannot consume the file's own lines) and compares the installed
# tag with the latest release, ignoring a leading "v" on both sides. One
# question per outdated app — after confirmation the download and install
# are automatic; declining just moves on. Apps no longer installed are
# dropped from the tracking list (self-healing), and per-app failures
# never abort the whole loop.
#
# Globals:   GITHUB_DB — read and rewritten (self-heal removals)
#            GH_TAG, GH_PICKED_URL — reused across iterations
# Arguments: none
# ───────────────────────────────────────────────────────────────────────────────
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

# ── List GitHub apps ───────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# github_list_apps() — list the apps tracked in the GitHub database
#
# Prints one line per tracked app (name, installed tag or "-", repository)
# behind the menu entry and the CLI --github-list flag; an empty database
# shows the install hint instead of an empty screen.
#
# Globals:   GITHUB_DB — database file read
# Arguments: none
# ───────────────────────────────────────────────────────────────────────────────
github_list_apps() {
    header "🐙 Tracked GitHub Apps"
    if [ ! -s "$GITHUB_DB" ]; then
        info "(empty) — install with: uo --github-install OWNER/REPO"
        return 0
    fi
    awk -F'|' '{printf "   %-24s %-14s %s\n", $1, ($3 == "" ? "-" : $3), $2}' "$GITHUB_DB"
    return 0
}
