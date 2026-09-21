# ============================================================
#   lib/common.sh — رنگ‌ها، توابع کمکی، رجیستری و سیستم لاگ
#   (این فایل مستقیماً اجرا نمی‌شود؛ توسط فایل اصلی source می‌شود)
# ============================================================

# ---------- ثابت‌ها ----------
readonly SYSCTL_CONF="/etc/sysctl.d/99-ubuntu-optimizer.conf"
readonly JOURNALD_DROPIN="/etc/systemd/journald.conf.d/99-optimizer.conf"
readonly SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/99-optimizer-timeout"
readonly POLKIT_RULE_FILE="/etc/polkit-1/rules.d/10-disable-password-timeout.rules"
readonly REGISTRY_DIR="$HOME/.local/share/ubuntu-optimizer"
readonly REGISTRY_DB="$REGISTRY_DIR/apps.db"

# ---------- تنظیمات لاگ ----------
readonly LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-optimizer"
readonly LOG_FILE="$LOG_DIR/optimizer.log"
readonly LOG_MAX_BYTES=1048576   # ۱ مگابایت — بزرگ‌تر شد، لاگ چرخش می‌کند

LOG_ENABLED=1
LOG_OK_COUNT=0
LOG_FAIL_COUNT=0
LOG_WARN_COUNT=0

# ---------- رنگ‌ها ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
#   هسته‌ی سیستم لاگ
# ============================================================

# حذف کدهای رنگ ANSI از متن قبل از ذخیره در لاگ
_strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# چرخش لاگ: اگر از ۱ مگابایت بزرگ‌تر شد، نسخه فعلی → .old
_log_rotate() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.old"
    fi
    return 0
}

# نوشتن یک خط در لاگ — $1=سطح (OK/ERROR/WARN/INFO/SECTION/SESSION)  $2=پیام
log_write() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%s] %-8s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$(_strip_ansi "$2")" >> "$LOG_FILE"
}

# شروع نشست — $1=نوع اجرا (cli / interactive)  بقیه پارامترها=آرگومان‌ها
log_session_start() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    _log_rotate
    local mode="$1"
    shift
    local extra=""
    [ $# -gt 0 ] && extra=" | آرگومان‌ها: $*"
    log_write "SESSION" "════ شروع نشست ($mode)$extra ════"
}

# پایان نشست — ثبت خلاصه در لاگ
log_session_end() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    log_write "SESSION" "خلاصه نشست: موفق=$LOG_OK_COUNT  خطا=$LOG_FAIL_COUNT  هشدار=$LOG_WARN_COUNT"
    log_write "SESSION" "════ پایان نشست ════"
}

# چاپ خلاصه پایان اجرا در ترمینال
print_session_summary() {
    echo ""
    echo -e "${BOLD}── خلاصه این اجرا ──${NC}"
    echo -e "   ✓ موفق: $LOG_OK_COUNT     ✗ خطا: $LOG_FAIL_COUNT     ⚠ هشدار: $LOG_WARN_COUNT"
    if [ "$LOG_ENABLED" = "1" ]; then
        echo -e "   ℹ لاگ کامل: $LOG_FILE"
    fi
    return 0
}

# نمایش آخرین خطوط لاگ (پرچم --log و گزینه ۱۳ منو)
show_log() {
    header "📜 لاگ فعالیت‌ها (آخرین ۶۰ خط)"
    if [ -f "$LOG_FILE" ]; then
        tail -n 60 "$LOG_FILE"
        echo ""
        info "مسیر کامل: $LOG_FILE"
        [ -f "$LOG_FILE.old" ] && info "لاگ قدیمی (چرخش‌یافته): $LOG_FILE.old"
    else
        info "هنوز لاگی ثبت نشده است."
        info "لاگ در این مسیر ساخته می‌شود: $LOG_FILE"
    fi
    return 0
}

# ---------- خروجی (چاپ در ترمینال + ثبت همزمان در لاگ) ----------
success() {
    echo -e "${GREEN}   ✓ $1${NC}"
    LOG_OK_COUNT=$((LOG_OK_COUNT + 1))
    log_write "OK" "$1"
}

failure() {
    echo -e "${RED}   ✗ $1${NC}"
    LOG_FAIL_COUNT=$((LOG_FAIL_COUNT + 1))
    log_write "ERROR" "$1"
}

info() {
    echo -e "${YELLOW}   ℹ $1${NC}"
    log_write "INFO" "$1"
}

warn() {
    echo -e "${MAGENTA}   ⚠ $1${NC}"
    LOG_WARN_COUNT=$((LOG_WARN_COUNT + 1))
    log_write "WARN" "$1"
}

header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}   $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    log_write "SECTION" "$1"
}

press_enter() {
    if [ "$CLI_MODE" = "1" ]; then echo; return 0; fi
    echo ""
    read -r -p "   برای ادامه Enter بزنید..." _
}

# درخواست تأیید yes/no (در حالت -y خودکار تأیید می‌شود)
confirm_action() {
    if [ "$ASSUME_YES" = "1" ]; then
        info "(تأیید خودکار با -y)"
        return 0
    fi
    read -r -p "   $1 (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# آیا بسته deb نصب است؟
pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# تنظیم/به‌روزرسانی امن یک پارامتر sysctl در فایل اختصاصی اسکریپت
set_sysctl() {   # $1=کلید  $2=مقدار
    local key_esc=${1//./\\.}
    if sudo grep -qE "^[[:space:]]*${key_esc}[[:space:]]*=" "$SYSCTL_CONF" 2>/dev/null; then
        sudo sed -i "s|^[[:space:]]*${key_esc}[[:space:]]*=.*|$1 = $2|" "$SYSCTL_CONF"
    else
        echo "$1 = $2" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    fi
}

apply_sysctl() {
    sudo sysctl --system > /dev/null 2>&1
}

# نام اتصال فعال NetworkManager (حلقه lo نادیده گرفته می‌شود)
# $1 اختیاری: فیلتر نوع اتصال (مثلاً wireless)
get_active_connection() {
    local name dev type
    while IFS=: read -r name dev type; do
        [ "$dev" = "lo" ] && continue
        if [ -n "$1" ] && [ "$type" != "$1" ]; then continue; fi
        echo "$name"
        return 0
    done < <(nmcli -t -f NAME,DEVICE,TYPE con show --active 2>/dev/null)
    return 1
}

# ---------- کمکی‌های نام/نسخه ----------

# نرمال‌سازی نام برای مقایسه (حذف فاصله/خط تیره/حروف بزرگ)
normalize_name() {
    printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

# حدس نسخه از نام فایل (مثل 1.10.4)
guess_version() {
    local base
    base=$(basename "$1")
    base=${base%.tar.gz}; base=${base%.tgz}
    if [[ "$base" =~ ([0-9]+(\.[0-9]+)+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# استخراج نام برنامه از نام فایل آرشیو (حذف نسخه/پلتفرم)
name_from_archive() {
    local base
    base=$(basename "$1")
    base=${base%.tar.gz}; base=${base%.tgz}
    base=$(printf '%s' "$base" | sed -E 's/[0-9]+(\.[0-9]+)+//g')
    base=$(printf '%s' "$base" | sed -E 's/(linux|amd64|arm64|aarch64|x86[_-]64|x64|i[0-9]86|riscv64|portable|appimage|stable|release|final|gnu)//gi')
    printf '%s' "$base" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]'
}

# ریشه نصب از مسیر فایل اجرایی (مثل /opt/app/bin/x → /opt/app)
derive_install_root() {
    local root
    root=$(dirname "$1")
    if [ "$(basename "$root")" = "bin" ]; then
        root=$(dirname "$root")
    fi
    printf '%s' "$root"
}

# ---------- رجیستری برنامه‌های tar.gz ----------
# فرمت هر خط: name|version|install_dir|exec_path|desktop_file|source_archive

registry_add() {   # $1=name $2=version $3=dir $4=exec $5=desktop $6=source
    mkdir -p "$REGISTRY_DIR"
    touch "$REGISTRY_DB"
    local tmp="$REGISTRY_DB.tmp"
    awk -F'|' -v n="$1" '$1 != n' "$REGISTRY_DB" > "$tmp" 2>/dev/null
    echo "$1|$2|$3|$4|$5|$6" >> "$tmp"
    mv "$tmp" "$REGISTRY_DB"
}

registry_remove() {   # $1=name
    [ -f "$REGISTRY_DB" ] || return 0
    local tmp="$REGISTRY_DB.tmp"
    awk -F'|' -v n="$1" '$1 != n' "$REGISTRY_DB" > "$tmp" 2>/dev/null
    mv "$tmp" "$REGISTRY_DB"
}