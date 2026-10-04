# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/gitssh.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Passwordless GitHub access: SSH key discovery/generation, an authentication
#  probe and the https → ssh URL rewrite in the global git config. Entry points:
#  menu item 3 and the CLI flags --git-ssh (wizard) / --git-ssh-status.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# ssh_key_file() — locate the first existing SSH key
#
# Probes ~/.ssh/id_ed25519 then ~/.ssh/id_rsa and prints the first hit; empty
# output with a non-zero status means no key exists yet.
#
# Arguments: none
# Returns:   0 — key path printed
#            1 — no key file found (nothing printed)
# ───────────────────────────────────────────────────────────────────────────────
ssh_key_file() {
    local t
    for t in id_ed25519 id_rsa; do
        if [ -f "$HOME/.ssh/$t" ]; then
            printf '%s' "$HOME/.ssh/$t"
            return 0
        fi
    done
    return 1
}

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_probe() — test GitHub authentication over SSH
#
# Runs ssh -T git@github.com with accept-new (the github.com host key is
# accepted on first connection) and BatchMode (never blocks on an
# interactive question). The full output is captured in GITSSH_OUT.
#
# Globals:   GITSSH_OUT (written)
# Arguments: none
# Returns:   0 — "successfully authenticated" seen in the output
#            1 — authentication failed
# ───────────────────────────────────────────────────────────────────────────────
gitssh_probe() {
    GITSSH_OUT=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                 -o BatchMode=yes -T git@github.com 2>&1)
    printf '%s' "$GITSSH_OUT" | grep -q "successfully authenticated"
}

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_github_user() — extract the GitHub username from a probe
#
# Parses the "Hi <username>!" greeting out of GITSSH_OUT; call it only
# after a successful gitssh_probe.
#
# Globals:   GITSSH_OUT (read)
# Arguments: none
# Returns:   0 — always (output may be empty)
# ───────────────────────────────────────────────────────────────────────────────
gitssh_github_user() {
    printf '%s' "$GITSSH_OUT" | grep -o 'Hi [^!]*' | awk '{print $2}'
}

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_rewrite_enabled() — check whether the https → ssh rewrite is on
#
# Reads the global git config and succeeds when
# url."git@github.com:".insteadOf maps https://github.com/.
#
# Arguments: none
# Returns:   0 — rewrite enabled
#            1 — rewrite not enabled
# ───────────────────────────────────────────────────────────────────────────────
gitssh_rewrite_enabled() {
    git config --global --get-all url."git@github.com:".insteadOf 2>/dev/null \
        | grep -qx "https://github.com/"
}

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_enable_rewrite() — make all https GitHub URLs use SSH
#
# Idempotent: reports and skips when the rewrite is already configured;
# otherwise asks for confirmation (recommended) before setting the global
# url."git@github.com:".insteadOf entry — clone/pull/push then work
# passwordlessly even with https URLs.
#
# Arguments: none
# Returns:   0 — always (declining only prints an informational message)
# ───────────────────────────────────────────────────────────────────────────────
gitssh_enable_rewrite() {
    if gitssh_rewrite_enabled; then
        info "URL rewriting (https → ssh) is already enabled."
        return 0
    fi
    if confirm_action "Make all https GitHub URLs automatically use SSH? (recommended: y)"; then
        git config --global url."git@github.com:".insteadOf "https://github.com/"
        success "Enabled — clone/pull/push without a password from now on, even with https URLs."
    else
        info "Declined — you can run this option again later."
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_disable_rewrite() — turn the https → ssh rewrite off
#
# Unsets the global insteadOf entry — for systems without a working SSH
# key. Reports "already disabled" when nothing is configured.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
gitssh_disable_rewrite() {
    if git config --global --get-all url."git@github.com:".insteadOf > /dev/null 2>&1; then
        git config --global --unset url."git@github.com:".insteadOf
        success "URL rewriting disabled."
    else
        info "Already disabled."
    fi
    return 0
}

# ── Full setup wizard ──────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_setup() — run the passwordless GitHub SSH setup wizard
#
# Installs git/openssh-client when missing. When authentication already
# works, only the missing URL rewrite is completed. Otherwise reuses an
# existing key or generates a passphrase-less ed25519 key (email taken
# from git config, prompted otherwise), prints the public key, copies it
# to the clipboard when xclip/wl-copy is available, then polls GitHub
# until the key has been added (capped at 5 attempts — prevents an
# infinite loop in -y mode) and finally enables the URL rewrite.
#
# Arguments: none
# Returns:   0 — setup complete, or already working
#            1 — key generation failed or all test attempts exhausted
# ───────────────────────────────────────────────────────────────────────────────
gitssh_setup() {
    header "🔑 Set Up GitHub SSH (Passwordless)"

    # Prerequisites
    if ! command -v git > /dev/null 2>&1; then
        info "Installing git..."
        sudo apt install -y git > /dev/null 2>&1 || { failure "Failed to install git."; return 1; }
    fi
    if ! command -v ssh > /dev/null 2>&1; then
        info "Installing openssh-client..."
        sudo apt install -y openssh-client > /dev/null 2>&1 \
            || { failure "Failed to install openssh-client."; return 1; }
    fi

    # If authentication already works, only the missing settings are completed
    if gitssh_probe; then
        local gh_user
        gh_user=$(gitssh_github_user)
        success "SSH is already set up! (user: ${gh_user:-unknown})"
        gitssh_enable_rewrite
        echo ""
        success "Everything is ready. Test with: git pull in any project."
        return 0
    fi

    # Existing key or generate a new one
    local KEY
    KEY=$(ssh_key_file)
    if [ -n "$KEY" ]; then
        info "Existing key: $KEY"
        info "Authentication with this key failed — not added to GitHub, or locked (passphrase)."
        info "The public key is shown below."
    else
        KEY="$HOME/.ssh/id_ed25519"
        info "Generating an ed25519 key (no passphrase)..."
        local EMAIL
        EMAIL=$(git config --global user.email 2>/dev/null)
        if [ -z "$EMAIL" ]; then
            # EOF (Ctrl+D) → system default
            read -r -p "   Email for the key comment (Enter = system default): " EMAIL || EMAIL=""
        fi
        [ -z "$EMAIL" ] && EMAIL="$(whoami)@$(hostname)"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        if ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N "" > /dev/null 2>&1; then
            success "Key generated: $KEY"
            info "It has no passphrase; you can add one later for extra security:"
            info "  ssh-keygen -p -f $KEY"
        else
            failure "Failed to generate the key."
            return 1
        fi
    fi

    # Show the public key + copy to the clipboard when possible
    local PUBKEY="${KEY}.pub"
    echo ""
    echo -e "${BOLD}Add this public key to GitHub:${NC}"
    echo -e "${CYAN}   github.com → Settings → SSH and GPG keys → New SSH key${NC}"
    echo ""
    echo "─────────────────────────────────────────────────────"
    cat "$PUBKEY"
    echo "─────────────────────────────────────────────────────"
    echo ""
    if command -v xclip > /dev/null 2>&1; then
        if xclip -selection clipboard < "$PUBKEY" 2>/dev/null; then
            success "Key copied to the clipboard (xclip)."
        fi
    elif command -v wl-copy > /dev/null 2>&1; then
        if wl-copy < "$PUBKEY" 2>/dev/null; then
            success "Key copied to the clipboard (wl-copy)."
        fi
    else
        info "For automatic clipboard copy: sudo apt install xclip"
    fi

    # Wait for the key to be added and test — up to 5 attempts
    echo ""
    local tries=0
    while true; do
        if ! confirm_action "Have you added the key to GitHub? Test now?"; then
            info "OK — once added, run 'Set up SSH' again."
            return 0
        fi
        tries=$((tries + 1))
        if gitssh_probe; then
            local gh_user
            gh_user=$(gitssh_github_user)
            success "🎉 GitHub authentication successful! (user: ${gh_user:-unknown})"
            break
        fi
        # Attempt cap — prevents an infinite loop in -y mode
        if [ "$tries" -ge 5 ]; then
            failure "Failed after $tries attempts — check the key and run again."
            return 1
        fi
        failure "Not successful yet (attempt $tries)."
        info "Make sure you press the Add key button on GitHub and wait a few seconds."
    done

    gitssh_enable_rewrite

    echo ""
    success "Setup complete! From now on:"
    info "  git clone / git pull / git push — with no username/password"
    return 0
}

# ── Status report ──────────────────────────────────────────────────────────────

# ───────────────────────────────────────────────────────────────────────────────
# gitssh_status() — report key, authentication and rewrite state
#
# Read-only overview: the key path with its fingerprint (ssh-keygen -lf),
# a live GitHub authentication probe (with a hint when it fails) and
# whether the https → ssh URL rewrite is enabled.
#
# Globals:   GITSSH_OUT (written, via gitssh_probe)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
gitssh_status() {
    header "🔑 GitHub SSH Status"

    local KEY
    KEY=$(ssh_key_file)
    if [ -n "$KEY" ]; then
        echo "   • Key: $KEY"
        ssh-keygen -lf "$KEY" 2>/dev/null | sed 's/^/       /'
    else
        echo -e "   ${RED}✗${NC} No SSH key exists — create one with 'Set up SSH'"
    fi

    if gitssh_probe; then
        local gh_user
        gh_user=$(gitssh_github_user)
        echo -e "   ${GREEN}✓${NC} GitHub authentication successful (user: ${gh_user:-unknown})"
    else
        echo -e "   ${RED}✗${NC} GitHub authentication is not working (key not created/added)"
        if [ -n "$KEY" ]; then
            echo -e "   ${YELLOW}ℹ${NC} Hint: add the public key at github.com → Settings → SSH keys"
        fi
    fi

    if gitssh_rewrite_enabled; then
        echo -e "   ${GREEN}✓${NC} URL rewriting enabled (https → ssh, passwordless)"
    else
        echo -e "   ${YELLOW}•${NC} URL rewriting disabled"
    fi
    return 0
}
