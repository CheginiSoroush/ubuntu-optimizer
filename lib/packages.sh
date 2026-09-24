# ============================================================
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#   lib/packages.sh — نصب بسته‌ها و برنامه‌ها (deb، ابزارها، nodejs)
#   v5.4: حذف purge_firefox و purge_nodejs — این دو میراث v2.0
#   بودند و با cleanup_app (منوی ۸ / --cleanup) هم‌پوشانی کامل داشتند.
#   مسیرهای داده خاص‌شان به offer_user_data_cleanup در
#   lib/appmgmt.sh منتقل شد تا هیچ قابلیتی از دست نرود.
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
