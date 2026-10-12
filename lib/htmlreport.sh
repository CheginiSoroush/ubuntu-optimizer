# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Ubuntu Optimizer & Fixer — lib/htmlreport.sh
# ───────────────────────────────────────────────────────────────────────────────
#  Self-contained HTML disk report: `uo --disk-report [FILE]` re-runs the same
#  read-only analysis as the terminal's disk_analyze (root usage, category
#  breakdown, largest /opt apps, largest deb packages) and renders it into one
#  standalone .html file — charts and sortable tables included, no CDN, no
#  internet, no JavaScript framework. Far more readable than the terminal for
#  heavy folders, and easy to share or archive.
#
#  Design rules:
#    • The document is 100 % self-contained: inline CSS + ~30 lines of vanilla
#      JS for the sortable tables. Everything else is static markup.
#    • RTL Persian layout with English technical terms — the file opens
#      correctly in any browser regardless of locale.
#    • EVERY value that came from the system (paths, sizes, names) is
#      HTML-escaped before it enters the document; a folder called
#      <script> can never inject markup.
#    • Atomic write: the report is rendered into a tmp file in the target
#      directory and moved into place with a single mv — a half-written
#      report can never exist.
#    • Missing data (a directory that does not exist, sudo without a tty)
#      simply omits that section — never a broken or empty page.
#
#  Project : ubuntu-optimizer — github.com/CheginiSoroush/ubuntu-optimizer
#  Author  : Soroush Chegini (CheginiSoroush)
#  License : MIT
# ═══════════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────────
# _html_escape() — escape a string for safe inclusion in HTML
#
# Handles the five XML/HTML-critical characters (& < > " '). Applied to every
# system-derived value before it is placed into the document, in both text
# nodes and attribute values.
#
# Bash 5.2 note: with the default patsub_replacement shopt, an '&' inside a
# ${var//pat/rep} replacement expands to the matched text — which would turn
# '&lt;' into '<lt;'. The shopt is switched off for the duration of the
# function and restored to the caller's state afterwards; on older bash the
# unknown-option errors are silenced and the state was already 'off'.
#
# Arguments: $1 — raw text
# Returns:   0 — always; the escaped text goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_html_escape() {
    local s="$1"
    local hr_pr=off
    if shopt -q patsub_replacement 2>/dev/null; then
        hr_pr=on
        shopt -u patsub_replacement 2>/dev/null
    fi
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    s=${s//\'/&#39;}
    [ "$hr_pr" = "on" ] && shopt -s patsub_replacement 2>/dev/null
    printf '%s' "$s"
}

# ───────────────────────────────────────────────────────────────────────────────
# _hr_fmt_kb() — humanize a size given in KiB
#
# Pure arithmetic formatter: >= 1 GiB → "x.x GB", >= 1 MiB → "x.x MB",
# otherwise "N KB". Non-numeric or empty input becomes "—".
#
# Arguments: $1 — size in KiB
# Returns:   0 — always; the formatted size goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_hr_fmt_kb() {
    local kb="$1"
    [[ "$kb" =~ ^[0-9]+$ ]] || { printf '—'; return 0; }
    if [ "$kb" -ge 1048576 ]; then
        printf '%s.%s GB' "$((kb / 1048576))" "$(( (kb % 1048576) * 10 / 1048576 ))"
    elif [ "$kb" -ge 1024 ]; then
        printf '%s.%s MB' "$((kb / 1024))" "$(( (kb % 1024) * 10 / 1024 ))"
    else
        printf '%s KB' "$kb"
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _hr_severity() — map a usage percentage to a severity class
#
# ok (< 60 %) · warn (< 85 %) · crit (>= 85 %) — the same thresholds drive the
# bar color, the big usage bar and the warning banner, so the page stays
# visually consistent.
#
# Arguments: $1 — percentage (0-100 integer)
# Returns:   0 — always; the class word goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_hr_severity() {
    local pct="$1"
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    if [ "$pct" -ge 85 ]; then printf 'crit'
    elif [ "$pct" -ge 60 ]; then printf 'warn'
    else printf 'ok'
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# _hr_add_cat() — append one category row to the collected data
#
# Skips silently when the size is missing/non-numeric/zero, so unavailable
# directories (and sudo-less environments) never produce empty rows.
#
# Arguments: $1 — display label (Persian), $2 — size in KiB
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
_hr_add_cat() {
    local label="$1" kb="$2"
    [[ "$kb" =~ ^[0-9]+$ ]] || return 0
    [ "$kb" -gt 0 ] || return 0
    HR_CATS_NAME+=("$label")
    HR_CATS_KB+=("$kb")
}

# ───────────────────────────────────────────────────────────────────────────────
# _disk_report_collect() — gather the disk data for the report
#
# Fills the HR_* globals with the same data the terminal analysis shows:
# root filesystem usage, category sizes (apt cache, snap, /opt, ~/.local,
# logs, crash dumps, Timeshift), the removable old-kernel count, the ten
# largest /opt entries and the ten largest deb packages. sudo-protected
# paths degrade gracefully when sudo is unavailable.
#
# Globals:   HR_* (written); _old_kernel_pkgs, _disk_avail_mb (called,
#            must be loaded); SCRIPT_VERSION (read)
# Arguments: none
# Returns:   0 — always (missing probes simply leave sections empty)
# ───────────────────────────────────────────────────────────────────────────────
_disk_report_collect() {
    HR_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -n "$HR_TIMESTAMP" ] || HR_TIMESTAMP="—"

    # root filesystem usage (human strings + numeric percent for the bar)
    read -r HR_TOTAL HR_USED HR_AVAIL HR_PCT <<< \
        "$(df -h / 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}')"
    HR_PCT_NUM="${HR_PCT//%/}"
    [[ "$HR_PCT_NUM" =~ ^[0-9]+$ ]] || HR_PCT_NUM=0
    HR_AVAIL_MB=$(_disk_avail_mb /)

    # category breakdown
    HR_CATS_NAME=()
    HR_CATS_KB=()
    _hr_add_cat "کش apt — /var/cache/apt/archives" \
        "$(du -sk /var/cache/apt/archives 2>/dev/null | cut -f1)"
    _hr_add_cat "اسنپ — /var/lib/snapd" \
        "$(sudo du -sk /var/lib/snapd 2>/dev/null | cut -f1)"
    _hr_add_cat "برنامه‌های /opt" \
        "$(du -sk /opt 2>/dev/null | cut -f1)"
    _hr_add_cat "داده‌های کاربر — ~/.local" \
        "$(du -sk "$HOME/.local" 2>/dev/null | cut -f1)"
    _hr_add_cat "لاگ‌ها — /var/log" \
        "$(sudo du -sk /var/log 2>/dev/null | cut -f1)"
    _hr_add_cat "گزارش‌های کرش — /var/crash" \
        "$(sudo du -sk /var/crash 2>/dev/null | cut -f1)"
    if [ -d /timeshift ]; then
        _hr_add_cat "اسنپ‌شات‌های تایم‌شیفت — /timeshift" \
            "$(sudo du -sk /timeshift 2>/dev/null | cut -f1)"
        HR_TS_COUNT=$(sudo find /timeshift/snapshots -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        [[ "$HR_TS_COUNT" =~ ^[0-9]+$ ]] || HR_TS_COUNT=""
    else
        HR_TS_COUNT=""
    fi

    # removable old kernels (running + newest are always kept)
    local -a hr_kernels=()
    mapfile -t hr_kernels < <(_old_kernel_pkgs 2>/dev/null)
    HR_OLD_KERNELS=${#hr_kernels[@]}

    # ten largest /opt entries
    HR_OPT_NAME=()
    HR_OPT_KB=()
    local hr_line hr_size hr_name
    while IFS= read -r hr_line; do
        [ -n "$hr_line" ] || continue
        hr_size="${hr_line%%$'\t'*}"
        hr_name="${hr_line#*$'\t'}"
        [[ "$hr_size" =~ ^[0-9]+$ ]] || continue
        [ ${#HR_OPT_NAME[@]} -lt 10 ] || continue
        HR_OPT_NAME+=("$(basename "$hr_name")")
        HR_OPT_KB+=("$hr_size")
    done < <(sudo du -sk /opt/*/ 2>/dev/null | sort -rn)

    # ten largest deb packages (Installed-Size is KiB)
    HR_DEB_NAME=()
    HR_DEB_KB=()
    while IFS= read -r hr_line; do
        [ -n "$hr_line" ] || continue
        hr_size="${hr_line%%$'\t'*}"
        hr_name="${hr_line#*$'\t'}"
        [[ "$hr_size" =~ ^[0-9]+$ ]] || continue
        [ ${#HR_DEB_NAME[@]} -lt 10 ] || continue
        HR_DEB_NAME+=("$hr_name")
        HR_DEB_KB+=("$hr_size")
    done < <(dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' 2>/dev/null | sort -rn)

    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# _disk_report_render() — emit the HTML document from the HR_* globals
#
# Pure renderer: it reads only the collected globals and writes the complete
# document to stdout — no system probing of its own. Tests seed the globals
# and diff/inspect the output. Sections with no data are omitted; the escape
# helper guards every system-derived value.
#
# Globals:   HR_* (read); SCRIPT_VERSION (read)
# Arguments: none
# Returns:   0 — always; the HTML document goes to stdout
# ───────────────────────────────────────────────────────────────────────────────
_disk_report_render() {
    local out=""
    local sev
    sev=$(_hr_severity "$HR_PCT_NUM")

    # ---- head + styles ----
    out+='<!DOCTYPE html>
<html dir="rtl" lang="fa">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>گزارش تحلیل دیسک — Ubuntu Optimizer</title>
<style>
:root{--bg:#0c0a09;--card:#1c1917;--line:#292524;--txt:#e7e5e4;--mut:#a8a29e;--acc:#E95420;--ok:#22c55e;--warn:#f59e0b;--crit:#ef4444}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--txt);font-family:Vazirmatn,Vazir,"IRANSansX","Segoe UI",Tahoma,sans-serif;line-height:1.7;padding:24px 16px 48px}
.wrap{max-width:880px;margin:0 auto}
header{text-align:center;margin-bottom:24px}
h1{font-size:1.5rem;font-weight:800}
h1 .en{color:var(--acc);font-size:1.05rem;display:block;margin-top:4px;font-weight:600}
.sub{color:var(--mut);font-size:.8rem;margin-top:6px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px 20px;margin-bottom:16px}
h2{font-size:1rem;font-weight:700;margin-bottom:14px;color:var(--acc)}
.bigbar{height:16px;background:#000;border-radius:99px;overflow:hidden;border:1px solid var(--line)}
.bigbar>i{display:block;height:100%;border-radius:99px}
.bigbar.ok>i{background:linear-gradient(90deg,var(--ok),#4ade80)}
.bigbar.warn>i{background:linear-gradient(90deg,var(--warn),#fbbf24)}
.bigbar.crit>i{background:linear-gradient(90deg,var(--crit),#f87171)}
.stats{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
.stat{flex:1 1 120px;background:#000;border:1px solid var(--line);border-radius:10px;padding:10px 14px;text-align:center}
.stat b{display:block;font-size:1.15rem}
.stat span{color:var(--mut);font-size:.72rem}
.banner{border-radius:10px;padding:10px 14px;margin-top:14px;font-size:.85rem}
.banner.low{background:rgba(239,68,68,.12);border:1px solid rgba(239,68,68,.4);color:#fca5a5}
.banner.note{background:rgba(245,158,11,.1);border:1px solid rgba(245,158,11,.35);color:#fcd34d}
.row{display:flex;align-items:center;gap:10px;margin-bottom:10px}
.row .lbl{flex:0 0 34%;font-size:.8rem;color:var(--mut);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;direction:ltr;text-align:right}
.bar{flex:1;height:10px;background:#000;border-radius:99px;overflow:hidden}
.bar>i{display:block;height:100%;background:var(--acc);border-radius:99px;opacity:.9}
.row .val{flex:0 0 70px;text-align:left;font-size:.78rem;direction:ltr}
table{width:100%;border-collapse:collapse;font-size:.82rem}
th,td{padding:8px 10px;text-align:right;border-bottom:1px solid var(--line)}
th{color:var(--mut);font-weight:600;cursor:pointer;user-select:none;white-space:nowrap}
th:hover{color:var(--acc)}
th[data-dir="asc"]::after{content:" ▲";color:var(--acc)}
th[data-dir="desc"]::after{content:" ▼";color:var(--acc)}
td.num{direction:ltr;text-align:left;color:var(--txt)}
tr:hover td{background:rgba(233,84,32,.06)}
.muted{color:var(--mut);font-size:.78rem;margin-top:8px}
.empty{color:var(--mut);font-size:.82rem;font-style:italic}
footer{text-align:center;color:var(--mut);font-size:.72rem;margin-top:28px}
footer a{color:var(--acc);text-decoration:none;direction:ltr;unicode-bidi:embed}
@media(max-width:560px){.row .lbl{flex-basis:45%}th,td{padding:6px}}
</style>
</head>
<body>
<div class="wrap">
<header>
  <h1>📊 گزارش تحلیل دیسک<span class="en">Ubuntu Optimizer &amp; Fixer — Disk Analysis</span></h1>
  <div class="sub">نسخه '"$(_html_escape "$SCRIPT_VERSION")"' · تولیدشده در '"$(_html_escape "$HR_TIMESTAMP")"'</div>
</header>'

    # ---- usage summary ----
    local pct_disp="${HR_PCT_NUM}"
    out+='
<section class="card">
  <h2>فضای پارتیشن ریشه ( / )</h2>
  <div class="bigbar '"$sev"'"><i style="width:'"$pct_disp"'%"></i></div>
  <div class="stats">
    <div class="stat"><b>'"$(_html_escape "${HR_TOTAL:-—}")"'</b><span>کل فضای دیسک</span></div>
    <div class="stat"><b>'"$(_html_escape "${HR_USED:-—}")"'</b><span>مصرف‌شده ('"$pct_disp"'٪)</span></div>
    <div class="stat"><b>'"$(_html_escape "${HR_AVAIL:-—}")"'</b><span>آزاد</span></div>
  </div>'
    if [ -n "$HR_AVAIL_MB" ] && [ "$HR_AVAIL_MB" -lt 2048 ] 2>/dev/null; then
        out+='
  <div class="banner low">⚠️ فضای دیسک کم است — فقط '"$(_html_escape "$HR_AVAIL_MB")"' مگابایت آزاد مانده. برای آزادسازی: <b>uo --disk-clean</b></div>'
    fi
    out+='
</section>'

    # ---- category breakdown ----
    out+='
<section class="card">
  <h2>فضا بر اساس دسته</h2>'
    if [ ${#HR_CATS_NAME[@]} -gt 0 ]; then
        local hr_max=1 hr_i hr_kb hr_w
        for hr_kb in "${HR_CATS_KB[@]}"; do
            [ "$hr_kb" -gt "$hr_max" ] && hr_max="$hr_kb"
        done
        for hr_i in "${!HR_CATS_NAME[@]}"; do
            hr_kb="${HR_CATS_KB[$hr_i]}"
            hr_w=$(( hr_kb * 100 / hr_max ))
            [ "$hr_w" -lt 1 ] && hr_w=1
            out+='
  <div class="row">
    <span class="lbl" title="'"$(_html_escape "${HR_CATS_NAME[$hr_i]}")"'">'"$(_html_escape "${HR_CATS_NAME[$hr_i]}")"'</span>
    <span class="bar"><i style="width:'"$hr_w"'%"></i></span>
    <span class="val">'"$(_hr_fmt_kb "$hr_kb")"'</span>
  </div>'
        done
        if [ "$HR_OLD_KERNELS" -gt 0 ] 2>/dev/null; then
            out+='
  <div class="banner note">🧩 '"$HR_OLD_KERNELS"' هستهٔ قدیمی قابل‌حذف — پاکسازی با: <b>uo --disk-clean</b></div>'
        fi
        if [ -n "$HR_TS_COUNT" ] && [ "$HR_TS_COUNT" -gt 0 ] 2>/dev/null; then
            out+='
  <div class="muted">تعداد اسنپ‌شات‌های تایم‌شیفت: '"$HR_TS_COUNT"'</div>'
        fi
    else
        out+='
  <div class="empty">هیچ داده‌ای برای نمایش یافت نشد.</div>'
    fi
    out+='
</section>'

    # ---- /opt table ----
    out+='
<section class="card">
  <h2>بزرگ‌ترین برنامه‌های /opt <span class="muted">(روی عنوان ستون کلیک کنید)</span></h2>'
    if [ ${#HR_OPT_NAME[@]} -gt 0 ]; then
        out+='
  <table data-sortable>
    <thead><tr><th data-key="name">برنامه</th><th data-key="size">حجم</th></tr></thead>
    <tbody>'
        for hr_i in "${!HR_OPT_NAME[@]}"; do
            out+='
      <tr><td>'"$(_html_escape "${HR_OPT_NAME[$hr_i]}")"'</td><td class="num" data-v="'"${HR_OPT_KB[$hr_i]}"'">'"$(_hr_fmt_kb "${HR_OPT_KB[$hr_i]}")"'</td></tr>'
        done
        out+='
    </tbody>
  </table>'
    else
        out+='
  <div class="empty">چیزی در /opt نصب نیست.</div>'
    fi
    out+='
</section>'

    # ---- deb packages table ----
    out+='
<section class="card">
  <h2>بزرگ‌ترین بسته‌های deb <span class="muted">(روی عنوان ستون کلیک کنید)</span></h2>'
    if [ ${#HR_DEB_NAME[@]} -gt 0 ]; then
        out+='
  <table data-sortable>
    <thead><tr><th data-key="name">بسته</th><th data-key="size">حجم نصب‌شده</th></tr></thead>
    <tbody>'
        for hr_i in "${!HR_DEB_NAME[@]}"; do
            out+='
      <tr><td>'"$(_html_escape "${HR_DEB_NAME[$hr_i]}")"'</td><td class="num" data-v="'"${HR_DEB_KB[$hr_i]}"'">'"$(_hr_fmt_kb "${HR_DEB_KB[$hr_i]}")"'</td></tr>'
        done
        out+='
    </tbody>
  </table>'
    else
        out+='
  <div class="empty">اطلاعات بسته‌ها در دسترس نیست (dpkg-query یافت نشد؟).</div>'
    fi
    out+='
</section>'

    out+='
<footer>تولیدشده با <a href="https://github.com/CheginiSoroush/ubuntu-optimizer">uo --disk-report</a> · Ubuntu Optimizer &amp; Fixer v'"$(_html_escape "$SCRIPT_VERSION")"' — کاملاً آفلاین و بدون وابستگی خارجی</footer>
</div>
<script>
document.querySelectorAll("table[data-sortable]").forEach(function(t){
  var headers=t.querySelectorAll("th[data-key]");
  headers.forEach(function(th,i){
    th.addEventListener("click",function(){
      var dir=th.getAttribute("data-dir")==="asc"?"desc":"asc";
      headers.forEach(function(h){h.removeAttribute("data-dir")});
      th.setAttribute("data-dir",dir);
      var tb=t.querySelector("tbody");
      var rows=Array.prototype.slice.call(tb.querySelectorAll("tr"));
      rows.sort(function(a,b){
        var x=a.children[i].getAttribute("data-v"),y=b.children[i].getAttribute("data-v");
        if(x!==null&&y!==null&&!isNaN(parseFloat(x))&&!isNaN(parseFloat(y))){
          x=parseFloat(x);y=parseFloat(y);
        }else{
          x=String(x===null?"":x).toLowerCase();y=String(y===null?"":y).toLowerCase();
        }
        if(x<y)return dir==="asc"?-1:1;
        if(x>y)return dir==="asc"?1:-1;
        return 0;
      });
      rows.forEach(function(r){tb.appendChild(r)});
    });
  });
});
</script>
</body>
</html>'

    printf '%s\n' "$out"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# disk_report_cli() — write the HTML disk report
#
# Orchestrates collect → render → atomic placement. The destination comes from
# DISK_REPORT_FILE (set by the parser, default uo-disk-report.html beside the
# working directory); the main script validates the path up front, and the
# function re-checks defensively so menu callers without validation are safe
# too. The report is rendered into a mktemp file in the target directory and
# moved into place with a single mv — atomicity per the module header.
#
# Globals:   DISK_REPORT_FILE (read), SCRIPT_VERSION (read)
# Arguments: none (uses DISK_REPORT_FILE, falling back to $PWD)
# Returns:   0 — report written
#            1 — destination unusable or render failed (tmp cleaned up)
# ───────────────────────────────────────────────────────────────────────────────
disk_report_cli() {
    local out_file="${DISK_REPORT_FILE:-$PWD/uo-disk-report.html}"

    header "🖥 HTML Disk Report"

    # defensive re-validation (the CLI path already checked this up front)
    if [ -e "$out_file" ] && [ ! -w "$out_file" ]; then
        failure "Cannot write to file: $out_file"
        return 1
    fi
    if [ ! -w "$(dirname -- "$out_file")" ]; then
        failure "Cannot write to directory: $(dirname -- "$out_file")"
        return 1
    fi

    info "Collecting disk data (read-only; this may take a moment)..."
    _disk_report_collect

    local tmp
    tmp=$(mktemp "$(dirname -- "$out_file")/.uo-disk-report.XXXXXX") || {
        failure "Could not create a temporary file next to: $out_file"
        return 1
    }

    if ! _disk_report_render > "$tmp"; then
        rm -f "$tmp"
        failure "HTML report could not be rendered."
        return 1
    fi

    if ! mv -f "$tmp" "$out_file"; then
        rm -f "$tmp"
        failure "Could not move the report into place: $out_file"
        return 1
    fi

    success "HTML report saved to: $out_file"
    info "Open in a browser: xdg-open \"$out_file\""
    log_write "INFO" "disk HTML report written: $out_file"
    return 0
}

# ───────────────────────────────────────────────────────────────────────────────
# menu_disk_report() — interactive wrapper for menu entry 19
#
# Asks for the output path (default: uo-disk-report.html in the current
# directory), validates it and runs the same CLI flow.
#
# Arguments: none
# Returns:   0 — always
# ───────────────────────────────────────────────────────────────────────────────
menu_disk_report() {
    local def="$PWD/uo-disk-report.html"
    echo ""
    info "The analysis is saved as a self-contained HTML file (charts + sortable tables)."
    local f
    read -r -p "   Output file [$def]: " f || return 0
    f="${f:-$def}"
    if [ -e "$f" ] && [ ! -w "$f" ]; then
        failure "Cannot write to file: $f"
        return 0
    fi
    if [ ! -w "$(dirname -- "$f")" ]; then
        failure "Cannot write to directory: $(dirname -- "$f")"
        return 0
    fi
    DISK_REPORT_FILE="$f"
    disk_report_cli
}
