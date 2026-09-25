# ============================================================
#   lib/gitssh.sh — راه‌اندازی و مدیریت کلید SSH گیت‌هاب
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
# ============================================================

# مسیر نخستین کلید SSH موجود — خالی اگر وجود نداشته باشد
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

# تست احراز هویت گیت‌هاب — خروجی در GITSSH_OUT؛ کد ۰ = موفق
# accept-new: کلید میزبان github.com در نخستین اتصال پذیرفته می‌شود
# BatchMode: بدون سؤال تعاملی معطل نمی‌ماند
gitssh_probe() {
    GITSSH_OUT=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                 -o BatchMode=yes -T git@github.com 2>&1)
    printf '%s' "$GITSSH_OUT" | grep -q "successfully authenticated"
}

# نام کاربر گیت‌هاب — باید پس از gitssh_probe صدا زده شود
gitssh_github_user() {
    printf '%s' "$GITSSH_OUT" | grep -o 'Hi [^!]*' | awk '{print $2}'
}

# آیا بازنویسی URL (https → ssh) فعال است؟
gitssh_rewrite_enabled() {
    git config --global --get-all url."git@github.com:".insteadOf 2>/dev/null \
        | grep -qx "https://github.com/"
}

# فعال‌سازی بازنویسی URL — همه آدرس‌های https گیت‌هاب از SSH استفاده می‌کنند
gitssh_enable_rewrite() {
    if gitssh_rewrite_enabled; then
        info "بازنویسی URL (https → ssh) از قبل فعال است."
        return 0
    fi
    if confirm_action "همه آدرس‌های https گیت‌هاب خودکار از SSH استفاده کنند؟ (پیشنهاد: y)"; then
        git config --global url."git@github.com:".insteadOf "https://github.com/"
        success "فعال شد — از این پس clone/pull/push بدون رمز، حتی با URL های https."
    else
        info "رد شد — می‌توانید بعداً دوباره این گزینه را اجرا کنید."
    fi
    return 0
}

# غیرفعال‌سازی بازنویسی URL — برای سیستم‌های بدون کلید SSH
gitssh_disable_rewrite() {
    if git config --global --get-all url."git@github.com:".insteadOf > /dev/null 2>&1; then
        git config --global --unset url."git@github.com:".insteadOf
        success "بازنویسی URL غیرفعال شد."
    else
        info "از قبل غیرفعال است."
    fi
    return 0
}

# ---------- ویزارد راه‌اندازی کامل ----------
gitssh_setup() {
    header "🔑 راه‌اندازی SSH گیت‌هاب (بدون رمز)"

    # پیش‌نیازها
    if ! command -v git > /dev/null 2>&1; then
        info "نصب git..."
        sudo apt install -y git > /dev/null 2>&1 || { failure "خطا در نصب git."; return 1; }
    fi
    if ! command -v ssh > /dev/null 2>&1; then
        info "نصب openssh-client..."
        sudo apt install -y openssh-client > /dev/null 2>&1 \
            || { failure "خطا در نصب openssh-client."; return 1; }
    fi

    # اگر احراز هویت از قبل برقرار است، فقط تنظیمات ناقص تکمیل می‌شود
    if gitssh_probe; then
        local gh_user
        gh_user=$(gitssh_github_user)
        success "SSH از قبل فعال است! (کاربر: ${gh_user:-نامشخص})"
        gitssh_enable_rewrite
        echo ""
        success "همه‌چیز آماده است. تست: git pull در هر پروژه‌ای."
        return 0
    fi

    # کلید موجود یا ساخت کلید جدید
    local KEY
    KEY=$(ssh_key_file)
    if [ -n "$KEY" ]; then
        info "کلید موجود: $KEY"
        info "این کلید هنوز به GitHub اضافه نشده است — در ادامه نمایش داده می‌شود."
    else
        KEY="$HOME/.ssh/id_ed25519"
        info "ساخت کلید ed25519 (بدون passphrase)..."
        local EMAIL
        EMAIL=$(git config --global user.email 2>/dev/null)
        if [ -z "$EMAIL" ]; then
            read -r -p "   ایمیل برای شناسه کلید (Enter = پیش‌فرض سیستم): " EMAIL
        fi
        [ -z "$EMAIL" ] && EMAIL="$(whoami)@$(hostname)"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        if ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N "" > /dev/null 2>&1; then
            success "کلید ساخته شد: $KEY"
            info "بدون passphrase است؛ برای امنیت بیشتر می‌توانید بعداً رمز بگذارید:"
            info "  ssh-keygen -p -f $KEY"
        else
            failure "خطا در ساخت کلید."
            return 1
        fi
    fi

    # نمایش کلید عمومی + کپی در کلیپ‌بورد در صورت امکان
    local PUBKEY="${KEY}.pub"
    echo ""
    echo -e "${BOLD}این کلید عمومی را به GitHub اضافه کنید:${NC}"
    echo -e "${CYAN}   github.com → Settings → SSH and GPG keys → New SSH key${NC}"
    echo ""
    echo "─────────────────────────────────────────────────────"
    cat "$PUBKEY"
    echo "─────────────────────────────────────────────────────"
    echo ""
    if command -v xclip > /dev/null 2>&1; then
        if xclip -selection clipboard < "$PUBKEY" 2>/dev/null; then
            success "کلید در کلیپ‌بورد کپی شد (xclip)."
        fi
    elif command -v wl-copy > /dev/null 2>&1; then
        if wl-copy < "$PUBKEY" 2>/dev/null; then
            success "کلید در کلیپ‌بورد کپی شد (wl-copy)."
        fi
    else
        info "برای کپی خودکار در کلیپ‌بورد: sudo apt install xclip"
    fi

    # انتظار برای افزودن کلید و تست
    echo ""
    local tries=0
    while true; do
        if ! confirm_action "کلید را در GitHub افزودید؟ اکنون تست کنیم؟"; then
            info "باشه — هر وقت افزودید، دوباره «راه‌اندازی SSH» را اجرا کنید."
            return 0
        fi
        tries=$((tries + 1))
        if gitssh_probe; then
            local gh_user
            gh_user=$(gitssh_github_user)
            success "🎉 احراز هویت GitHub موفق! (کاربر: ${gh_user:-نامشخص})"
            break
        fi
        failure "هنوز موفق نشد (تلاش $tries)."
        info "در صفحه GitHub حتماً دکمه Add key را بزنید و چند ثانیه صبر کنید."
    done

    gitssh_enable_rewrite

    echo ""
    success "راه‌اندازی کامل شد! از این پس:"
    info "  git clone / git pull / git push — بدون هیچ Username/Password"
    return 0
}

# ---------- گزارش وضعیت ----------
gitssh_status() {
    header "🔑 وضعیت SSH گیت‌هاب"

    local KEY
    KEY=$(ssh_key_file)
    if [ -n "$KEY" ]; then
        echo "   • کلید: $KEY"
        ssh-keygen -lf "$KEY" 2>/dev/null | sed 's/^/       /'
    else
        echo -e "   ${RED}✗${NC} کلید SSH وجود ندارد — با «راه‌اندازی SSH» بسازید"
    fi

    if gitssh_probe; then
        local gh_user
        gh_user=$(gitssh_github_user)
        echo -e "   ${GREEN}✓${NC} احراز هویت GitHub موفق (کاربر: ${gh_user:-نامشخص})"
    else
        echo -e "   ${RED}✗${NC} احراز هویت GitHub برقرار نیست (کلید ساخته/افزوده نشده)"
        if [ -n "$KEY" ]; then
            echo -e "   ${YELLOW}ℹ${NC} راهنما: کلید عمومی را در github.com → Settings → SSH keys بگذارید"
        fi
    fi

    if gitssh_rewrite_enabled; then
        echo -e "   ${GREEN}✓${NC} بازنویسی URL فعال (https → ssh، بدون رمز)"
    else
        echo -e "   ${YELLOW}•${NC} بازنویسی URL غیرفعال"
    fi
    return 0
}
