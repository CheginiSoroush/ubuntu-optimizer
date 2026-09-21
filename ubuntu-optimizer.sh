#!/bin/bash

# ============================================================
#   Ubuntu Optimizer & Fixer - v5.2 (نسخه ماژولار)
#
#   فایل اصلی: بارگذاری ماژول‌ها + حالت CLI + منوی اصلی
#   جدید در v5.2:
#     + گزارش وضعیت سیستم (--report) — سلامت سیستم و
#       وضعیت بهینه‌سازی‌ها، فقط خواندنی
#     + نصب/مدیریت پروژه با install.sh جداگانه
#   v5.1: سیستم لاگ — ثبت خودکار عملیات + خلاصه پایان اجرا
#
#   ماژول‌ها در پوشه lib/ کنار همین فایل قرار دارند.
#   اجرای مستقیم فایل‌های lib/ ممکن نیست — همیشه از همین فایل اجرا کن.
# ============================================================

# مسیر پوشه‌ی اسکریپت (مستقل از اینکه از کجا اجرا شود یا symlink باشد)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ---------- بارگذاری ماژول‌ها ----------
for _lib in common network system fixnet packages targz appmgmt snapflatpak recovery report menus; do
    _libfile="$SCRIPT_DIR/lib/${_lib}.sh"
    if [ -f "$_libfile" ]; then
        # shellcheck source=/dev/null
        source "$_libfile"
    else
        echo "✗ ماژول پیدا نشد: lib/${_lib}.sh"
        echo "  ℹ همه فایل‌ها باید در ساختار پوشه‌ای کنار هم باشند:"
        echo "    ubuntu-optimizer.sh + lib/*.sh"
        exit 1
    fi
done
unset _lib _libfile

# ---------- وضعیت اجرا ----------
ASSUME_YES=0
PURGE_DATA=0
CLI_MODE=0
CLEANUP_TARGET=""
CLI_ACTIONS=()
ORIG_ARGS="$*"   # آرگومان‌های اصلی برای ثبت در لاگ (قبل از مصرف توسط حلقه)

# ============================================================
#   راهنمای CLI
# ============================================================

usage() {
    cat << 'EOF'
Ubuntu Optimizer & Fixer - v5.2 (ماژولار)

استفاده:
  uo                          → منوی تعاملی
  uo [گزینه‌ها]               → حالت CLI (بدون منو)

گزینه‌ها:
  -h, --help          نمایش این راهنما
  -y, --yes           تأیید خودکار همه سؤال‌ها (با احتیاط!)
  --no-color          خروجی بدون رنگ

  --report            گزارش وضعیت سیستم (فقط خواندنی)

  --optimize          همه بهینه‌سازی‌های شبکه + سیستم
  --network           بهینه‌سازی شبکه (BBR, DNS, MTU, TCP)
  --system            بهینه‌سازی سیستم و حافظه
  --security          تنظیمات sudo timeout + polkit
  --time              همگام‌سازی زمان سیستم
  --fixnet            ساخت اسکریپت fixnet
  --fixnet-run        اجرای fixnet (رفع مشکل شبکه)
  --test              تست‌های شبکه (پینگ، DNS، سرعت)

  --update            به‌روزرسانی همه منابع (apt, snap, flatpak, tar.gz)
  --update-apt        فقط apt
  --update-snap       فقط snap
  --update-flatpak    فقط flatpak
  --update-targz      بررسی به‌روزرسانی برنامه‌های tar.gz

  --list-apps         لیست همه برنامه‌ها از همه منابع
  --cleanup NAME      حذف کامل برنامه NAME از هر منبعی که باشد
  --purge-data        (همراه --cleanup) حذف داده‌های کاربری هم
  --snap-clean        پاک‌سازی نسخه‌های قدیمی snap + unused فلت‌پک

  --log               نمایش آخرین خطوط لاگ فعالیت‌ها
  --log-clear         حذف کامل فایل لاگ
  --no-log            این اجرا در لاگ ثبت نشود

مثال‌ها:
  uo --report
  uo --optimize
  uo --update -y
  uo --cleanup abdownloadmanager --purge-data
EOF
}

# ============================================================
#   اجرای اصلی
# ============================================================

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}   ✗ این اسکریپت را بدون sudo اجرا کنید.${NC}"
    echo -e "${YELLOW}   ℹ خودش هنگام نیاز، رمز sudo می‌پرسد.${NC}"
    exit 1
fi

# خروج تمیز با Ctrl+C
trap 'echo ""; warn "خروج..."; exit 130' INT TERM

# ---------- پردازش آرگومان‌ها (حالت CLI) ----------
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)        usage; exit 0 ;;
        -y|--yes)         ASSUME_YES=1; shift ;;
        --no-color)       RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; BOLD=''; NC=''; shift ;;
        --no-log)         LOG_ENABLED=0; shift ;;
        --report)         CLI_ACTIONS+=("system_report|گزارش وضعیت سیستم"); shift ;;
        --log)
            if [ -f "$LOG_FILE" ]; then
                echo "── آخرین ۶۰ خط لاگ ──"
                tail -n 60 "$LOG_FILE"
            else
                echo "هنوز فایل لاگی وجود ندارد."
                echo "مسیر لاگ: $LOG_FILE"
            fi
            exit 0
            ;;
        --log-clear)
            if [ -f "$LOG_FILE" ]; then
                rm -f "$LOG_FILE" "$LOG_FILE.old"
                echo "لاگ حذف شد."
            else
                echo "فایل لاگی برای حذف وجود ندارد."
            fi
            exit 0
            ;;
        --optimize)       CLI_ACTIONS+=("all_network_opts|بهینه‌سازی شبکه" "all_system_opts|بهینه‌سازی سیستم"); shift ;;
        --network)        CLI_ACTIONS+=("all_network_opts|بهینه‌سازی شبکه"); shift ;;
        --system)         CLI_ACTIONS+=("all_system_opts|بهینه‌سازی سیستم"); shift ;;
        --security)       CLI_ACTIONS+=("all_security_opts|تنظیمات امنیتی"); shift ;;
        --time)           CLI_ACTIONS+=("fix_time|همگام‌سازی زمان"); shift ;;
        --fixnet)         CLI_ACTIONS+=("create_fixnet_script|ساخت fixnet"); shift ;;
        --fixnet-run)     CLI_ACTIONS+=("run_fixnet|اجرای fixnet"); shift ;;
        --test)           CLI_ACTIONS+=("all_tests|تست‌های شبکه"); shift ;;
        --update)         CLI_ACTIONS+=("update_all|به‌روزرسانی همه"); shift ;;
        --update-apt)     CLI_ACTIONS+=("update_apt|به‌روزرسانی apt"); shift ;;
        --update-snap)    CLI_ACTIONS+=("update_snap|به‌روزرسانی snap"); shift ;;
        --update-flatpak) CLI_ACTIONS+=("update_flatpak|به‌روزرسانی flatpak"); shift ;;
        --update-targz)   CLI_ACTIONS+=("update_targz_apps|به‌روزرسانی tar.gz"); shift ;;
        --list-apps)      CLI_ACTIONS+=("list_all_apps|لیست برنامه‌ها"); shift ;;
        --snap-clean)     CLI_ACTIONS+=("clean_snap_flatpak_junk|پاک‌سازی snap/flatpak"); shift ;;
        --purge-data)     PURGE_DATA=1; shift ;;
        --cleanup)
            if [ $# -ge 2 ]; then
                CLEANUP_TARGET="$2"; shift 2
            else
                echo "گزینه --cleanup نیاز به نام برنامه دارد: --cleanup <نام>"
                exit 1
            fi
            ;;
        *)
            echo "گزینه نامعتبر: $1"
            usage
            exit 1
            ;;
    esac
done

# ---------- اجرای حالت CLI ----------
if [ ${#CLI_ACTIONS[@]} -gt 0 ] || [ -n "$CLEANUP_TARGET" ]; then
    CLI_MODE=1
    log_session_start "cli" "$ORIG_ARGS"
    trap 'log_session_end; print_session_summary' EXIT
    echo -e "${BOLD}Ubuntu Optimizer & Fixer v5.2 — حالت CLI${NC}"
    cli_action=""
    for cli_action in "${CLI_ACTIONS[@]}"; do
        "${cli_action%%|*}"
    done
    if [ -n "$CLEANUP_TARGET" ]; then
        cleanup_app "$CLEANUP_TARGET"
    fi
    echo ""
    success "پایان — همه کارهای درخواستی انجام شد."
    exit 0
fi

# ---------- اجرای منوی تعاملی ----------
log_session_start "interactive"
trap 'log_session_end; print_session_summary' EXIT
main_menu