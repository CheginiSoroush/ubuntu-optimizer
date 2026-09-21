# ============================================================
#   lib/recovery.sh — بازیابی و نجات سیستم + ابزارهای خطرناک
# ============================================================

fix_broken() {
    header "بازیابی بسته‌های خراب"
    local ok=1
    sudo apt --fix-broken install -y || ok=0
    sudo dpkg --configure -a || ok=0
    if [ "$ok" -eq 1 ]; then
        success "بازیابی انجام شد."
    else
        failure "بازیابی ناقص ماند. خروجی بالا را بررسی کنید."
    fi
}

reinstall_desktop() {
    header "نصب مجدد محیط دسکتاپ"
    warn "این کار ممکن است چند دقیقه طول بکشد..."
    if sudo apt install --reinstall -y ubuntu-desktop ubuntu-desktop-minimal gnome-shell gdm3 nautilus gnome-terminal; then
        success "محیط دسکتاپ مجدداً نصب شد."
        info "لطفاً سیستم را ری‌استارت کنید."
    else
        failure "خطا در نصب مجدد محیط دسکتاپ."
    fi
}

fix_dpkg_configure() {
    header "بررسی و پیکربندی بسته‌ها با dpkg"
    if sudo dpkg --configure -a; then
        success "پیکربندی بسته‌ها انجام شد."
    else
        failure "خطا در پیکربندی بسته‌ها."
    fi
}

install_veet() {
    header "نصب VEET (ابزار حذف عمیق)"
    warn "⚠ هشدار: VEET می‌تواند بسته‌های سیستمی را اشتباهاً حذف کند!"
    warn "⚠ فقط برنامه‌های کاربردی را با آن حذف کنید، نه بسته‌های سیستمی."
    confirm_action "ادامه می‌کنید؟" || { info "لغو شد."; return 0; }

    if ! command -v go > /dev/null 2>&1; then
        info "نصب golang..."
        sudo apt install -y golang > /dev/null 2>&1 || { failure "خطا در نصب golang."; return 1; }
    fi

    if [ ! -d "$HOME/veet/.git" ]; then
        info "دانلود سورس VEET..."
        git clone https://github.com/swadhinbiswas/veet.git "$HOME/veet" \
            || { failure "خطا در دانلود (اینترنت یا آدرس ریپو را بررسی کنید)."; return 1; }
    fi

    info "ساخت برنامه (ممکن است طول بکشد)..."
    if (cd "$HOME/veet" && make build && sudo make install); then
        if [ -x /usr/local/bin/veet ]; then
            success "VEET نصب شد. برای اجرا: sudo veet"
        elif [ -f "$HOME/veet/veet" ]; then
            sudo cp "$HOME/veet/veet" /usr/local/bin/veet
            sudo chmod +x /usr/local/bin/veet
            success "VEET نصب شد. برای اجرا: sudo veet"
        else
            failure "باینری ساخته نشد."
        fi
    else
        failure "خطا در ساخت VEET."
    fi
}
