# ============================================================
#   lib/targz.sh — نصب هوشمند برنامه‌های tar.gz
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#
#   تشخیص فایل اجرایی اصلی، بررسی معماری، نصب وابستگی‌های
#   گمشده و ثبت در رجیستری. در حالت UO_AUTO=1 (جریان گیت‌هاب)
#   بدون سؤال تعاملی اجرا می‌شود.
# ============================================================

# انتخاب فایل اجرایی اصلی بسته
# اولویت: AppImage → تطبیق کامل نام → تطبیق جزئی نام (بدون .bin) →
# تنها کاندید → در حالت UO_AUTO نخستین کاندید، وگرنه انتخاب کاربر
# ابزارهای کمکی Electron/JVM کنار گذاشته می‌شوند
pick_executable() {   # $1=پوشه بسته  $2=نام برنامه  → خروجی: SELECTED_EXEC
    SELECTED_EXEC=""
    local dir="$1" app="$2" f base_norm app_norm choice i
    app_norm=$(normalize_name "$app")

    local -a all=() matched=()
    mapfile -t all < <(find "$dir" -type f -executable \
        ! -name "*.so*" \
        ! -name "chrome-sandbox" ! -name "chrome_crashpad_handler" \
        ! -name "crashpad_handler" ! -name "jspawnhelper" 2>/dev/null)
    [ ${#all[@]} -gt 0 ] || return 1

    for f in "${all[@]}"; do
        basename "$f" | grep -qi appimage && { SELECTED_EXEC="$f"; return 0; }
    done

    for f in "${all[@]}"; do
        base_norm=$(normalize_name "$(basename "$f")")
        [ "$base_norm" = "$app_norm" ] && matched+=("$f")
    done

    if [ ${#matched[@]} -eq 0 ]; then
        for f in "${all[@]}"; do
            base_norm=$(normalize_name "$(basename "$f")")
            [[ "$base_norm" == *"$app_norm"* ]] && matched+=("$f")
        done
    fi

    if [ ${#matched[@]} -ge 1 ]; then
        # در بسته‌های Electron، فایل بدون پسوند .bin راه‌انداز اصلی است
        for f in "${matched[@]}"; do
            [[ "$f" != *.bin ]] && { SELECTED_EXEC="$f"; return 0; }
        done
        SELECTED_EXEC="${matched[0]}"
        return 0
    fi

    if [ ${#all[@]} -eq 1 ]; then
        SELECTED_EXEC="${all[0]}"
        return 0
    fi

    if [ "${UO_AUTO:-0}" = "1" ]; then
        warn "چند فایل اجرایی هم‌ارزش — نخستین انتخاب شد: $(basename "${all[0]}")"
        SELECTED_EXEC="${all[0]}"
        return 0
    fi
    warn "چند فایل اجرایی پیدا شد؛ کدام‌یک برنامه اصلی است؟"
    i=1
    for f in "${all[@]}"; do
        echo "   $i) $(realpath --relative-to="$dir" "$f" 2>/dev/null || basename "$f")"
        ((i++))
    done
    read -r -p "   شماره فایل اجرایی اصلی: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#all[@]}" ]; then
        SELECTED_EXEC="${all[$((choice-1))]}"
        return 0
    fi
    return 1
}

# نگاشت کتابخانه گمشده به بسته deb — چند نام برای نسخه‌های مختلف اوبونتو
lib_pkg_candidates() {
    case "$1" in
        libwebkit2gtk-4.0*|libjavascriptcoregtk-4.0*) echo "libwebkit2gtk-4.0-37" ;;
        libwebkit2gtk-4.1*|libjavascriptcoregtk-4.1*) echo "libwebkit2gtk-4.1-0" ;;
        libfuse.so.2)             echo "libfuse2t64 libfuse2" ;;
        libgtk-3.so.0)            echo "libgtk-3-0t64 libgtk-3-0" ;;
        libgtk-4.so.1)            echo "libgtk-4-1" ;;
        libnss3.so)               echo "libnss3" ;;
        libasound.so.2)           echo "libasound2t64 libasound2" ;;
        libXss.so.1)              echo "libxss1" ;;
        libgbm.so.1)              echo "libgbm1" ;;
        libatk-bridge*)           echo "libatk-bridge2.0-0t64 libatk-bridge2.0-0" ;;
        libayatana-appindicator*) echo "libayatana-appindicator3-1" ;;
        *) echo "" ;;
    esac
}

# بررسی وابستگی‌های گمشده با ldd و نصب خودکار
fix_binary_deps() {   # $1 = مسیر فایل اجرایی
    local bin="$1" out missing lib pkgs pkg sibling
    # اگر فایل اسکریپت راه‌انداز است، باینری واقعی (.bin) کنارش بررسی می‌شود
    if head -c 2 "$bin" 2>/dev/null | grep -q '#!'; then
        sibling=$(find "$(dirname "$bin")" -maxdepth 1 -type f \
                  -name "$(basename "$bin").bin" 2>/dev/null | head -1)
        [ -n "$sibling" ] && bin="$sibling"
    fi

    out=$(ldd "$bin" 2>&1)
    echo "$out" | grep -q "not a dynamic executable" && return 0

    missing=$(echo "$out" | grep "not found" | awk '{print $1}' | sort -u)
    [ -z "$missing" ] && return 0

    warn "این کتابخانه‌ها روی سیستم نیستند:"
    printf '      • %s\n' $missing

    for lib in $missing; do
        for pkg in $(lib_pkg_candidates "$lib"); do
            if apt-cache show "$pkg" > /dev/null 2>&1; then
                if sudo apt install -y "$pkg" > /dev/null 2>&1; then
                    success "نصب شد: $pkg"
                    break
                fi
            fi
        done
    done

    missing=$(ldd "$bin" 2>/dev/null | grep "not found" | awk '{print $1}' | sort -u)
    if [ -z "$missing" ]; then
        success "همه وابستگی‌ها آماده‌اند."
        return 0
    fi
    failure "این کتابخانه‌ها هنوز نصب نشده‌اند:"
    printf '      • %s\n' $missing
    info "راهنما: apt search <بخشی از نام کتابخانه>"
    return 1
}

# بررسی سازگاری معماری بسته با سیستم
check_package_arch() {   # $1 = ریشه نصب  $2 = فایل اجرایی اصلی
    local root="$1" target="$2" f info arch sys_arch compatible

    command -v file > /dev/null 2>&1 || sudo apt install -y file > /dev/null 2>&1
    command -v file > /dev/null 2>&1 || { info "ابزار file در دسترس نیست؛ بررسی معماری رد شد."; return 0; }

    # اگر اجرایی اصلی اسکریپت است، نخستین باینری ELF بسته بررسی می‌شود
    if head -c 2 "$target" 2>/dev/null | grep -q '#!'; then
        while IFS= read -r f; do
            if file -b "$f" 2>/dev/null | grep -q 'ELF'; then
                target="$f"
                break
            fi
        done < <(find "$root" -type f -executable ! -name "*.so*" \
                    ! -name "chrome-sandbox" ! -name "chrome_crashpad_handler" \
                    ! -name "jspawnhelper" 2>/dev/null)
    fi

    info=$(file -b "$target" 2>/dev/null)
    echo "$info" | grep -q 'ELF' || return 0

    sys_arch=$(uname -m)
    if   echo "$info" | grep -q 'x86-64';  then arch="x86_64"
    elif echo "$info" | grep -q 'aarch64'; then arch="aarch64"
    elif echo "$info" | grep -q 'ARM,';    then arch="arm"
    elif echo "$info" | grep -q '80386';   then arch="i386"
    else return 0; fi

    compatible="no"
    case "$sys_arch" in
        x86_64)  if [ "$arch" = "x86_64" ] || [ "$arch" = "i386" ]; then compatible="yes"; fi ;;
        aarch64) if [ "$arch" = "aarch64" ]; then compatible="yes"; fi ;;
        *)       compatible="yes" ;;
    esac
    [ "$compatible" = "yes" ] && return 0

    failure "ناسازگاری معماری بسته با سیستم!"
    warn "معماری بسته: $arch  |  معماری سیستم: $sys_arch"
    case "$sys_arch" in
        x86_64)  warn "→ نسخه «amd64» یا «x64» برنامه را دانلود کنید." ;;
        aarch64) warn "→ نسخه «arm64» یا «aarch64» برنامه را دانلود کنید." ;;
    esac
    return 1
}

# نصب برنامه از فایل tar.gz — منطق مشترک نصب و به‌روزرسانی
targz_install_from_file() {   # $1=مسیر فایل  $2=نام برنامه
    local TARGZ_PATH="$1" APP_NAME="$2"

    local TEMP_DIR SRC_DIR n first
    TEMP_DIR=$(mktemp -d) || return 1
    info "استخراج فایل..."
    tar -xzf "$TARGZ_PATH" -C "$TEMP_DIR" || { failure "خطا در استخراج فایل."; rm -rf "$TEMP_DIR"; return 1; }
    success "فایل استخراج شد."

    # تشخیص ساختار آرشیو: پوشه ریشه تکی یا فایل‌های سطح بالا
    n=$(ls -A "$TEMP_DIR" | wc -l)
    first=$(ls -A "$TEMP_DIR" | head -1)
    if [ "$n" -eq 1 ] && [ -d "$TEMP_DIR/$first" ]; then
        SRC_DIR="$TEMP_DIR/$first"
    else
        SRC_DIR="$TEMP_DIR"
    fi

    if ! pick_executable "$SRC_DIR" "$APP_NAME"; then
        failure "فایل اجرایی اصلی پیدا نشد. محتوای بسته:"
        ls -la "$SRC_DIR"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    local EXEC_FILE="$SELECTED_EXEC"
    info "فایل اجرایی اصلی: $EXEC_FILE"

    local INSTALL_DIR="/opt/$APP_NAME"
    if [ -d "$INSTALL_DIR" ]; then
        warn "پوشه $INSTALL_DIR از قبل وجود دارد."
        if [ "${UO_AUTO:-0}" = "1" ]; then
            info "(حذف و نصب مجدد خودکار)"
            sudo rm -rf "$INSTALL_DIR"
        elif confirm_action "حذف و نصب مجدد شود؟"; then
            sudo rm -rf "$INSTALL_DIR"
        else
            info "لغو شد."
            rm -rf "$TEMP_DIR"
            return 0
        fi
    fi

    sudo mv "$SRC_DIR" "$INSTALL_DIR"
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    success "برنامه به $INSTALL_DIR منتقل شد."

    local FINAL_EXEC="$INSTALL_DIR${EXEC_FILE#$SRC_DIR}"

    if ! check_package_arch "$INSTALL_DIR" "$FINAL_EXEC"; then
        warn "نصب لغو شد؛ فایل‌های ناقص پاک می‌شوند."
        sudo rm -rf "$INSTALL_DIR"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    fix_binary_deps "$FINAL_EXEC"

    sudo ln -sf "$FINAL_EXEC" "/usr/local/bin/$APP_NAME"
    success "دستور اجرا: /usr/local/bin/$APP_NAME"

    # آیکون: بزرگ‌ترین تصویر موجود در بسته
    local ICON_FILE
    ICON_FILE=$(find "$INSTALL_DIR" -type f \( -iname "*.png" -o -iname "*.svg" \) \
                -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    ICON_FILE=${ICON_FILE:-applications-other}

    local DESKTOP_FILE="/usr/share/applications/$APP_NAME.desktop"
    cat << EOF | sudo tee "$DESKTOP_FILE" > /dev/null
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Installed by Ubuntu Optimizer
Exec="$FINAL_EXEC"
Path="$INSTALL_DIR"
Icon="$ICON_FILE"
Terminal=false
Categories=Utility;
EOF
    command -v update-desktop-database > /dev/null 2>&1 \
        && sudo update-desktop-database > /dev/null 2>&1

    rm -rf "$TEMP_DIR"

    registry_add "$APP_NAME" "$(guess_version "$TARGZ_PATH")" \
                 "$INSTALL_DIR" "$FINAL_EXEC" "$DESKTOP_FILE" "$(basename "$TARGZ_PATH")"

    success "🎉 نصب/به‌روزرسانی $APP_NAME کامل شد."
    info "اجرای از ترمینال: $APP_NAME"

    # اجرای آزمایشی فقط در حالت تعاملی
    if [ "${UO_AUTO:-0}" = "1" ]; then
        info "(اجرای آزمایشی در حالت خودکار رد شد)"
    elif confirm_action "همین حالا اجرا شود تا از کارکردش مطمئن شویم؟"; then
        (cd "$INSTALL_DIR" && nohup "$FINAL_EXEC" > /dev/null 2>&1 &)
        info "اگر پنجره‌ای باز نشد، در ترمینال «$APP_NAME» را اجرا کنید تا خطا را ببینید."
    fi
    return 0
}

# نصب تعاملی از منو
install_targz() {
    header "نصب برنامه از فایل .tar.gz"
    echo "   برای برنامه‌هایی که فقط فایل فشرده منتشر می‌کنند."
    echo "   • تشخیص خودکار فایل اجرایی اصلی"
    echo "   • بررسی معماری بسته با سیستم"
    echo "   • نصب خودکار وابستگی‌های گمشده"
    echo "   • ثبت در رجیستری (برای حذف و به‌روزرسانی بعدی)"
    echo ""

    local TARGZ_PATH APP_NAME
    read -r -p "   مسیر کامل فایل .tar.gz (مثلاً ~/Downloads/app.tar.gz): " TARGZ_PATH
    TARGZ_PATH=${TARGZ_PATH/#\~/$HOME}
    [ -f "$TARGZ_PATH" ] || { failure "فایل پیدا نشد: $TARGZ_PATH"; return 1; }
    [[ "$TARGZ_PATH" =~ \.tar\.gz$ ]] || { failure "پسوند فایل باید .tar.gz باشد."; return 1; }

    read -r -p "   نام برنامه (مثلاً abdownloadmanager): " APP_NAME
    [ -n "$APP_NAME" ] || { failure "نام برنامه وارد نشد."; return 1; }
    APP_NAME=$(printf '%s' "$APP_NAME" | tr -cd '[:alnum:]_-')

    targz_install_from_file "$TARGZ_PATH" "$APP_NAME"
}

# نصب از حالت CLI — $1=مسیر فایل  $2=نام اختیاری
install_targz_cli() {
    local TARGZ_PATH="$1" APP_NAME="$2"

    TARGZ_PATH=${TARGZ_PATH/#\~/$HOME}
    [ -f "$TARGZ_PATH" ] || { failure "فایل پیدا نشد: $TARGZ_PATH"; return 1; }
    [[ "$TARGZ_PATH" =~ \.tar\.gz$ ]] || { failure "پسوند فایل باید .tar.gz باشد."; return 1; }

    if [ -z "$APP_NAME" ]; then
        APP_NAME=$(name_from_archive "$TARGZ_PATH")
        if [ -z "$APP_NAME" ]; then
            failure "نام برنامه از نام فایل قابل تشخیص نبود."
            info "نام را صریح بدهید: --install-targz <فایل> <نام>"
            return 1
        fi
        info "نام تشخیص داده‌شده از فایل: $APP_NAME"
    fi
    APP_NAME=$(printf '%s' "$APP_NAME" | tr -cd '[:alnum:]_-')

    targz_install_from_file "$TARGZ_PATH" "$APP_NAME"
}
