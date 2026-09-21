# ============================================================
#   lib/packages.sh — نصب بسته‌ها و برنامه‌ها (deb، ابزارها، nodejs)
# ============================================================

install_essential_tools() {
    header "نصب ابزارهای ضروری"
    if sudo apt install -y curl wget git synaptic iw net-tools gnome-tweaks; then
        success "ابزارهای ضروری نصب شدند."
    else
        failure "خطا در نصب ابزارها."
    fi
}

install_unrar() {
    header "نصب ابزارهای استخراج (unrar, p7zip, file-roller)"
    if sudo apt install -y unrar p7zip-full file-roller; then
        success "ابزارهای استخراج نصب شدند."
    else
        failure "خطا در نصب ابزارها."
    fi
}

install_deb() {
    header "نصب فایل .deb"
    local DEB_PATH
    read -r -p "   مسیر کامل فایل .deb را وارد کنید: " DEB_PATH
    DEB_PATH=${DEB_PATH/#\~/$HOME}

    if [ ! -f "$DEB_PATH" ]; then
        failure "فایل پیدا نشد: $DEB_PATH"
        return 1
    fi
    if [[ ! "$DEB_PATH" =~ \.deb$ ]]; then
        failure "فایل باید با پسوند .deb باشد."
        return 1
    fi

    info "نصب بسته..."
    if sudo apt install -y "$DEB_PATH"; then
        success "بسته با موفقیت نصب شد."
    else
        warn "نصب با apt ناموفق بود. تلاش با dpkg..."
        if sudo dpkg -i "$DEB_PATH"; then
            sudo apt --fix-broken install -y > /dev/null 2>&1
            success "بسته نصب شد (با رفع وابستگی‌ها)."
        else
            failure "خطا در نصب بسته."
            return 1
        fi
    fi
}

purge_firefox() {
    header "حذف کامل Firefox"
    warn "بوکمارک‌ها، رمزها و تمام داده‌های کاربری Firefox هم حذف می‌شوند!"
    if ! pkg_installed firefox && ! { command -v snap > /dev/null 2>&1 && snap list firefox > /dev/null 2>&1; }; then
        info "Firefox نصب نیست."
        return 0
    fi
    confirm_action "ادامه می‌کنید؟" || { info "لغو شد."; return 0; }

    if pkg_installed firefox; then
        sudo apt purge -y firefox > /dev/null 2>&1
    fi
    if command -v snap > /dev/null 2>&1 && snap list firefox > /dev/null 2>&1; then
        info "حذف نسخه snap..."
        sudo snap remove --purge firefox > /dev/null 2>&1
    fi
    if command -v flatpak > /dev/null 2>&1 && flatpak list --app 2>/dev/null | grep -q firefox; then
        flatpak uninstall -y org.mozilla.firefox 2>/dev/null
    fi
    sudo apt autoremove -y > /dev/null 2>&1
    rm -rf ~/.mozilla ~/.cache/mozilla ~/.config/firefox ~/.cache/firefox 2>/dev/null
    success "Firefox کامل حذف شد."
}

purge_nodejs() {
    header "حذف کامل nodejs و npm"
    if ! pkg_installed nodejs; then
        info "nodejs نصب نیست."
        return 0
    fi
    confirm_action "nodejs و npm و بسته‌های سراسری‌شان حذف شوند؟" || { info "لغو شد."; return 0; }
    if sudo apt purge -y nodejs npm > /dev/null 2>&1; then
        sudo apt autoremove -y > /dev/null 2>&1
        sudo rm -rf /usr/lib/node_modules 2>/dev/null
        success "nodejs و npm حذف شدند."
    else
        failure "خطا در حذف nodejs."
    fi
}

install_appclean() {
    header "نصب AppClean"
    if ! command -v node > /dev/null 2>&1; then
        failure "nodejs نصب نیست. اول nodejs را از همین منو نصب کنید."
        return 1
    fi
    if sudo npm install -g appclean@2.0.0 > /dev/null 2>&1; then
        success "AppClean نصب شد. برای اجرا: appclean gui"
    else
        failure "خطا در نصب AppClean."
    fi
}

install_nodejs() {
    header "نصب nodejs و npm"
    if sudo apt install -y nodejs npm; then
        success "nodejs و npm نصب شدند."
        info "نسخه‌ها: node $(node --version 2>/dev/null) | npm $(npm --version 2>/dev/null)"
    else
        failure "خطا در نصب nodejs."
    fi
}
