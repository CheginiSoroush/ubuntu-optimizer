# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/i18n.sh
# ───────────────────────────────────────────────────────────────────────────────
#  The fa/en translation framework for the CLI. English is the source of truth:
#  every EN_* catalog entry is the exact string the interface printed before
#  i18n existed, so with the language unresolved to fa the output is
#  byte-identical to the pre-i18n toolkit. Persian (fa) translations live in
#  the parallel FA_* catalogs; a key that is missing there (or everywhere)
#  falls back by design — nothing ever fails or prints a warning.
#
#  Language resolution (i18n_init), first match wins:
#      1. UO_LANG environment variable  (fa | en, case-insensitive;
#         any invalid value resolves to en silently)
#      2. config file key `language`    (applied by lib/config.sh — the same
#         paranoid validate/apply pipeline as every other key)
#      3. locale auto-detect            (fa* / pe* in $LC_ALL, $LC_MESSAGES,
#         $LANG — first Persian-looking locale wins)
#      4. default                       (en)
#
#  This file is pure at source time (data + functions only, no side effects);
#  i18n_init() runs once from ubuntu-optimizer.sh after the config load and
#  before any banner/menu output. Modules that are also sourced standalone by
#  the test suite (common.sh, menus.sh, fzf.sh) pull this file in with a
#  `declare -F t` guard when it is not already loaded.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# Load-once guard: the entry script lists i18n.sh in its module list AND the
# standalone-sourcing modules (common.sh/menus.sh/fzf.sh) pull it in — both
# paths must end with exactly one copy of the catalogs in memory.
if [ -n "${_UO_I18N_LOADED:-}" ]; then
    return 0
fi
_UO_I18N_LOADED=1

# ── Effective language state (written by i18n_init) ───────────────────────────
UO_LANG_ACTIVE=""    # resolved UI language: "fa" | "en" ("" = not yet resolved)
UO_LANG_SOURCE=""    # where it came from: "env" | "config" | "detected" | "default"

# ── Catalogs ──────────────────────────────────────────────────────────────────
# Three groups per language, named EN_<GROUP> / FA_<GROUP>; the group is the
# prefix of every key (banner.* / menu.* / msg.*). EN_* values are the exact
# pre-i18n strings — byte-identical en output is a hard requirement.

declare -gA EN_BANNER=()
declare -gA FA_BANNER=()
declare -gA EN_MENU=()
declare -gA FA_MENU=()
declare -gA EN_MSG=()
declare -gA FA_MSG=()

# ── Banner / title (main_menu box in lib/menus.sh) ────────────────────────────
# The 7-space indent is part of the boxed layout, not of the translation.
EN_BANNER[banner.title]='       Ubuntu Optimizer & Fixer - v%s'
FA_BANNER[banner.title]='       بهینه‌ساز و تعمیرکار اوبونتو - نسخه %s'
EN_BANNER[banner.tagline]='       All-in-one Ubuntu optimization & repair toolkit'
FA_BANNER[banner.tagline]='       مجموعهٔ همه‌کارهٔ بهینه‌سازی و تعمیر اوبونتو'

# ── Main menu (lib/menus.sh main_menu — mirrored exactly) ─────────────────────
# Section headers
EN_MENU[menu.sec_optimization]='── Optimization & Health ──'
FA_MENU[menu.sec_optimization]='── بهینه‌سازی و سلامت ──'
EN_MENU[menu.sec_emergency]='── Emergency & Diagnostics ──'
FA_MENU[menu.sec_emergency]='── اضطراری و عیب‌یابی ──'
EN_MENU[menu.sec_apps]='── Applications ──'
FA_MENU[menu.sec_apps]='── برنامه‌ها ──'
EN_MENU[menu.sec_system]='── System & Info ──'
FA_MENU[menu.sec_system]='── سیستم و اطلاعات ──'
# The 22 numbered entries (labels only — the "N) " prefix stays in the render)
EN_MENU[menu.01]='🌐 Network optimization'
FA_MENU[menu.01]='🌐 بهینه‌سازی شبکه'
EN_MENU[menu.02]='💾 System & memory optimization'
FA_MENU[menu.02]='💾 بهینه‌سازی سیستم و حافظه'
EN_MENU[menu.03]='🔐 Security & passwords'
FA_MENU[menu.03]='🔐 امنیت و گذرواژه‌ها'
EN_MENU[menu.04]='🕐 Time & NTP'
FA_MENU[menu.04]='🕐 زمان و NTP'
EN_MENU[menu.05]='⚡ Optimization profiles (laptop/server/gaming/minimal)'
FA_MENU[menu.05]='⚡ پروفایل‌های بهینه‌سازی (لپ‌تاپ/سرور/گیمینگ/حداقلی)'
EN_MENU[menu.06]='🛠 Create & run fixnet'
FA_MENU[menu.06]='🛠 ساخت و اجرای fixnet'
EN_MENU[menu.07]='📊 Network & speed tests'
FA_MENU[menu.07]='📊 تست‌های شبکه و سرعت'
EN_MENU[menu.08]='📦 Install packages & apps'
FA_MENU[menu.08]='📦 نصب بسته‌ها و برنامه‌ها'
EN_MENU[menu.09]='🧹 Manage & fully remove apps'
FA_MENU[menu.09]='🧹 مدیریت و حذف کامل برنامه‌ها'
EN_MENU[menu.10]='🔄 Update apps'
FA_MENU[menu.10]='🔄 به‌روزرسانی برنامه‌ها'
EN_MENU[menu.11]='🧩 snap & flatpak management'
FA_MENU[menu.11]='🧩 مدیریت snap و flatpak'
EN_MENU[menu.12]='🚑 System recovery & rescue'
FA_MENU[menu.12]='🚑 بازیابی و نجات سیستم'
EN_MENU[menu.13]='☠ Advanced tools (dangerous)'
FA_MENU[menu.13]='☠ ابزارهای پیشرفته (خطرناک)'
EN_MENU[menu.14]='📜 Activity log'
FA_MENU[menu.14]='📜 گزارش فعالیت (لاگ)'
EN_MENU[menu.15]='📊 System status report'
FA_MENU[menu.15]='📊 گزارش وضعیت سیستم'
EN_MENU[menu.16]='📊 Disk space analysis'
FA_MENU[menu.16]='📊 تحلیل فضای دیسک'
EN_MENU[menu.17]='🧹 Disk cleanup'
FA_MENU[menu.17]='🧹 پاکسازی دیسک'
EN_MENU[menu.18]='⏰ Scheduled updates (systemd timer)'
FA_MENU[menu.18]='⏰ به‌روزرسانی زمان‌بندی‌شده (تایمر systemd)'
EN_MENU[menu.19]='🖥 Disk report (HTML, shareable)'
FA_MENU[menu.19]='🖥 گزارش دیسک (HTML، قابل اشتراک)'
EN_MENU[menu.20]='🥾 Boot & startup'
FA_MENU[menu.20]='🥾 بوت و راه‌اندازی'
EN_MENU[menu.21]='🔍 Monitor & inspect'
FA_MENU[menu.21]='🔍 پایش و بازرسی'
EN_MENU[menu.22]='🧰 Maintenance & hardware (DNS · kernels · swap)'
FA_MENU[menu.22]='🧰 نگهداری و سخت‌افزار (DNS · هسته‌ها · سواپ)'
EN_MENU[menu.23]='🚀 Interactive fzf menu (if installed)'
FA_MENU[menu.23]='🚀 منوی تعاملی fzf (در صورت نصب)'
EN_MENU[menu.exit]='Exit'
FA_MENU[menu.exit]='خروج'
EN_MENU[menu.select]='   Select: '
FA_MENU[menu.select]='   انتخاب: '

# ── Common feedback strings ───────────────────────────────────────────────────
EN_MSG[msg.finished_ok]='Finished — all requested tasks completed.'
FA_MSG[msg.finished_ok]='تمام شد — همهٔ کارهای درخواستی انجام شد.'
EN_MSG[msg.finished_errors]='Finished — some steps had errors; see the log for details.'
FA_MSG[msg.finished_errors]='تمام شد — برخی مراحل خطا داشتند؛ جزئیات در لاگ.'
EN_MSG[msg.dry_run_notice]='── DRY RUN: commands are printed, nothing is executed ──'
FA_MSG[msg.dry_run_notice]='── DRY RUN: دستورها فقط نمایش داده می‌شوند، هیچ چیزی اجرا نمی‌شود ──'
EN_MSG[msg.invalid_choice]='Invalid choice'
FA_MSG[msg.invalid_choice]='انتخاب نامعتبر'
EN_MSG[msg.goodbye]='Goodbye! 👋'
FA_MSG[msg.goodbye]='خداحافظ! 👋'
EN_MSG[msg.press_enter]='   Press Enter to continue...'
FA_MSG[msg.press_enter]='   برای ادامه Enter را فشار دهید...'
EN_MSG[msg.report_saved]='Report saved to: %s'
FA_MSG[msg.report_saved]='گزارش ذخیره شد در: %s'
EN_MSG[msg.exiting]='Exiting...'
FA_MSG[msg.exiting]='در حال خروج...'
EN_MSG[msg.no_log_yet]='No log file exists yet.'
FA_MSG[msg.no_log_yet]='هنوز فایل لاگی وجود ندارد.'
EN_MSG[msg.no_log_to_delete]='No log file to delete.'
FA_MSG[msg.no_log_to_delete]='فایل لاگی برای حذف وجود ندارد.'
EN_MSG[msg.log_deleted]='Log deleted.'
FA_MSG[msg.log_deleted]='لاگ حذف شد.'
# Reserved: the self-update opt-outs (—no-update / UO_AUTO_UPDATE=0) skip the
# startup check SILENTLY by design — translating that silence would change the
# documented output. The key exists so the day that changes, the string is ready.
EN_MSG[msg.update_check_skipped]='Update check skipped.'
FA_MSG[msg.update_check_skipped]='بررسی به‌روزرسانی رد شد.'
# Reserved: a generic cancellation line for future flows.
EN_MSG[msg.cancelled]='Cancelled.'
FA_MSG[msg.cancelled]='لغو شد.'
EN_MSG[msg.fzf_missing]='fzf is not installed — install it with: sudo apt install fzf'
FA_MSG[msg.fzf_missing]='fzf نصب نیست — برای نصب از این دستور استفاده کنید: sudo apt install fzf'
EN_MSG[msg.lang_saved]='Language set to %s — saved in %s'
FA_MSG[msg.lang_saved]='زبان روی %s تنظیم شد — ذخیره شد در %s'
EN_MSG[msg.lang_show]='Language: %s (source: %s)'
FA_MSG[msg.lang_show]='زبان: %s (منبع: %s)'

# ───────────────────────────────────────────────────────────────────────────────
# _i18n_detect() — map one locale string to a UI language
#
# Pure helper (no environment reads): "fa*"/"pe*" (the legacy ISO code for
# Persian) → fa, everything else → en. Case-insensitive on the language tag,
# so fa_IR.UTF-8, FA-ir and pe_IR all detect as fa.
#
# Arguments: $1 — a locale string (e.g. fa_IR.UTF-8, en_US.UTF-8)
# Returns:   0 — always; prints "fa" or "en"
# ───────────────────────────────────────────────────────────────────────────────
_i18n_detect() {
    local locale="${1:-}"
    case "$locale" in
        [Ff][Aa]*|[Pp][Ee]*) printf 'fa\n' ;;
        *)                   printf 'en\n' ;;
    esac
}

# ───────────────────────────────────────────────────────────────────────────────
# i18n_init() — resolve the effective UI language (see the resolution order
# in the file header). Idempotent, silent, side-effect-free and cheap: no
# forks except one optional _i18n_detect call when a locale var is present.
#
# Globals:   UO_LANG, UO_LANGUAGE, LC_ALL, LC_MESSAGES, LANG (read);
#            UO_LANG_ACTIVE, UO_LANG_SOURCE (written)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
i18n_init() {
    # Already resolved — never re-run (cheap + predictable)
    [ -n "$UO_LANG_ACTIVE" ] && return 0
    UO_LANG_ACTIVE="en"
    UO_LANG_SOURCE="default"

    # 1) explicit environment override (fa/en, case-insensitive).
    #    An invalid value is terminal: it resolves to en silently and does
    #    NOT fall through to the config file — an explicit override that is
    #    garbage must never be second-guessed by a stored preference.
    if [ -n "${UO_LANG:-}" ]; then
        case "${UO_LANG,,}" in
            fa) UO_LANG_ACTIVE="fa"; UO_LANG_SOURCE="env" ;;
            en) UO_LANG_ACTIVE="en"; UO_LANG_SOURCE="env" ;;
        esac
        return 0
    fi

    # 2) config file key `language` — applied by lib/config.sh's standard
    #    validate/apply pipeline, so invalid values never reach this point.
    if [ -n "${UO_LANGUAGE:-}" ]; then
        case "$UO_LANGUAGE" in
            fa) UO_LANG_ACTIVE="fa"; UO_LANG_SOURCE="config" ;;
            en) UO_LANG_ACTIVE="en"; UO_LANG_SOURCE="config" ;;
        esac
        return 0
    fi

    # 3) locale auto-detect: the first Persian-looking locale among
    #    LC_ALL → LC_MESSAGES → LANG wins
    local var locale_value
    for var in LC_ALL LC_MESSAGES LANG; do
        locale_value="${!var:-}"
        [ -n "$locale_value" ] || continue
        if [ "$(_i18n_detect "$locale_value")" = "fa" ]; then
            UO_LANG_ACTIVE="fa"
            UO_LANG_SOURCE="detected"
            return 0
        fi
    done

    # 4) default en already set
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# t() — translate a catalog key in the active language
#
# Resolution: FA_<group>[key] when active and present → EN_<group>[key] (the
# English default) → the key itself. With arguments the value is treated as a
# printf format string; without arguments it is printed literally (so stray %
# in translations can never misfire). Missing keys are a silent fallback, by
# design — untranslated future keys simply show English.
#
# Arguments: $1 — key ("<group>.<name>", group ∈ banner|menu|msg)
#            $2.. — optional printf arguments
# Returns:   0 — always; the string (+ newline) goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
t() {
    local key="$1"
    shift
    local group="${key%%.*}"
    local fmt=""

    # Unknown group (or dot-less key) → the key itself, silently
    case "$group" in
        banner|menu|msg) ;;
        *) printf '%s\n' "$key"; return 0 ;;
    esac

    if [ "${UO_LANG_ACTIVE:-en}" = "fa" ]; then
        case "$group" in
            banner) [ -n "${FA_BANNER[$key]+x}" ] && fmt="${FA_BANNER[$key]}" ;;
            menu)   [ -n "${FA_MENU[$key]+x}" ]   && fmt="${FA_MENU[$key]}" ;;
            msg)    [ -n "${FA_MSG[$key]+x}" ]    && fmt="${FA_MSG[$key]}" ;;
        esac
    fi
    if [ -z "$fmt" ]; then
        case "$group" in
            banner) [ -n "${EN_BANNER[$key]+x}" ] && fmt="${EN_BANNER[$key]}" ;;
            menu)   [ -n "${EN_MENU[$key]+x}" ]   && fmt="${EN_MENU[$key]}" ;;
            msg)    [ -n "${EN_MSG[$key]+x}" ]    && fmt="${EN_MSG[$key]}" ;;
        esac
    fi

    if [ -z "$fmt" ]; then
        # Missing from both catalogs → the key itself (never an error)
        printf '%s\n' "$key"
        return 0
    fi
    if [ "$#" -gt 0 ]; then
        # printf-style substitution is the documented t() contract;
        # the format string comes exclusively from our own catalogs
        # shellcheck disable=SC2059
        printf -- "$fmt\n" "$@"
    else
        printf '%s\n' "$fmt"
    fi
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# i18n_show() — implement `uo --lang-show`
#
# Prints the effective language and where it was resolved from
# (env / config / detected / default).
#
# Globals:   UO_LANG_ACTIVE, UO_LANG_SOURCE (read; resolved via i18n_init)
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
i18n_show() {
    i18n_init
    printf '%s\n' "$(t msg.lang_show "$UO_LANG_ACTIVE" "$UO_LANG_SOURCE")"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# i18n_set_language() — implement `uo --lang fa|en` (persist the choice)
#
# Writes `language=<fa|en>` into the user's config file — the same file the
# standard config system reads (the --config override path when one was given,
# else ~/.config/uo/config.conf). An existing (uncommented) language line is
# replaced in place, a missing key is appended, a missing file is created with
# a two-line header. Never touches anything else in the file. The in-process
# state is updated afterwards so a confirmation prints in the NEW language.
#
# Globals:   CONFIG_PATH_OVERRIDE, CONFIG_FILE (read — set by lib/config.sh);
#            UO_LANGUAGE, UO_LANG_ACTIVE, UO_LANG_SOURCE (written)
# Arguments: $1 — validated language ("fa" or "en", already normalized)
# Returns:   0 — persisted; 1 — the config directory could not be created
# ───────────────────────────────────────────────────────────────────────────────
i18n_set_language() {
    local lang="$1"
    local target="${CONFIG_PATH_OVERRIDE:-${CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/uo/config.conf}}"
    local target_dir
    target_dir="$(dirname -- "$target")"
    if ! mkdir -p -- "$target_dir"; then
        printf 'Cannot create config directory: %s\n' "$target_dir" >&2
        return 1
    fi

    if [ -f "$target" ] && grep -qE '^[[:space:]]*language=' "$target"; then
        # Replace the existing line in place — everything else stays byte-for-byte
        sed -i --follow-symlinks "s|^[[:space:]]*language=.*|language=$lang|" -- "$target"
    elif [ -f "$target" ]; then
        printf '\nlanguage=%s\n' "$lang" >> "$target"
    else
        {
            echo "# Ubuntu Optimizer & Fixer — user configuration"
            echo "# Format: KEY=VALUE (annotated template: uo --config-example)"
            echo "language=$lang"
        } > "$target"
    fi

    # Keep the in-process state consistent (i18n_show after a --lang run)
    UO_LANGUAGE="$lang"
    CONFIG_SOURCES["language"]="config"
    UO_LANG_ACTIVE="$lang"
    UO_LANG_SOURCE="config"
    printf '%s\n' "   ✓ $(t msg.lang_saved "$lang" "$target")"
    return 0
}
