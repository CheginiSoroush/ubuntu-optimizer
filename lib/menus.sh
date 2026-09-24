# ============================================================
#   lib/menus.sh — موتور منو، منوهای فرعی و منوی اصلی
#   v5.4: منوی ۷ فقط «نصب»، منوی ۱۰ فقط «مدیریت»
#   v5.4.1: گروه‌بندی بصری منوی اصلی در ۴ دسته معنایی
# ============================================================

# استفاده: menu_loop "عنوان" [-w "هشدار"]... "توضیح|نام_تابع"...
menu_loop() {
    local title="$1"; shift
    local warnings=()
    while [ "$1" = "-w" ]; do
        warnings+=("$2")
        shift 2
    done
    local items=("$@")
    local choice i item w func

    while true; do
        clear
        header "$title"
        for w in "${warnings[@]}"; do warn "$w"; done
        [ ${#warnings[@]} -gt 0 ] && echo ""
        i=1
        for item in "${items[@]}"; do
            echo "   $i) ${item%%|*}"
            ((i++))
        done
        echo "   0) بازگشت"
        echo ""
        read -r -p "   انتخاب کنید: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
            func="${items[$((choice-1))]#*|}"
            "$func"
            press_enter
        elif [ "$choice" = "0" ]; then
            break
        else
            failure "گزینه نامعتبر"
            sleep 1
        fi
    done
}

# ---------- منوهای فرعی ----------
menu_network() {
    menu_loop "🌐 بهینه‌سازی شبکه" \
        "غیرفعال کردن Power Management وای‌فای|disable_wifi_powersave" \
        "تنظیم DNS روی 8.8.8.8 و 1.1.1.1|set_dns" \
        "فعال‌سازی الگوریتم BBR|enable_bbr" \
        "تنظیم MTU (پیش‌فرض 1492)|set_mtu" \
        "بهینه‌سازی پارامترهای TCP|optimize_tcp" \
        "اجرای همه موارد بالا|all_network_opts"
}

menu_system() {
    menu_loop "💾 بهینه‌سازی سیستم و حافظه" \
        "کاهش swappiness و vfs_cache_pressure|optimize_memory" \
        "افزودن noatime به /etc/fstab|set_noatime" \
        "غیرفعال کردن سرویس‌های اضافی|disable_extra_services" \
        "نصب preload|install_preload" \
        "نصب tlp (مدیریت باتری)|install_tlp" \
        "محدود کردن حجم لاگ‌ها|limit_journal" \
        "اجرای همه موارد بالا|all_system_opts"
}

menu_security() {
    menu_loop "🔐 امنیت و رمز عبور" \
        "افزایش زمان اعتبار رمز sudo|extend_sudo_timeout" \
        "ساخت قانون polkit|setup_polkit_rule" \
        "اجرای هر دو|all_security_opts" \
        "راه‌اندازی کلید SSH گیت‌هاب (بدون رمز)|gitssh_setup" \
        "وضعیت SSH گیت‌هاب|gitssh_status"
}

menu_time() {
    menu_loop "🕐 زمان و NTP" \
        "رفع مشکل زمان با chrony|fix_time" \
        "نمایش وضعیت زمان|show_time_status"
}

menu_fixnet() {
    menu_loop "🛠 اسکریپت fixnet" \
        "ساخت اسکریپت fixnet (دو زبانه)|create_fixnet_script" \
        "اجرای fixnet|run_fixnet"
}

menu_testing() {
    menu_loop "📊 تست‌های شبکه" \
        "تست پینگ به 8.8.8.8|test_ping" \
        "تست DNS (ping google.com)|test_ping_dns" \
        "تست سرعت اینترنت|test_speed" \
        "نمایش اطلاعات کامل شبکه|show_network_info" \
        "اجرای همه تست‌ها|all_tests"
}

menu_packages() {
    menu_loop "📦 نصب بسته‌ها و برنامه‌ها" \
        "نصب ابزارهای ضروری (curl, wget, git, ...)|install_essential_tools" \
        "نصب ابزارهای استخراج (unrar, p7zip, file-roller)|install_unrar" \
        "نصب فایل .deb|install_deb" \
        "نصب برنامه از فایل .tar.gz (هوشمند + ثبت در رجیستری)|install_targz" \
        "نصب nodejs و npm|install_nodejs" \
        "نصب AppClean|install_appclean"
}

menu_appmgmt() {
    menu_loop "🧹 مدیریت و حذف کامل برنامه‌ها" \
        "لیست همه برنامه‌های نصب‌شده (همه منابع)|list_all_apps" \
        "حذف کامل یک برنامه از هر منبعی (با داده‌ها)|cleanup_app" \
        "پاک‌سازی تنظیمات باقی‌مانده بسته‌های deb|cleanup_deb_residuals" \
        "حذف فایل‌های desktop یتیم|cleanup_desktop_orphans"
}

menu_snapflat() {
    menu_loop "🧩 مدیریت snap و flatpak" \
        "لیست برنامه‌های snap|snap_list_apps" \
        "نصب برنامه snap|snap_install_app" \
        "حذف برنامه snap|snap_remove_app" \
        "پاک‌سازی نسخه‌های قدیمی snap (بازیابی فضا)|snap_clean_revisions" \
        "لیست برنامه‌های flatpak|flatpak_list_apps" \
        "نصب برنامه flatpak|flatpak_install_app" \
        "حذف برنامه flatpak|flatpak_remove_app" \
        "پاک‌سازی ران‌تایم‌های بدون استفاده flatpak|flatpak_clean_unused"
}

menu_updates() {
    menu_loop "🔄 به‌روزرسانی برنامه‌ها" \
        "به‌روزرسانی همه (apt + snap + flatpak + tar.gz)|update_all" \
        "به‌روزرسانی apt (سیستم و بسته‌های deb)|update_apt" \
        "به‌روزرسانی snap|update_snap" \
        "به‌روزرسانی flatpak|update_flatpak" \
        "بررسی به‌روزرسانی برنامه‌های tar.gz|update_targz_apps"
}

menu_recovery() {
    menu_loop "🚑 بازیابی و نجات سیستم" \
        "بازیابی بسته‌های خراب (apt --fix-broken)|fix_broken" \
        "نصب مجدد محیط دسکتاپ|reinstall_desktop" \
        "بررسی و پیکربندی بسته‌ها با dpkg|fix_dpkg_configure"
}

menu_dangerous() {
    menu_loop "☠ ابزارهای پیشرفته (خطرناک)" \
        -w "این بخش شامل ابزارهای قدرتمندی است که در صورت استفاده نادرست" \
        -w "می‌توانند به سیستم شما آسیب جدی بزنند!" \
        "نصب VEET (ابزار حذف عمیق - با هشدار)|install_veet"
}

# ============================================================
#   منوی اصلی — گروه‌بندی بصری در ۴ دسته معنایی
# ============================================================

main_menu() {
    local choice
    while true; do
        clear
        echo -e "${MAGENTA}"
        cat << "EOF"
    ╔══════════════════════════════════════════════════════╗
    ║                                                      ║
    ║       Ubuntu Optimizer & Fixer - v5.4                ║
    ║       ابزار جامع بهینه‌سازی و رفع مشکلات اوبونتو     ║
    ║                                                      ║
    ╚══════════════════════════════════════════════════════╝
EOF
        echo -e "${NC}"
        echo -e "${BOLD}   ── بهینه‌سازی و سلامت ──${NC}"
        echo "   1) 🌐 بهینه‌سازی شبکه"
        echo "   2) 💾 بهینه‌سازی سیستم و حافظه"
        echo "   3) 🔐 امنیت و رمز عبور"
        echo "   4) 🕐 زمان و NTP"
        echo ""
        echo -e "${BOLD}   ── ابزارهای اضطراری و تشخیص ──${NC}"
        echo "   5) 🛠 ساخت و اجرای fixnet"
        echo "   6) 📊 تست‌های شبکه و سرعت"
        echo ""
        echo -e "${BOLD}   ── برنامه‌ها ──${NC}"
        echo "   7) 📦 نصب بسته‌ها و برنامه‌ها"
        echo "   8) 🧹 مدیریت و حذف کامل برنامه‌ها"
        echo "   9) 🔄 به‌روزرسانی برنامه‌ها"
        echo "  10) 🧩 مدیریت snap و flatpak"
        echo ""
        echo -e "${BOLD}   ── سیستم و اطلاعات ──${NC}"
        echo "  11) 🚑 بازیابی و نجات سیستم"
        echo "  12) ☠ ابزارهای پیشرفته (خطرناک)"
        echo "  13) 📜 لاگ فعالیت‌ها"
        echo "  14) 📊 گزارش وضعیت سیستم"
        echo ""
        echo "   0) خروج"
        echo ""
        echo -e "${BOLD}   راهنمای سریع CLI:${NC} uo --help  (پس از نصب با install.sh)"
        echo ""
        read -r -p "   انتخاب کنید: " choice
        case $choice in
            1) menu_network ;;
            2) menu_system ;;
            3) menu_security ;;
            4) menu_time ;;
            5) menu_fixnet ;;
            6) menu_testing ;;
            7) menu_packages ;;
            8) menu_appmgmt ;;
            9) menu_updates ;;
            10) menu_snapflat ;;
            11) menu_recovery ;;
            12) menu_dangerous ;;
            13) show_log; press_enter ;;
            14) system_report; press_enter ;;
            0) clear; echo -e "${GREEN}خدانگهدار! 👋${NC}"; exit 0 ;;
            *) failure "گزینه نامعتبر"; sleep 1 ;;
        esac
    done
}
