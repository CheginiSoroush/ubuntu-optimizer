# ============================================================
#   lib/github.sh — نصب و به‌روزرسانی برنامه‌ها از GitHub Releases
#   نویسنده و طراح: Soroush Chegini (CheginiSoroush)
#
#   جریان نصب: دریافت آخرین release → انتخاب خودکار فایل →
#   دانلود موقت → نصب → ثبت در github.db → حذف فایل دانلودی.
#   به‌روزرسانی: تنها یک سؤال به‌ازای هر برنامه؛ پس از تأیید،
#   بقیه مراحل خودکار است.
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

# آیا برنامه در بانک گیت‌هاب ثبت شده است؟
gh_db_has() {   # $1=name
    [ -f "$GITHUB_DB" ] || return 1
    grep -q "^${1}|" "$GITHUB_DB" 2>/dev/null
}

# ---------- دریافت آخرین release ----------
# خروجی: GH_TAG (نسخه) و آرایه GH_URLS (آدرس فایل‌های release)
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
        warn "محدودیت API گیت‌هاب (۶۰ درخواست در ساعت بدون توکن) — بعداً تلاش کنید."
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

# ---------- انتخاب خودکار فایل مناسب ----------
# امتیازدهی:
#   معماری مطابق سیستم +40 | فرمت deb +10 | tar.gz/tgz +5
#   بدون برچسب معماری -15  | musl -8       | معماری ناسازگار -200
# بالاترین امتیاز انتخاب می‌شود؛ در تساوی، نخستین فایل.
gh_pick_asset() {
    GH_PICKED_URL=""
    local sys_arch
    sys_arch=$(uname -m)

    local -a urls=() scores=()
    local u f low score best i

    for u in "${GH_URLS[@]}"; do
        f=$(basename "$u")
        low=${f,,}
        score=0

        # فرمت
        case "$low" in
            *.deb)          score=$((score + 10)) ;;
            *.tar.gz|*.tgz) score=$((score + 5)) ;;
            *)              continue ;;
        esac

        # معماری
        if [ "$sys_arch" = "x86_64" ]; then
            case "$low" in
                *amd64*|*x86_64*|*x64*)     score=$((score + 40)) ;;
                *i386*|*i686*|*80386*|*x86*) score=$((score + 20)) ;;
                *arm64*|*aarch64*|*armv5*|*armv6*|*armv7*|*arm*|*riscv64*|*ppc64le*|*s390x*|*loong64*) score=$((score - 200)) ;;
                *)                          score=$((score - 15)) ;;
            esac
        elif [ "$sys_arch" = "aarch64" ]; then
            case "$low" in
                *arm64*|*aarch64*)           score=$((score + 40)) ;;
                *armv5*|*armv6*|*armv7*|*arm*) score=$((score + 20)) ;;
                *amd64*|*x86_64*|*x64*|*i386*|*i686*|*riscv64*|*ppc64le*|*s390x*|*loong64*) score=$((score - 200)) ;;
                *)                           score=$((score - 15)) ;;
            esac
        else
            case "$low" in
                *arm64*|*aarch64*|*amd64*|*x86_64*|*x64*|*armv5*|*armv6*|*armv7*|*riscv64*|*ppc64le*|*s390x*|*loong64*)
                    score=$((score - 200)) ;;
            esac
        fi

        [[ "$low" == *musl* ]] && score=$((score - 8))
        [ "$score" -le -100 ] && continue

        urls+=("$u")
        scores+=("$score")
    done

    if [ ${#urls[@]} -eq 0 ]; then
        failure "فایل نصبی سازگار با سیستم پیدا نشد."
        info "فایل‌های این release (برای بررسی/نصب دستی):"
        for u in "${GH_URLS[@]}"; do
            echo "      • $(basename "$u")"
        done
        return 1
    fi

    best=0
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" -gt "${scores[$best]}" ] && best=$i
    done
    local -a ties=()
    for i in "${!scores[@]}"; do
        [ "${scores[$i]}" = "${scores[$best]}" ] && ties+=("$i")
    done
    [ ${#ties[@]} -gt 1 ] && info "(چند فایل هم‌امتیاز — نخستین انتخاب شد)"

    GH_PICKED_URL="${urls[$best]}"
    return 0
}

# ---------- دانلود، نصب، ثبت و پاک‌کردن فایل موقت ----------
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
        # نصب tar.gz در حالت خودکار — بدون سؤال تعاملی
        UO_AUTO=1
        if targz_install_from_file "$tmpfile" "$name"; then
            installed=1
        fi
        unset UO_AUTO
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

# ---------- نصب برنامه از گیت‌هاب (کاملاً خودکار) ----------
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

# ---------- حذف برنامه گیت‌هابی ----------
# حذف خود برنامه از سیستم (تمام منابع) + حذف رد از بانک گیت‌هاب
# در یک عملیات. رد tar.gz توسط cleanup_app خودکار حذف می‌شود.
github_remove_app() {   # $1 اختیاری = نام برنامه
    header "🐙 حذف برنامه از گیت‌هاب"

    local raw
    if [ -n "${1:-}" ]; then
        raw="$1"
    else
        if [ -s "$GITHUB_DB" ]; then
            info "برنامه‌های ردیابی‌شده:"
            awk -F'|' '{printf "      • %s (%s) ← %s\n", $1, $3, $2}' "$GITHUB_DB"
            echo ""
        fi
        read -r -p "   نام برنامه برای حذف: " raw
    fi
    [ -z "$raw" ] && { failure "نام وارد نشد."; return 1; }

    if ! gh_db_has "$raw"; then
        failure "برنامه‌ای با نام «$raw» در فهرست گیت‌هاب نیست."
        info "فهرست فعلی: uo --github-list"
        return 1
    fi

    # حذف خود برنامه از سیستم — همه منابع، با داده‌های کاربری
    if ! cleanup_app "$raw"; then
        warn "برنامه از سیستم حذف نشد — رد گیت‌هاب نگه داشته می‌شود."
        return 1
    fi

    gh_db_remove "$raw"
    success "رد «$raw» از فهرست ردیابی گیت‌هاب حذف شد."
    return 0
}

# ---------- بررسی به‌روزرسانی ----------
# تنها سؤال به‌ازای هر برنامه: «به‌روزرسانی شود؟» — پس از تأیید،
# دانلود و نصب خودکار است و در صورت رد، برنامه بعدی بررسی می‌شود
github_update_apps() {
    header "🔄 بررسی به‌روزرسانی برنامه‌های گیت‌هاب"

    if [ ! -s "$GITHUB_DB" ]; then
        info "هنوز برنامه‌ای از گیت‌هاب نصب/ردیابی نشده است."
        info "نصب: uo --github-install OWNER/REPO"
        return 0
    fi

    # اسنپ‌شات کامل بانک پیش از حلقه — read های تعاملی نباید
    # خطوط خود فایل را مصرف کنند
    local -a lines=()
    mapfile -t lines < "$GITHUB_DB"

    local line name repo tag latest
    for line in "${lines[@]}"; do
        IFS='|' read -r name repo tag <<< "$line"
        [ -z "$name" ] && continue

        echo ""
        info "برنامه: $name (نصب‌شده: ${tag:-نامشخص}) ← $repo"

        # خودترمیمی: برنامه حذف‌شده از فهرست ردیابی خارج می‌شود
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

        info "نسخه جدید موجود است: $latest (فعلی: ${tag:-نامشخص})"
        if ! confirm_action "«$name» به $latest به‌روزرسانی شود؟"; then
            info "رد شد — ادامه با برنامه بعدی."
            continue
        fi

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
