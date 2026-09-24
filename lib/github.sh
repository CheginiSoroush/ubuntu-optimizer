# ============================================================
#   lib/github.sh — نصب و به‌روزرسانی برنامه‌ها از GitHub Releases
#   جریان: دریافت آخرین release → انتخاب خودکار هوشمند فایل
#   (امتیازدهی معماری/فرمت — بدون سؤال در حالت عادی) → دانلود
#   موقت → نصب → ثبت در github.db → حذف فایل دانلودی
#
#   فیکس v5.5: باگ فیلتر معماری — الگوهای armv5/armv6/armv7 و
#   i386 و غیره به‌عنوان «خنثی» رد می‌شدند و لیست چندتایی
#   ساخته می‌شد؛ حالا انتخاب کاملاً خودکار با امتیاز است.
# ============================================================

readonly GITHUB_DB="$REGISTRY_DIR/github.db"

# ---------- بانک برنامه‌های گیت‌هاب ----------
# فرمت هر خط: name|owner/repo|installed_tag

gh_db_add() {   # $1=name $2=repo $3=tag
    mkdir -p "$REGISTRY_DIR"
    touch "$GITHUB_DB"
    local tmp="$GITHUB_DB.tmp"
    awk -F'|' -v n="$1" '$1 != n' "$GITHUB_DB" > "$tmp" 2>/dev/null
    echo "$1|$2|$3" >> "$tmp"
    mv "$tmp" "$GITHUB_DB"
}

gh_db_remove() {   # $1=name
    [ -f "$GITHUB_DB" ] || return 0
    local tmp="$GITHUB_DB.tmp"
    awk -F'|' -v n="$1" '$1 != n' "$GITHUB_DB" > "$tmp" 2>/dev/null
    mv "$tmp" "$GITHUB_DB"
}

# ---------- دریافت اطلاعات آخرین release ----------
# نتیجه: GH_TAG و آرایه GH_URLS (آدرس فایل‌های release)
gh_fetch_latest() {   # $1 = OWNER/REPO یا URL کامل
    GH_TAG=""
    GH_URLS=()

    if ! command -v curl > /dev/null 2>&1; then
        info "نصب curl..."
        sudo apt install -y curl > /dev/null 2>&1 || { failure "خطا در نصب curl."; return 1; }
    fi

    local repo="$1" resp
    repo=${repo#https://github.com/}
    repo=${repo#git@github.com:}
    repo=${repo%/}

    if ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        failure "قالب مخزن نامعتبر: «$repo»"
        info "قالب صحیح: OWNER/REPO یا https://github.com/OWNER/REPO"
        return 1
    fi

    info "بررسی آخرین release از $repo ..."
    resp=$(curl -sSL --connect-timeout 15 --max-time 30 \
        "https://api.github.com/repos/${repo}/releases/latest" 2>&1)

    if printf '%s' "$resp" | grep -q '"message": *"Not Found"'; then
        failure "مخزن پیدا نشد یا release عمومی ندارد (404)."
        info "نام مخزن را بررسی کنید: $repo"
        return 1
    fi
    if printf '%s' "$resp" | grep -qi 'rate limit'; then
        warn "محدودیت API گیت‌هاب (۶۰ درخواست در ساعت برای بدون توکن) — بعداً تلاش کنید."
        return 1
    fi

    if command -v jq > /dev/null 2>&1; then
        GH_TAG=$(printf '%s' "$resp" | jq -r '.tag_name // empty')
        mapfile -t GH_URLS < <(printf '%s' "$resp" | jq -r '.assets[].browser_download_url' 2>/dev/null)
    else
        GH_TAG=$(printf '%s' "$resp" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
        mapfile -t GH_URLS < <(printf '%s' "$resp" | grep -o '"browser_download_url": *"[^"]*"' | sed 's/.*: *"//; s/"$//')
    fi

    if [ -z "$GH_TAG" ]; then
        failure "پاسخ API قابل پردازش نبود (مخزن خصوصی؟)."
        return 1
    fi
    return 0
}

# ---------- انتخاب خودکار فایل مناسب (امتیازدهی) ----------
# امتیاز هر فایل:
#   معماری:  +۴۰ نام معماری سیستم دقیق | +۳۰ معماری ۶۴ بیتی سازگار
#            | -۲۰۰ معماری غیرسازگار (رد قطعی)
#   فرمت:    +۱۰ .deb | +۵ .tar.gz/.tgz | -۲۰۰ سایر (رد قطعی)
#   جریمه‌ها: -۱۵ بدون برچسب معماری (مثل universal) | -۸ musl
# انتخاب: بالاترین امتیاز — فقط اگر چند فایل «امتیاز مساوی مثبت»
# داشتند و اطلاعات کافی برای تمایز نبود، سؤال پرسیده می‌شود.
gh_pick_asset() {
    GH_PICKED_URL=""
    local sys_arch
    sys_arch=$(uname -m)

    local -a urls=() scores=()
    local u f low score best i choice

    for u in "${GH_URLS[@]}"; do
        f=$(basename "$u")
        low=${f,,}
        score=0

        # --- فرمت ---
        case "$low" in
            *.deb)      score=$((score + 10)) ;;
            *.tar.gz|*.tgz) score=$((score + 5)) ;;
            *)          continue ;;   # فرمت نامعتبر — رد
        esac

        # --- معماری (چند الگو برای هر خانواده) ---
        # سازگار با سیستم فعلی
        if [ "$sys_arch" = "x86_64" ]; then
            case "$low" in
                *amd64*|*x86_64*|*x64*)       score=$((score + 40)) ;;
                *i386*|*i686*|*80386*|*x86*)   score=$((score + 20)) ;;
                *arm64*|*aarch64*|*armv5*|*armv6*|*armv7*|*arm*|*riscv64*|*ppc64le*|*s390x*|*loong64*|*universal*|*all*) score=$((score - 200)) ;;
                *)                             score=$((score - 15)) ;;  # بدون برچسب معماری
            esac
        elif [ "$sys_arch" = "aarch64" ]; then
            case "$low" in
                *arm64*|*aarch64*)             score=$((score + 40)) ;;
                *armv5*|*armv6*|*armv7*|*arm*)  score=$((score + 20)) ;;
                *amd64*|*x86_64*|*x64*|*i386*|*i686*|*riscv64*|*ppc64le*|*s390x*|*loong64*) score=$((score - 200)) ;;
                *)                             score=$((score - 15)) ;;
            esac
        else
            # معماری ناشناخته — فقط برچسب‌های خنثی مجاز
            case "$low" in
                *arm64*|*aarch64*|*amd64*|*x86_64*|*x64*|*armv5*|*armv6*|*armv7*|*riscv64*|*ppc64le*|*s390x*|*loong64*)
                    score=$((score - 200)) ;;
            esac
        fi

        # --- جریمه‌های ریز ---
        [[ "$low" == *musl* ]] && score=$((score - 8))

        # --- رد قطعی‌ها ---
        [ "$score" -le -100 ] && continue

        urls+=("$u")
        scores+=("$score")
    done

    if [ ${#urls[@]} -eq 0 ]; then
        # هیچ فایل امتیاز مثبت نگرفت — انتخاب دستی از همه (آخرین راه نجات)
        if [ ${#GH_URLS[@]} -eq 0 ]; then
            failure "این release هیچ فایل نصبی (asset) ندارد — فقط سورس است."
            return 1
        fi
        warn "هیچ فایل به‌طور خودکار قابل تشخیص نبود؛ همه فایل‌ها:"
        i=1
        for u in "${GH_URLS[@]}"; do
            echo "   $i) $(basename "$u")"
            ((i++))
        done
        read -r -p "   شماره (0=انصراف): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#GH_URLS[@]} ]; then
            u="${GH_URLS[$((choice-1))]}"
            case "$(basename "$u")" in
                *.deb|*.tar.gz|*.tgz|*.DEB|*.TAR.GZ|*.TGZ)
                    GH_PICKED_URL="$u"
                    return 0
                    ;;
                *)
                    failure "این فرمت پشتیبانی نمی‌شود: $(basename "$u") (فقط .deb و .tar.gz)"
                    return 1
                    ;;
            esac
        fi
        return 1
    fi

    # بالاترین امتیاز
    best=0
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" -gt "${scores[$best]}" ] && best=$i
    done
    GH_PICKED_URL="${urls[$best]}"

    # اگر تنها فایلِ با بالاترین امتیاز نیست و رقیب هم‌امتیاز مثبت دارد → سؤال
    local -a ties=()
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" = "${scores[$best]}" ] && ties+=("$i")
    done
    if [ ${#ties[@]} -eq 1 ]; then
        return 0
    fi

    # مساوی — در حالت -y اولین، وگرنه سؤال
    if [ "$CLI_MODE" = "1" ] && [ "$ASSUME_YES" = "1" ]; then
        info "(انتخاب خودکار اولین فایل هم‌امتیاز با -y)"
        return 0
    fi
    info "چند فایل کاملاً هم‌ارزش پیدا شد؛ کدام نصب شود؟"
    i=1
    for idx in "${ties[@]}"; do
        echo "   $i) $(basename "${urls[$idx]}")"
        ((i++))
    done
    local -a tie_urls=()
    for idx in "${ties[@]}"; do
        tie_urls+=("${urls[$idx]}")
    done
    read -r -p "   شماره (0=انصراف): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#tie_urls[@]} ]; then
        GH_PICKED_URL="${tie_urls[$((choice-1))]}"
        return 0
    fi
    return 1
}

# ---------- دانلود + نصب + ثبت + پاک‌کردن فایل موقت ----------
gh_download_and_install() {   # $1=url $2=name $3=repo $4=tag
    local url="$1" name="$2" repo="$3" tag="$4"
    local base ext tmpfile installed=0

    base=$(basename "$url")
    case "${base,,}" in
        *.deb) ext=".deb" ;;
        *.tgz) ext=".tgz" ;;
        *)     ext=".tar.gz" ;;
    esac
    tmpfile="/tmp/uo-github-${name}${ext}"

    info "دانلود $base ..."
    if ! curl -fL --connect-timeout 15 --progress-bar -o "$tmpfile" "$url"; then
        failure "دانلود ناموفق بود."
        rm -f "$tmpfile"
        return 1
    fi
    success "دانلود کامل شد."

    if [ "$ext" = ".deb" ]; then
        info "نصب بسته deb ..."
        if sudo apt install -y "$tmpfile" > /dev/null 2>&1; then
            installed=1
        else
            warn "نصب با apt ناموفق؛ تلاش با dpkg ..."
            if sudo dpkg -i "$tmpfile" 2>/dev/null; then
                sudo apt --fix-broken install -y > /dev/null 2>&1
                installed=1
            fi
        fi
    else
        # tar.gz/tgz — نصب هوشمند (رجیستری + معماری + وابستگی‌ها)
        if targz_install_from_file "$tmpfile" "$name"; then
            installed=1
        fi
    fi

    if [ "$installed" = "1" ]; then
        gh_db_add "$name" "$repo" "$tag"
        rm -f "$tmpfile"
        success "فایل دانلودی پاک شد: $tmpfile"
        return 0
    fi
    failure "نصب ناموفق بود — فایل برای بررسی نگه داشته شد: $tmpfile"
    return 1
}

# ---------- نصب برنامه از گیت‌هاب ----------
github_install_repo() {   # $1=repo (اختیاری در منو)  $2=نام اختیاری
    header "🐙 نصب برنامه از گیت‌هاب"

    local repo="$1" name="$2"

    if [ -z "$repo" ]; then
        read -r -p "   مخزن (OWNER/REPO یا لینک کامل github.com/OWNER/REPO): " repo
    fi
    [ -z "$repo" ] && { failure "مخزن وارد نشد."; return 1; }

    repo=${repo#https://github.com/}
    repo=${repo#git@github.com:}
    repo=${repo%/}

    if ! [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        failure "قالب مخزن نامعتبر: «$repo»"
        info "مثال درست: amir1376/ab-download-manager"
        return 1
    fi

    if [ -z "$name" ]; then
        name=$(basename "$repo")
        info "نام برنامه (از مخزن): $name"
    fi
    name=$(printf '%s' "$name" | tr -cd '[:alnum:]_-')

    if ! gh_fetch_latest "$repo"; then
        return 1
    fi
    info "آخرین نسخه: $GH_TAG"

    if ! gh_pick_asset; then
        return 1
    fi
    info "فایل انتخاب‌شده: $(basename "$GH_PICKED_URL")"

    gh_download_and_install "$GH_PICKED_URL" "$name" "$repo" "$GH_TAG"
}

# ---------- بررسی به‌روزرسانی برنامه‌های گیت‌هاب ----------
github_update_apps() {
    header "🔄 بررسی به‌روزرسانی برنامه‌های گیت‌هاب"

    if [ ! -s "$GITHUB_DB" ]; then
        info "هنوز برنامه‌ای از گیت‌هاب نصب/ردیابی نشده است."
        info "نصب: uo --github-install OWNER/REPO"
        return 0
    fi

    # اسنپ‌شات یک‌جا از بانک (درس آموخته‌شده از باگ stdin!)
    local -a lines=()
    mapfile -t lines < "$GITHUB_DB"

    local line name repo tag latest
    for line in "${lines[@]}"; do
        IFS='|' read -r name repo tag <<< "$line"
        [ -z "$name" ] && continue

        echo ""
        info "برنامه: $name (نصب‌شده: ${tag:-نامشخص}) ← $repo"

        # خودترمیمی: اگر برنامه دیگر نصب نیست، از فهرست حذف شود
        if ! grep -q "^${name}|" "$REGISTRY_DB" 2>/dev/null \
           && ! pkg_installed "$name" \
           && [ ! -d "/opt/$name" ]; then
            warn "این برنامه دیگر نصب نیست — از فهرست ردیابی حذف شد."
            gh_db_remove "$name"
            continue
        fi

        if ! gh_fetch_latest "$repo"; then
            warn "دریافت اطلاعات $repo ناموفق — رد شد."
            continue
        fi
        latest=$GH_TAG

        if [ "${latest#v}" = "${tag#v}" ]; then
            success "به‌روز است ($latest)."
            continue
        fi

        info "نسخه جدید موجود است: $latest"
        if ! gh_pick_asset; then
            continue
        fi
        gh_download_and_install "$GH_PICKED_URL" "$name" "$repo" "$latest"
    done
    return 0
}

# ---------- فهرست برنامه‌های گیت‌هابی ----------
github_list_apps() {
    header "🐙 برنامه‌های ردیابی‌شده از گیت‌هاب"
    if [ ! -s "$GITHUB_DB" ]; then
        info "(خالی) — نصب با: uo --github-install OWNER/REPO"
        return 0
    fi
    awk -F'|' '{printf "   %-24s %-14s %s\n", $1, ($3 == "" ? "-" : $3), $2}' "$GITHUB_DB"
    return 0
}
