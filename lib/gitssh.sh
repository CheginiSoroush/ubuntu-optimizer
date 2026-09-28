# shellcheck shell=bash
# ============================================================
#   lib/gitssh.sh — set up and manage the GitHub SSH key
#   Author & Designer: Soroush Chegini (CheginiSoroush)
# ============================================================

# Path of the first existing SSH key — empty if none exists
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

# GitHub authentication test — output in GITSSH_OUT; exit 0 = success
# accept-new: the github.com host key is accepted on first connection
# BatchMode: never blocks on an interactive question
gitssh_probe() {
    GITSSH_OUT=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                 -o BatchMode=yes -T git@github.com 2>&1)
    printf '%s' "$GITSSH_OUT" | grep -q "successfully authenticated"
}

# GitHub username — must be called after gitssh_probe
gitssh_github_user() {
    printf '%s' "$GITSSH_OUT" | grep -o 'Hi [^!]*' | awk '{print $2}'
}

# Is URL rewriting (https → ssh) enabled?
gitssh_rewrite_enabled() {
    git config --global --get-all url."git@github.com:".insteadOf 2>/dev/null \
        | grep -qx "https://github.com/"
}

# Enable URL rewriting — all https GitHub URLs use SSH
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

# Disable URL rewriting — for systems without an SSH key
gitssh_disable_rewrite() {
    if git config --global --get-all url."git@github.com:".insteadOf > /dev/null 2>&1; then
        git config --global --unset url."git@github.com:".insteadOf
        success "URL rewriting disabled."
    else
        info "Already disabled."
    fi
    return 0
}

# ---------- Full setup wizard ----------
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

# ---------- Status report ----------
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
