# ============================================================
#   lib/snapflatpak.sh — مدیریت snap/flatpak و به‌روزرسانی‌ها
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
# ============================================================

snap_list_apps() {
    header "لیست برنامه‌های snap"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap روی سیستم نصب نیست."
        return 0
    fi
    local out
    out=$(snap list 2>/dev/null)
    if [ -n "$out" ]; then
        echo "$out" | sed 's/^/   /'
    else
        echo "   (هیچ snap نصب نیست)"
    fi
    return 0
}

update_snap() {
    header "به‌روزرسانی همه snap ها"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap روی سیستم نصب نیست."
        return 0
    fi
    if sudo snap refresh; then
        success "همه snap ها به‌روزرسانی شدند."
    else
        failure "خطا در به‌روزرسانی snap."
        return 1
    fi
    return 0
}

snap_install_app() {
    header "نصب برنامه snap"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap روی سیستم نصب نیست."
        return 0
    fi
    local name
    read -r -p "   نام snap (مثلاً spotify): " name
    [ -z "$name" ] && { failure "نام وارد نشد."; return 1; }
    if sudo snap install "$name"; then
        success "snap نصب شد."
    else
        failure "خطا در نصب snap."
        info "اگر برنامه حالت classic لازم دارد: sudo snap install $name --classic"
    fi
    return 0
}

snap_remove_app() {
    header "حذف برنامه snap"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap روی سیستم نصب نیست."
        return 0
    fi
    local name
    read -r -p "   نام snap برای حذف: " name
    [ -z "$name" ] && { failure "نام وارد نشد."; return 1; }
    if ! snap list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "$name"; then
        failure "این snap نصب نیست."
        return 1
    fi
    confirm_action "snap «$name» کامل حذف شود؟" || { info "لغو شد."; return 0; }
    if sudo snap remove --purge "$name"; then
        success "حذف شد."
    else
        failure "خطا در حذف."
    fi
    return 0
}

snap_clean_revisions() {
    header "پاک‌سازی نسخه‌های قدیمی snap (بازیابی فضای دیسک)"
    if ! command -v snap > /dev/null 2>&1; then
        info "snap روی سیستم نصب نیست."
        return 0
    fi
    local disabled
    disabled=$(snap list --all 2>/dev/null | awk '/disabled/ {print $1" "$3}')
    if [ -z "$disabled" ]; then
        success "نسخه قدیمی snap برای حذف وجود ندارد."
        return 0
    fi
    local count
    count=$(echo "$disabled" | wc -l)
    info "این نسخه‌های قدیمی قابل حذف‌اند:"
    echo "$disabled" | sed 's/^/      • /'
    if ! confirm_action "$count نسخه حذف شوند؟"; then
        info "لغو شد."
        return 0
    fi
    local name rev
    while read -r name rev; do
        [ -z "$name" ] && continue
        if sudo snap remove "$name" --revision="$rev" > /dev/null 2>&1; then
            success "$name (نسخه $rev) حذف شد."
        else
            failure "حذف $name نسخه $rev ناموفق بود."
        fi
    done <<< "$disabled"
    return 0
}

flatpak_list_apps() {
    header "لیست برنامه‌های flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak روی سیستم نصب نیست."
        return 0
    fi
    local out
    out=$(flatpak list --app 2>/dev/null)
    if [ -n "$out" ]; then
        echo "$out" | sed 's/^/   /'
    else
        echo "   (هیچ برنامه flatpak نصب نیست)"
    fi
    return 0
}

update_flatpak() {
    header "به‌روزرسانی همه flatpak ها"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak روی سیستم نصب نیست."
        return 0
    fi
    if flatpak update -y; then
        success "همه flatpak ها به‌روزرسانی شدند."
    else
        failure "خطا در به‌روزرسانی flatpak."
        return 1
    fi
    return 0
}

flatpak_install_app() {
    header "نصب برنامه flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak روی سیستم نصب نیست."
        return 0
    fi
    local id
    read -r -p "   شناسه برنامه (مثلاً org.mozilla.firefox): " id
    [ -z "$id" ] && { failure "شناسه وارد نشد."; return 1; }
    if flatpak install -y flathub "$id"; then
        success "flatpak نصب شد."
    else
        failure "خطا در نصب flatpak."
        info "اگر مخزن flathub اضافه نشده:"
        info "  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    fi
    return 0
}

flatpak_remove_app() {
    header "حذف برنامه flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak روی سیستم نصب نیست."
        return 0
    fi
    local id
    read -r -p "   شناسه برنامه برای حذف: " id
    [ -z "$id" ] && { failure "شناسه وارد نشد."; return 1; }
    if ! flatpak list --app --columns=application 2>/dev/null | grep -qx "$id"; then
        failure "این برنامه flatpak نصب نیست."
        return 1
    fi
    confirm_action "«$id» همراه داده‌هایش حذف شود؟" || { info "لغو شد."; return 0; }
    if flatpak uninstall -y --delete-data "$id"; then
        success "حذف شد."
    else
        failure "خطا در حذف."
    fi
    return 0
}

flatpak_clean_unused() {
    header "پاک‌سازی ران‌تایم‌ها و بسته‌های بدون استفاده flatpak"
    if ! command -v flatpak > /dev/null 2>&1; then
        info "flatpak روی سیستم نصب نیست."
        return 0
    fi
    if flatpak uninstall --unused -y; then
        success "پاک‌سازی انجام شد."
    else
        failure "خطا در پاک‌سازی."
    fi
    return 0
}

clean_snap_flatpak_junk() {
    snap_clean_revisions
    flatpak_clean_unused
}

# ============================================================
#   به‌روزرسانی برنامه‌ها
# ============================================================

update_apt() {
    header "به‌روزرسانی apt (سیستم و بسته‌های deb)"
    info "بررسی به‌روزرسانی‌ها..."
    sudo apt update || { failure "خطا در apt update."; return 1; }
    if sudo apt upgrade -y; then
        success "به‌روزرسانی apt انجام شد."
        sudo apt autoremove -y > /dev/null 2>&1
    else
        failure "خطا در به‌روزرسانی بسته‌ها."
        return 1
    fi
    return 0
}

# بررسی به‌روزرسانی برنامه‌های tar.gz — اسکن Downloads + مسیر/URL دستی
# خودترمیمی: رد‌های بی‌نسخه که مسیرشان با رد دیگری (دارای نسخه)
# یکسان است، پیش از اسکن حذف می‌شوند
update_targz_apps() {
    header "بررسی به‌روزرسانی برنامه‌های tar.gz"

    if [ ! -s "$REGISTRY_DB" ]; then
        info "هیچ برنامه‌ای در رجیستری ثبت نشده است."
        info "برنامه‌های نصب‌شده با نسخه‌های قبلی اسکریپت رجیستری ندارند؛"
        info "برای ردیابی به‌روزرسانی، یک‌بار دوباره نصبشان کنید."
        return 0
    fi

    # خودترمیمی رد‌های مرواریدی
    local -a db_lines=()
    mapfile -t db_lines < "$REGISTRY_DB"
    local l n1 v1 d1 n2 v2 d2 i clean_removed=0
    for l in "${db_lines[@]}"; do
        IFS='|' read -r n1 v1 d1 <<< "$l"
        [ -z "$v1" ] || continue
        for i in "${!db_lines[@]}"; do
            IFS='|' read -r n2 v2 d2 <<< "${db_lines[$i]}"
            if [ -n "$v2" ] && [ "$d2" = "$d1" ]; then
                info "رد مرواریدی «$n1» (بی‌نسخه، مسیر تکراری) حذف شد."
                registry_remove "$n1"
                clean_removed=1
                break
            fi
        done
    done
    [ "$clean_removed" = "1" ] && mapfile -t db_lines < "$REGISTRY_DB"

    # اسنپ‌شات کامل بانک پیش از حلقه — read های تعاملی داخل حلقه
    # نباید خطوط خود فایل را مصرف کنند و بازنویسی بانک در میانه
    # حلقه (موقع نصب نسخه جدید) ایمن انجام می‌شود
    local -a reg_lines=()
    mapfile -t reg_lines < "$REGISTRY_DB"

    local line name ver dir sel f idx j
    for line in "${reg_lines[@]}"; do
        IFS='|' read -r name ver dir _ <<< "$line"
        [ -z "$name" ] && continue

        echo ""
        info "برنامه: $name (نسخه: $( [ -n "$ver" ] && echo "$ver" || echo "نامشخص")) → $dir"

        # اسکن پوشه Downloads برای نسخه جدید
        local -a match=() mver=()
        local n1 n2 fname_clean
        n1=$(normalize_name "$name")
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            fname_clean=$(name_from_archive "$f")
            n2="$fname_clean"
            if [[ "$n2" == *"$n1"* ]] || [[ "$n1" == *"$n2"* ]]; then
                match+=("$f")
                mver+=("$(guess_version "$f")")
            fi
        done < <(find "$HOME/Downloads" -maxdepth 1 -type f -iname "*.tar.gz" 2>/dev/null)

        if [ ${#match[@]} -gt 0 ]; then
            info "این فایل‌ها در Downloads پیدا شدند:"
            j=1
            for idx in "${!match[@]}"; do
                local mark=""
                if [ -n "${mver[$idx]}" ] && [ "${mver[$idx]}" != "$ver" ]; then
                    mark="  → نسخه ${mver[$idx]}"
                fi
                echo "   $j) $(basename "${match[$idx]}")$mark"
                ((j++))
            done
        else
            info "فایل جدیدی برای این برنامه در ~/Downloads پیدا نشد."
        fi
        echo "   m) مسیر فایل جدید یا لینک دانلود را خودم می‌دهم"
        echo "   Enter) رد کردن این برنامه"

        read -r -p "   انتخاب: " sel
        if [ "${sel,,}" = "m" ]; then
            read -r -p "   مسیر فایل یا URL: " f
            f=${f/#\~/$HOME}
            if [[ "$f" == http* ]]; then
                if ! command -v curl > /dev/null 2>&1; then
                    failure "curl نصب نیست (sudo apt install curl)."
                    continue
                fi
                local dl="$HOME/Downloads/$(basename "$f")"
                info "دانلود $f ..."
                if curl -fL --progress-bar -o "$dl" "$f"; then
                    f="$dl"
                else
                    failure "دانلود ناموفق بود."
                    continue
                fi
            fi
            [ -f "$f" ] || { failure "فایل پیدا نشد."; continue; }
            targz_install_from_file "$f" "$name"
        elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#match[@]} ]; then
            targz_install_from_file "${match[$((sel-1))]}" "$name"
        else
            info "رد شد."
        fi
    done
    return 0
}

# به‌روزرسانی همه منابع
update_all() {
    header "🔄 به‌روزرسانی همه برنامه‌ها (apt + snap + flatpak + tar.gz + github)"
    update_apt
    update_snap
    update_flatpak
    update_targz_apps
    github_update_apps
    echo ""
    success "چرخه به‌روزرسانی کامل شد."
    return 0
}
