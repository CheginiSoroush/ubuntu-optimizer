#!/bin/bash

# ============================================================
#   install.sh — نصب و مدیریت خودِ Ubuntu Optimizer & Fixer
#
#   اجرا:
#     ./install.sh               → نصب کامل (سلامت + میان‌بر uo + alias + PATH)
#     ./install.sh --check       → بررسی سلامت فایل‌ها و وضعیت نصب
#     ./install.sh --update      → به‌روزرسانی از git (اگر مخزن git باشد)
#     ./install.sh --uninstall   → حذف میان‌بر و alias (خود پروژه دست‌نخورده)
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()  { echo -e "${GREEN}   ✓ $1${NC}"; }
bad() { echo -e "${RED}   ✗ $1${NC}"; }
inf() { echo -e "${YELLOW}   ℹ $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/ubuntu-optimizer.sh"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/uo"

REQUIRED_MODULES=(common network system fixnet packages targz appmgmt snapflatpak recovery report menus)

version() { grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' "$MAIN_SCRIPT" 2>/dev/null; }

# ---------- بررسی سلامت همه فایل‌های پروژه ----------
check_health() {
    echo -e "${BOLD}── بررسی سلامت فایل‌ها ──${NC}"
    if [ ! -f "$MAIN_SCRIPT" ]; then
        bad "ubuntu-optimizer.sh در این پوشه پیدا نشد!"
        return 1
    fi
    if ! bash -n "$MAIN_SCRIPT" 2>/dev/null; then
        bad "خطای syntax در ubuntu-optimizer.sh"
        return 1
    fi
    ok "ubuntu-optimizer.sh ($(version))"

    local m f broken=0
    for m in "${REQUIRED_MODULES[@]}"; do
        f="$SCRIPT_DIR/lib/$m.sh"
        if [ ! -f "$f" ]; then
            bad "ماژول غایب: lib/$m.sh"
            broken=1
        elif ! bash -n "$f" 2>/dev/null; then
            bad "خطای syntax در: lib/$m.sh"
            broken=1
        else
            ok "lib/$m.sh"
        fi
    done
    [ "$broken" = "0" ] || return 1

    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        bad "نسخه bash سیستم قدیمی است (نیاز: 4+) — فعلی: $BASH_VERSION"
        return 1
    fi
    return 0
}

# ---------- وضعیت نصب فعلی ----------
check_install_status() {
    echo -e "${BOLD}── وضعیت نصب ──${NC}"
    if [ -L "$BIN_LINK" ]; then
        ok "میان‌بر فعال: $BIN_LINK → $(readlink "$BIN_LINK")"
    else
        inf "میان‌بر «uo» نصب نشده است."
    fi
    if grep -q "alias uo=" "$HOME/.bashrc" 2>/dev/null; then
        ok "alias «uo» در ~/.bashrc موجود است."
    else
        inf "alias «uo» در ~/.bashrc نیست."
    fi
    if grep -q "ubuntu-optimizer path" "$HOME/.bashrc" 2>/dev/null; then
        ok "بلوک PATH در ~/.bashrc موجود است."
    else
        inf "بلوک PATH در ~/.bashrc نیست."
    fi
    if [ -f "$HOME/.zshrc" ]; then
        if grep -q "alias uo=" "$HOME/.zshrc" 2>/dev/null; then
            ok "alias «uo» در ~/.zshrc موجود است."
        else
            inf "alias «uo» در ~/.zshrc نیست."
        fi
    fi
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        inf "پوشه $BIN_DIR در PATH شل فعلی نیست (در شل‌های جدید فعال می‌شود)."
    fi
}

# افزودن بلوک PATH به فایل شل (با گارد ضد تکرار)
_add_path_block() {   # $1 = مسیر فایل rc
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    grep -q "ubuntu-optimizer path" "$rcfile" 2>/dev/null && return 0
    {
        echo ""
        echo "# >>> ubuntu-optimizer path >>>"
        echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
        echo "# <<< ubuntu-optimizer path <<<"
    } >> "$rcfile"
    return 0
}

# حذف بلوک PATH از فایل شل
_remove_path_block() {   # $1 = مسیر فایل rc
    local rcfile="$1"
    [ -f "$rcfile" ] || return 0
    sed -i '/^# >>> ubuntu-optimizer path >>>$/,/^# <<< ubuntu-optimizer path <<</d' "$rcfile" 2>/dev/null
    return 0
}

# ---------- نصب ----------
do_install() {
    echo -e "${BOLD}${CYAN}نصب Ubuntu Optimizer & Fixer $(version)${NC}"
    echo ""
    if ! check_health; then
        echo ""
        bad "نصب لغو شد — ابتدا خطاهای بالا را رفع کنید."
        exit 1
    fi
    echo ""

    mkdir -p "$BIN_DIR"
    ln -sf "$MAIN_SCRIPT" "$BIN_LINK"
    chmod +x "$MAIN_SCRIPT"
    ok "میان‌بر ساخته شد: $BIN_LINK"

    local rc_alias="alias uo=\"$MAIN_SCRIPT\""
    if ! grep -q "alias uo=" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# Ubuntu Optimizer & Fixer"
            echo "$rc_alias"
        } >> "$HOME/.bashrc"
        ok "alias «uo» به ~/.bashrc اضافه شد."
    fi
    if [ -f "$HOME/.zshrc" ] && ! grep -q "alias uo=" "$HOME/.zshrc" 2>/dev/null; then
        {
            echo ""
            echo "# Ubuntu Optimizer & Fixer"
            echo "$rc_alias"
        } >> "$HOME/.zshrc"
        ok "alias «uo» به ~/.zshrc اضافه شد."
    fi

    # مسیر ~/.local/bin در فایل‌های شل — برای اینکه «uo» حتی بدون
    # alias هم کار کند (مثلاً داخل اسکریپت‌ها یا شل‌های دیگر)
    _add_path_block "$HOME/.bashrc"
    _add_path_block "$HOME/.zshrc"
    ok "مسیر $BIN_DIR در فایل‌های شل تنظیم شد."

    echo ""
    inf "برای فعال‌شدن در همین ترمینال:  source ~/.bashrc"
    inf "در ترمینال‌های جدید، «uo» به‌صورت خودکار فعال است."
    inf "استفاده:  uo   |   uo --report   |   uo --help"
}

# ---------- به‌روزرسانی ----------
do_update() {
    echo -e "${BOLD}${CYAN}به‌روزرسانی Ubuntu Optimizer & Fixer${NC}"
    echo ""
    if [ -d "$SCRIPT_DIR/.git" ]; then
        inf "دریافت به‌روزرسانی‌ها از git..."
        if git -C "$SCRIPT_DIR" pull; then
            echo ""
            if ! check_health; then
                bad "پس از به‌روزرسانی، برخی فایل‌ها مشکل دارند!"
                exit 1
            fi
            echo ""
            ok "به‌روزرسانی کامل شد. نسخه فعلی: $(version)"
        else
            bad "خطا در git pull — اینترنت یا دسترسی مخزن را بررسی کنید."
            exit 1
        fi
    else
        inf "این پوشه یک مخزن git نیست؛ به‌روزرسانی خودکار ممکن نیست."
        inf "روش دستی: فایل‌های جدید را در همین پوشه جایگزین کنید، سپس:"
        inf "  $0 --check"
        exit 0
    fi
}

# ---------- حذف نصب ----------
do_uninstall() {
    echo -e "${BOLD}${CYAN}حذف نصب Ubuntu Optimizer & Fixer${NC}"
    echo ""
    rm -f "$BIN_LINK"
    ok "میان‌بر «uo» حذف شد."
    sed -i '/alias uo=/d; /^# Ubuntu Optimizer & Fixer$/d' "$HOME/.bashrc" 2>/dev/null
    _remove_path_block "$HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ]; then
        sed -i '/alias uo=/d; /^# Ubuntu Optimizer & Fixer$/d' "$HOME/.zshrc" 2>/dev/null
        _remove_path_block "$HOME/.zshrc"
    fi
    ok "alias و بلوک PATH از فایل‌های شل حذف شدند."
    inf "خود پروژه در $SCRIPT_DIR دست‌نخورده مانده است."
    inf "برای حذف کامل پروژه: rm -rf \"$SCRIPT_DIR\""
}

usage() {
    cat << 'EOF'
install.sh — مدیریت نصب Ubuntu Optimizer & Fixer

  ./install.sh              نصب: بررسی سلامت + میان‌بر uo + alias + PATH
  ./install.sh --check      فقط بررسی سلامت فایل‌ها و وضعیت نصب
  ./install.sh --update     به‌روزرسانی از git (اگر مخزن git باشد)
  ./install.sh --uninstall  حذف میان‌بر و alias (بدون حذف خود پروژه)
  ./install.sh --help       همین راهنما
EOF
}

case "${1:-}" in
    --check)     check_health; echo ""; check_install_status ;;
    --update)    do_update ;;
    --uninstall) do_uninstall ;;
    -h|--help)   usage ;;
    "")          do_install ;;
    *)           echo "گزینه نامعتبر: $1"; usage; exit 1 ;;
esac