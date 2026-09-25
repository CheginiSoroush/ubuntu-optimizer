# ============================================================
#   lib/appmgmt.sh — مدیریت و حذف کامل برنامه‌ها از همه منابع
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#
#   منابع جستجو: رجیستری tar.gz، apt (دقیق و تقریبی)، snap،
#   flatpak، پوشه‌های /opt و فایل‌های desktop. پوشه‌های متعلق به
#   بسته‌های deb تشخیص داده می‌شوند تا حذف از مسیر درست انجام شود.
# ============================================================

# نام بسته deb مالک یک مسیر — خالی اگر متعلق به هیچ بسته نباشد
deb_owner_of() {   # $1=مسیر (مثل /opt/Obsidian)
    dpkg -S "$1" 2>/dev/null | head -1 | cut -d: -f1 | awk '{print $1}' | tr -d ','
}

# جستجوی برنامه در همه منابع → آرایه FOUND_LINES
# فرمت هر عضو: type|id|توضیح|مسیر_اختیاری
# نوع‌ها: apt | snap | flatpak | targz | opt | manual
find_app_instances() {
    FOUND_LINES=()
    local raw="$1"
    local norm
    norm=$(normalize_name "$raw")
    [ -z "$norm" ] && return 1

    local rname rver rdir rexec rdesk rsrc n2 pn low name fn bn bnorm rn dup f d exec_path root owner fl
    local -a reg_names=() fuzzy=()

    # ۱) رجیستری tar.gz
    if [ -f "$REGISTRY_DB" ]; then
        while IFS='|' read -r rname rver rdir rexec rdesk rsrc; do
            [ -z "$rname" ] && continue
            reg_names+=("$(normalize_name "$rname")")
            n2=$(normalize_name "$rname")
            if [ "$n2" = "$norm" ] || [[ "$n2" == *"$norm"* ]] || [[ "$norm" == *"$n2"* ]]; then
                local vtxt=""
                [ -n "$rver" ] && vtxt=" (نسخه $rver)"
                FOUND_LINES+=("targz|$rname|نصب با این اسکریپت$vtxt|$rdir")
            fi
        done < "$REGISTRY_DB"
    fi

    # ۲) apt — تطبیق دقیق، در غیر این صورت جستجوی پیشوندی
    if pkg_installed "$raw"; then
        FOUND_LINES+=("apt|$raw|بسته deb نصب‌شده|")
    else
        while IFS= read -r pn; do
            [ -z "$pn" ] && continue
            low=${pn,,}
            case "$low" in
                lib*|python3-*|*-dev|*-doc|*-common|*-data|*-dbg|*-bin|fonts-*|*-l10n|*-i18n|language-*|*-locale*) continue ;;
            esac
            [[ "$low" == "${raw,,}"* ]] && fuzzy+=("$pn")
            [ ${#fuzzy[@]} -ge 6 ] && break
        done < <(dpkg -l 2>/dev/null | awk '/^ii/ {sub(/:.*/, "", $2); print $2}')
        for pn in "${fuzzy[@]}"; do
            FOUND_LINES+=("apt|$pn|بسته deb (تطبیق تقریبی نام)|")
        done
    fi

    # ۳) snap
    if command -v snap > /dev/null 2>&1; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            [ "$(normalize_name "$name")" = "$norm" ] && FOUND_LINES+=("snap|$name|برنامه snap|")
        done < <(snap list 2>/dev/null | awk 'NR > 1 {print $1}')
    fi

    # ۴) flatpak
    if command -v flatpak > /dev/null 2>&1; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            fn=$(normalize_name "$name")
            if [[ "$fn" == *"$norm"* ]] || [[ "$norm" == *"$fn"* ]]; then
                FOUND_LINES+=("flatpak|$name|برنامه flatpak|")
            fi
        done < <(flatpak list --app --columns=application 2>/dev/null)
    fi

    # ۵) پوشه‌های /opt — پوشه متعلق به بسته deb باید از طریق apt حذف شود
    #    تا بسته در وضعیت خراب باقی نماند
    for d in /opt/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        bn=$(basename "$d")
        bnorm=$(normalize_name "$bn")
        [ -z "$bnorm" ] && continue
        if [ "$bnorm" = "$norm" ] || [[ "$bnorm" == *"$norm"* ]] || [[ "$norm" == *"$bnorm"* ]]; then
            owner=$(deb_owner_of "$d")
            if [ -n "$owner" ]; then
                dup=0
                for fl in "${FOUND_LINES[@]}"; do
                    [[ "$fl" == "apt|$owner|"* ]] && { dup=1; break; }
                done
                [ "$dup" = "1" ] || FOUND_LINES+=("apt|$owner|بسته deb (نصب‌شده در $d)|")
                continue
            fi
            dup=0
            for rn in "${reg_names[@]}"; do
                [ "$rn" = "$bnorm" ] && { dup=1; break; }
            done
            [ "$dup" = "1" ] && continue
            FOUND_LINES+=("opt|$bn|نصب دستی در /opt|$d")
        fi
    done

    # ۶) فایل‌های desktop با Exec داخل پوشه خانه (نصب دستی خارج از /opt)
    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        exec_path=$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"' | awk '{print $1}')
        [ -z "$exec_path" ] && continue
        [ "${exec_path:0:1}" = "/" ] || continue
        [[ "$exec_path" == "$HOME"/* ]] || continue
        [[ "$exec_path" == "$HOME"/*/* ]] || continue
        if grep -E '^(Name|Exec)=' "$f" 2>/dev/null | grep -qiF "$raw"; then
            root=$(derive_install_root "$exec_path")
            [ "$root" = "$HOME" ] && continue
            FOUND_LINES+=("manual|$(basename "$root")|نصب دستی: $exec_path|$root")
        fi
    done

    return 0
}

# حذف کامل یک نصب پوشه‌ای: symlink ها + فایل‌های desktop + رجیستری
remove_dir_app() {   # $1=مسیر ریشه نصب  $2=نام برنامه
    local dir="$1" name="$2"

    # مسیرهای حساس قابل حذف نیستند
    case "$dir" in
        ""|"/"|"/opt"|"$HOME"|"$HOME"/)
            failure "مسیر حذف نامعتبر: $dir"
            return 1
            ;;
    esac

    # حذف symlink های /usr/local/bin اشاره‌کننده به داخل این پوشه
    local l target removed_links=0
    for l in /usr/local/bin/*; do
        [ -L "$l" ] || continue
        target=$(readlink -f "$l" 2>/dev/null)
        if [ -n "$target" ] && { [ "$target" = "$dir" ] || [[ "$target" == "$dir"/* ]]; }; then
            sudo rm -f "$l"
            ((removed_links++))
        fi
    done

    # حذف فایل‌های desktop اشاره‌کننده به این مسیر
    local f
    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        if grep -qF "$dir/" "$f" 2>/dev/null; then
            if [[ "$f" == "$HOME"/* ]]; then rm -f "$f"; else sudo rm -f "$f"; fi
        fi
    done

    if [ -d "$dir" ]; then
        sudo rm -rf "$dir"
    else
        info "$dir وجود ندارد (شاید قبلاً حذف شده باشد)."
    fi

    registry_remove "$name"
    success "برنامه حذف شد: $dir"
    [ "$removed_links" -gt 0 ] && info "$removed_links میان‌بر از /usr/local/bin حذف شد."
    return 0
}

# یافتن و حذف داده‌های کاربری (config/cache/share)
offer_user_data_cleanup() {   # $1=نام برنامه
    local raw="$1"
    local -a dirs=()
    local base d

    for base in "$HOME/.config" "$HOME/.local/share" "$HOME/.cache"; do
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$base" -maxdepth 1 -type d -iname "${raw}*" 2>/dev/null)
    done

    # داده‌های flatpak
    if [ -d "$HOME/.var/app" ]; then
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$HOME/.var/app" -maxdepth 1 -type d -iname "*${raw}*" 2>/dev/null)
    fi

    # مسیرهای داده برنامه‌های شناخته‌شده
    case "${raw,,}" in
        firefox|firefox-esr)
            for d in "$HOME/.mozilla" "$HOME/.cache/mozilla" \
                     "$HOME/.config/firefox" "$HOME/.cache/firefox"; do
                [ -d "$d" ] && dirs+=("$d")
            done
            ;;
        thunderbird)
            [ -d "$HOME/.thunderbird" ] && dirs+=("$HOME/.thunderbird")
            ;;
        nodejs|npm)
            for d in "$HOME/.npm" "$HOME/.cache/npm"; do
                [ -d "$d" ] && dirs+=("$d")
            done
            ;;
    esac

    # بسته‌های سراسری npm — سیستمی است و نیازمند sudo
    if [[ "${raw,,}" == "nodejs" || "${raw,,}" == "npm" ]] && [ -d /usr/lib/node_modules ]; then
        info "بسته‌های سراسری npm: /usr/lib/node_modules"
        if [ "$PURGE_DATA" = "1" ] || confirm_action "بسته‌های سراسری npm هم حذف شوند؟"; then
            sudo rm -rf /usr/lib/node_modules
            success "بسته‌های سراسری npm حذف شدند."
        else
            info "بسته‌های سراسری npm نگه داشته شدند."
        fi
    fi

    if [ ${#dirs[@]} -eq 0 ]; then
        info "داده کاربری مرتبطی پیدا نشد."
        return 0
    fi

    info "این داده‌های کاربری پیدا شدند:"
    printf '      • %s\n' "${dirs[@]}"
    if [ "$PURGE_DATA" = "1" ] || confirm_action "این پوشه‌ها هم حذف شوند؟"; then
        rm -rf "${dirs[@]}"
        success "داده‌های کاربری حذف شدند."
    else
        info "داده‌های کاربری نگه داشته شدند."
    fi
    return 0
}

# حذف کامل یک برنامه از هر منبع — تعاملی یا از CLI با --cleanup
cleanup_app() {   # $1 اختیاری = نام برنامه
    header "🧹 حذف کامل برنامه"

    local raw
    if [ -n "${1:-}" ]; then
        raw="$1"
    else
        read -r -p "   نام برنامه (مثلاً abdownloadmanager یا firefox): " raw
    fi
    [ -z "$raw" ] && { failure "نام وارد نشد."; return 1; }

    find_app_instances "$raw"
    if [ ${#FOUND_LINES[@]} -eq 0 ]; then
        failure "برنام‌ای با نام «$raw» در هیچ منبعی پیدا نشد."
        info "منابع بررسی‌شده: apt، snap، flatpak، رجیستری tar.gz، /opt و فایل‌های desktop"
        return 1
    fi

    info "این موارد پیدا شدند:"
    local i line typ id desc extra
    i=1
    for line in "${FOUND_LINES[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        echo "   $i) [$typ] $id — $desc"
        ((i++))
    done
    echo "   a) حذف همه موارد بالا"
    echo "   0) انصراف"
    echo ""

    local sel
    if [ "$CLI_MODE" = "1" ] && [ "$ASSUME_YES" = "1" ]; then
        sel="a"
        info "(انتخاب خودکار همه موارد با -y)"
    else
        read -r -p "   کدام حذف شود؟ (شماره / چند شماره با کاما / a / 0): " sel
    fi
    if [ -z "$sel" ] || [ "$sel" = "0" ]; then
        info "لغو شد."
        return 0
    fi

    local -a todo=()
    if [ "${sel,,}" = "a" ]; then
        todo=("${FOUND_LINES[@]}")
    else
        local s
        local -a parts=()
        IFS=',' read -ra parts <<< "$sel"
        for s in "${parts[@]}"; do
            s=$(printf '%s' "$s" | tr -d ' ')
            if [[ "$s" =~ ^[0-9]+$ ]] && [ "$s" -ge 1 ] && [ "$s" -le ${#FOUND_LINES[@]} ]; then
                todo+=("${FOUND_LINES[$((s-1))]}")
            fi
        done
    fi
    [ ${#todo[@]} -eq 0 ] && { failure "انتخاب نامعتبر."; return 1; }

    echo ""
    warn "این موارد حذف خواهند شد:"
    for line in "${todo[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        echo "      • [$typ] $id"
    done
    if ! confirm_action "مطمئنید؟"; then
        info "لغو شد."
        return 0
    fi

    local any_apt=0
    for line in "${todo[@]}"; do
        IFS='|' read -r typ id desc extra <<< "$line"
        case "$typ" in
            apt)
                info "حذف بسته deb: $id"
                if sudo apt purge -y "$id" > /dev/null 2>&1; then
                    success "$id حذف شد."
                    any_apt=1
                else
                    failure "خطا در حذف $id"
                fi
                ;;
            snap)
                info "حذف snap: $id"
                if sudo snap remove --purge "$id" > /dev/null 2>&1; then
                    success "$id حذف شد."
                else
                    failure "خطا در حذف snap $id"
                fi
                ;;
            flatpak)
                info "حذف flatpak: $id"
                if flatpak uninstall -y --delete-data "$id" > /dev/null 2>&1; then
                    success "$id حذف شد."
                else
                    failure "خطا در حذف flatpak $id"
                fi
                ;;
            targz)
                info "حذف از $extra"
                remove_dir_app "$extra" "$id"
                ;;
            opt)
                info "حذف از /opt/$id"
                remove_dir_app "/opt/$id" "$id"
                ;;
            manual)
                info "حذف از $extra"
                remove_dir_app "$extra" "$(basename "$extra")"
                ;;
        esac
    done

    [ "$any_apt" = "1" ] && sudo apt autoremove -y > /dev/null 2>&1
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1

    echo ""
    info "بررسی داده‌های کاربری باقی‌مانده..."
    offer_user_data_cleanup "$raw"
    success "عملیات حذف کامل شد."
    return 0
}

# پاک‌سازی تنظیمات باقی‌مانده بسته‌های deb (وضعیت rc در dpkg)
cleanup_deb_residuals() {
    header "پاک‌سازی تنظیمات باقی‌مانده بسته‌های deb"
    local -a rc=()
    local p
    while IFS= read -r p; do
        [ -n "$p" ] && rc+=("$p")
    done < <(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')

    if [ ${#rc[@]} -eq 0 ]; then
        success "تنظیمات باقی‌مانده‌ای وجود ندارد."
        return 0
    fi

    info "${#rc[@]} بسته حذف‌شده هنوز تنظیمات دارند:"
    printf '      • %s\n' "${rc[@]}" | head -30
    [ ${#rc[@]} -gt 30 ] && echo "      ... و $((${#rc[@]} - 30)) مورد دیگر"

    confirm_action "همگی پاک‌سازی شوند؟" || { info "لغو شد."; return 0; }
    if sudo apt purge -y "${rc[@]}" > /dev/null 2>&1; then
        success "تنظیمات باقی‌مانده پاک‌سازی شد."
    else
        failure "خطا در پاک‌سازی (خروجی بالا را بررسی کنید)."
    fi
    return 0
}

# حذف فایل‌های desktop که به برنامه‌ای موجود اشاره نمی‌کنند
cleanup_desktop_orphans() {
    header "بررسی فایل‌های desktop یتیم"
    local -a orphans=()
    local f exec_path

    for f in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do
        [ -f "$f" ] || continue
        exec_path=$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"' | awk '{print $1}')
        [ -z "$exec_path" ] && continue
        if [[ "$exec_path" == /* ]]; then
            [ -e "$exec_path" ] || orphans+=("$f")
        else
            command -v "$exec_path" > /dev/null 2>&1 || orphans+=("$f")
        fi
    done

    if [ ${#orphans[@]} -eq 0 ]; then
        success "فایل desktop یتیمی وجود ندارد."
        return 0
    fi

    info "این فایل‌ها به برنامه‌ای موجود اشاره نمی‌کنند:"
    printf '      • %s\n' "${orphans[@]}"
    if ! confirm_action "همگی حذف شوند؟"; then
        info "لغو شد."
        return 0
    fi
    for f in "${orphans[@]}"; do
        if [[ "$f" == "$HOME"/* ]]; then rm -f "$f"; else sudo rm -f "$f"; fi
    done
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1
    success "${#orphans[@]} فایل desktop حذف شد."
    return 0
}

# فهرست همه برنامه‌ها از همه منابع
list_all_apps() {
    header "لیست برنامه‌های نصب‌شده (همه منابع)"

    local -a reg_names=()
    local rname rn
    if [ -s "$REGISTRY_DB" ]; then
        while IFS='|' read -r rname _; do
            [ -n "$rname" ] && reg_names+=("$(normalize_name "$rname")")
        done < "$REGISTRY_DB"
    fi

    echo -e "${BOLD}── نصب با این اسکریپت (tar.gz / رجیستری) ──${NC}"
    if [ -s "$REGISTRY_DB" ]; then
        awk -F'|' '{printf "   %-24s %-12s %s\n", $1, ($2 == "" ? "-" : $2), $3}' "$REGISTRY_DB"
    else
        echo "   (خالی)"
    fi
    echo ""

    echo -e "${BOLD}── برنامه‌های deb که در /opt نصب شده‌اند ──${NC}"
    local d bn owner found_deb=0
    local -a manual_dirs=()
    for d in /opt/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        bn=$(basename "$d")
        owner=$(deb_owner_of "$d")
        if [ -n "$owner" ]; then
            echo "   $bn  →  بسته deb: $owner  (حذف از طریق apt)"
            found_deb=1
        else
            manual_dirs+=("$bn")
        fi
    done
    [ "$found_deb" = "0" ] && echo "   (خالی)"
    echo ""

    echo -e "${BOLD}── نصب دستی در /opt (بدون رجیستری و بدون بسته deb) ──${NC}"
    local found=0 isreg
    for bn in "${manual_dirs[@]}"; do
        isreg=0
        for rn in "${reg_names[@]}"; do
            [ "$rn" = "$(normalize_name "$bn")" ] && { isreg=1; break; }
        done
        [ "$isreg" = "1" ] && continue
        echo "   $bn  →  /opt/$bn"
        found=1
    done
    [ "$found" = "0" ] && echo "   (خالی)"
    echo ""

    echo -e "${BOLD}── snap ──${NC}"
    if command -v snap > /dev/null 2>&1; then
        local out
        out=$(snap list 2>/dev/null)
        if [ -n "$out" ]; then
            echo "$out" | sed 's/^/   /'
        else
            echo "   (هیچ snap نصب نیست)"
        fi
    else
        echo "   (snap نصب نیست)"
    fi
    echo ""

    echo -e "${BOLD}── flatpak ──${NC}"
    if command -v flatpak > /dev/null 2>&1; then
        local out
        out=$(flatpak list --app 2>/dev/null)
        if [ -n "$out" ]; then
            echo "$out" | sed 's/^/   /'
        else
            echo "   (هیچ برنامه flatpak نصب نیست)"
        fi
    else
        echo "   (flatpak نصب نیست)"
    fi
    echo ""

    echo -e "${BOLD}── آخرین بسته‌های نصب‌شده apt ──${NC}"
    if [ -f /var/log/dpkg.log ]; then
        grep " install " /var/log/dpkg.log 2>/dev/null \
            | awk '{sub(/:.*/, "", $4); print $4}' \
            | grep -viE '^(lib|python|perl|fonts|language|gcc|binutils|dpkg|install-info|adduser|passwd)' \
            | tail -15 | sed 's/^/   /'
    else
        echo "   (لاگ apt در دسترس نیست)"
    fi
    return 0
}
