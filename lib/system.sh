# ============================================================
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#   lib/system.sh — بهینه‌سازی سیستم/حافظه + امنیت + زمان
#   بهبود v5.2: fix_time — همگام‌سازی از دیمن فعال (chronyc makestep)
#   + پیام شفاف درباره مسدودی پورت NTP توسط ISP
# ============================================================

optimize_memory() {
    header "کاهش swappiness و vfs_cache_pressure"
    set_sysctl vm.swappiness 10
    set_sysctl vm.vfs_cache_pressure 50
    if apply_sysctl; then
        success "مقادیر حافظه تنظیم شدند."
        info "swappiness=10  |  vfs_cache_pressure=50"
    else
        failure "خطا در تنظیم مقادیر حافظه."
    fi
}

set_noatime() {
    header "افزودن noatime به /etc/fstab"
    if grep -q "noatime" /etc/fstab; then
        info "noatime از قبل فعال است."
        return 0
    fi
    sudo cp /etc/fstab /etc/fstab.bak
    info "بک‌آپ ساخته شد: /etc/fstab.bak"
    sudo sed -i -E '/^[^#]*[[:space:]]\/[[:space:]]/ s/defaults/defaults,noatime/' /etc/fstab
    if grep -q "noatime" /etc/fstab; then
        success "noatime به پارتیشن ریشه اضافه شد. پس از ری‌استارت اعمال می‌شود."
    else
        failure "خطا در ویرایش /etc/fstab (شاید گزینه defaults نداشته باشد)."
        info "بک‌آپ موجود است: /etc/fstab.bak"
    fi
}

disable_extra_services() {
    header "غیرفعال کردن سرویس‌های اضافی"
    warn "غیرفعال‌کردن avahi-daemon، کشف پرینترهای شبکه (mDNS) را از کار می‌اندازد."
    local count=0 svc
    for svc in cups-browsed whoopsie avahi-daemon; do
        if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
            if sudo systemctl disable --now "$svc" 2>/dev/null; then
                success "$svc غیرفعال شد."
                ((count++))
            else
                warn "$svc غیرفعال نشد."
            fi
        else
            info "$svc روی سیستم وجود ندارد."
        fi
    done
    [ "$count" -gt 0 ] && success "در مجموع $count سرویس غیرفعال شد."
    return 0
}

install_preload() {
    header "نصب preload (پیش‌بارگذاری برنامه‌ها)"
    if pkg_installed preload; then
        info "preload از قبل نصب است."
        return 0
    fi
    if sudo apt install -y preload > /dev/null 2>&1; then
        success "preload نصب شد."
    else
        failure "خطا در نصب preload."
    fi
}

install_tlp() {
    header "نصب tlp (مدیریت باتری)"
    if pkg_installed tlp; then
        info "tlp از قبل نصب است."
        return 0
    fi
    info "tlp بیشتر برای لپ‌تاپ‌ها مفید است."
    if pkg_installed power-profiles-daemon; then
        warn "power-profiles-daemon با tlp تداخل دارد؛ ابتدا حذف می‌شود..."
        sudo apt remove -y power-profiles-daemon > /dev/null 2>&1
    fi
    if sudo apt install -y tlp tlp-rdw > /dev/null 2>&1; then
        sudo systemctl enable tlp > /dev/null 2>&1
        sudo systemctl start tlp > /dev/null 2>&1
        success "tlp نصب و فعال شد."
    else
        failure "خطا در نصب tlp."
    fi
}

limit_journal() {
    header "محدود کردن حجم لاگ‌های سیستم"
    sudo journalctl --vacuum-size=100M > /dev/null 2>&1
    sudo mkdir -p /etc/systemd/journald.conf.d
    printf "[Journal]\nSystemMaxUse=100M\n" | sudo tee "$JOURNALD_DROPIN" > /dev/null
    sudo systemctl restart systemd-journald > /dev/null 2>&1
    success "حجم لاگ‌ها به 100M محدود شد."
}

all_system_opts() { optimize_memory; set_noatime; disable_extra_services; install_preload; install_tlp; limit_journal; }

# ============================================================
#   امنیت و رمز عبور
# ============================================================

extend_sudo_timeout() {
    header "افزایش زمان اعتبار رمز sudo"
    if sudo test -f "$SUDOERS_TIMEOUT_FILE" && sudo grep -q "timestamp_timeout" "$SUDOERS_TIMEOUT_FILE"; then
        info "timestamp_timeout از قبل تنظیم شده است."
        return 0
    fi
    echo "Defaults timestamp_timeout=120" | sudo tee "$SUDOERS_TIMEOUT_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_TIMEOUT_FILE"
    if sudo visudo -c -f "$SUDOERS_TIMEOUT_FILE" > /dev/null 2>&1; then
        success "زمان اعتبار sudo به 120 دقیقه افزایش یافت."
    else
        sudo rm -f "$SUDOERS_TIMEOUT_FILE"
        failure "فایل نامعتبر بود و حذف شد. وضعیت sudoers دست‌نخورده است."
    fi
}

setup_polkit_rule() {
    header "ساخت قانون polkit برای برنامه‌های گرافیکی"
    warn "⚠ این قانون تایید polkit را برای کاربران گروه sudo بدون رمز انجام می‌دهد."
    warn "⚠ یعنی برنامه‌های گرافیکی مدیریتی دیگر رمز نمی‌خواهند (امنیت کمی کم می‌شود)."
    if ! confirm_action "ادامه می‌کنید؟"; then
        info "لغو شد."
        return 0
    fi
    sudo mkdir -p /etc/polkit-1/rules.d
    cat << 'EOF' | sudo tee "$POLKIT_RULE_FILE" > /dev/null
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF
    if sudo systemctl restart polkit 2>/dev/null; then
        success "قانون polkit ایجاد و polkit ری‌استارت شد."
    else
        failure "خطا در ری‌استارت polkit."
    fi
}

all_security_opts() { extend_sudo_timeout; setup_polkit_rule; }

# ============================================================
#   زمان و NTP
# ============================================================

fix_time() {
    header "رفع مشکل زمان سیستم"
    if ! pkg_installed chrony; then
        info "نصب chrony..."
        sudo apt install -y chrony > /dev/null 2>&1 || { failure "خطا در نصب chrony."; return 1; }
    fi
    sudo systemctl enable --now chrony > /dev/null 2>&1

    local synced=0 i

    # روش ۱: درخواست همگام‌سازی فوری از دیمنِ در حال اجرا
    if systemctl is-active --quiet chrony 2>/dev/null; then
        sudo chronyc makestep > /dev/null 2>&1
        # چند ثانیه به دیمن فرصت می‌دهیم
        for i in 1 2 3 4 5; do
            if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
                synced=1
                break
            fi
            sleep 1
        done
    fi

    # روش ۲: همگام‌سازی یک‌باره مستقل (جایگزین ntpdate)
    if [ "$synced" = "0" ] && command -v chronyd > /dev/null 2>&1; then
        if sudo chronyd -q 'pool.ntp.org iburst' > /dev/null 2>&1; then
            synced=1
        fi
    fi

    if [ "$synced" = "1" ]; then
        success "زمان سیستم همگام شد."
    else
        warn "همگام‌سازی NTP در این لحظه ممکن نشد."
        warn "علت رایج: مسدود بودن پورت NTP (UDP 123) توسط ISP یا فایروال."
        info "chrony در پس‌زمینه به تلاش ادامه می‌دهد و معمولاً خودش همگام می‌کند."
    fi

    sudo hwclock --systohc 2>/dev/null
    success "زمان فعلی: $(date)"
    return 0
}

show_time_status() {
    header "وضعیت زمان سیستم"
    timedatectl status
}