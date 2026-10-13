#!/usr/bin/env bats
# ============================================================
#   test/htmlreport.bats — tests for the HTML disk report
#   (lib/htmlreport.sh, the --disk-report flag)
#   Author & Designer: Soroush Chegini (CheginiSoroush)
#
#   The module is exercised at two levels:
#     • CLI level — the real entry script with --disk-report in
#       a temp HOME: the happy path (default + explicit path),
#       the flag-not-eaten semantics, fail-fast on unwritable
#       destinations, overwrite semantics and cross-validation.
#       df/du/dpkg-query are real (the sandbox/CI has them);
#       no root is needed — sudo-protected sections degrade.
#     • Function level — lib/common.sh + lib/disk.sh +
#       lib/htmlreport.sh sourced into the test shell; the HR_*
#       globals are seeded by hand so the renderer is checked
#       as a pure function, including hostile names that must
#       be HTML-escaped.
#   Everything runs fully offline.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Targeted copy: ubuntu-optimizer.sh + lib/*.sh only — a full-tree cp
    # would drag website/node_modules (~700 MB when present) and stall tests
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

# Load only the modules an htmlreport test needs, into the test shell
load_hr() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/disk.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/htmlreport.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

# Seed every global the renderer reads — callers override per test
seed_hr() {
    HR_TIMESTAMP="2026-01-01 10:00:00"
    HR_TOTAL="10G" HR_USED="2G" HR_AVAIL="8G" HR_PCT="20%" HR_PCT_NUM=20
    HR_AVAIL_MB=8192
    HR_CATS_NAME=() HR_CATS_KB=()
    HR_TS_COUNT=""
    HR_OLD_KERNELS=0
    HR_OPT_NAME=() HR_OPT_KB=()
    HR_DEB_NAME=() HR_DEB_KB=()
}

# ---------- CLI: happy paths ----------

@test "cli: --disk-report PATH writes an RTL self-contained HTML report" {
    run run_uo --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/r.html" ]
    run head -c 60 "$TEST_HOME/r.html"
    [[ "$output" == "<!DOCTYPE html>"* ]]
    grep -q 'dir="rtl" lang="fa"' "$TEST_HOME/r.html"
    grep -q '<meta charset="utf-8">' "$TEST_HOME/r.html"
}

@test "cli: without a path the report lands beside the working directory" {
    run bash -c "cd '$TEST_HOME' && bash '$TEST_HOME/uo-tree/ubuntu-optimizer.sh' --no-log --disk-report"
    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/uo-disk-report.html" ]
}

@test "cli: report shows the usage summary, all sections and the footer" {
    run run_uo --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 0 ]
    grep -q "فضای پارتیشن ریشه" "$TEST_HOME/r.html"
    grep -q "فضا بر اساس دسته" "$TEST_HOME/r.html"
    grep -q "بزرگ‌ترین بسته‌های deb" "$TEST_HOME/r.html"
    grep -q "uo --disk-report" "$TEST_HOME/r.html"
}

@test "cli: a following flag is never eaten as the file argument" {
    run run_uo --disk-report --no-color --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/r.html" ]
}

@test "cli: an existing report is replaced cleanly (no tmp leftovers)" {
    run run_uo --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 0 ]
    run run_uo --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 0 ]
    [ "$(find "$TEST_HOME" -maxdepth 1 -name '.uo-disk-report.*' | wc -l)" -eq 0 ]
    [ "$(grep -c '<!DOCTYPE html>' "$TEST_HOME/r.html")" -eq 1 ]
}

# ---------- CLI: fail-fast paths ----------

@test "cli: unwritable destination exits 1 and writes nothing" {
    run run_uo --disk-report "$TEST_HOME/no-such-dir/r.html"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot write to file"* ]]
    [ ! -e "$TEST_HOME/no-such-dir" ]
}

@test "cli: --disk-report together with --json is rejected" {
    run run_uo --disk-report "$TEST_HOME/r.html" --json
    [ "$status" -eq 1 ]
    [[ "$output" == *"--json is only valid together with --report."* ]]
}

@test "cli: --disk-report is not a --dry-run flow" {
    run run_uo --dry-run --disk-report "$TEST_HOME/r.html"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--dry-run is only valid with"* ]]
}

# ---------- Function level: helpers ----------

@test "helper: _html_escape escapes the five HTML-critical characters" {
    load_hr
    run _html_escape '&<>"'"'"''
    [ "$status" -eq 0 ]
    [ "$output" = "&amp;&lt;&gt;&quot;&#39;" ]
}

@test "helper: _html_escape leaves plain text unchanged" {
    load_hr
    run _html_escape 'hello world 123'
    [ "$output" = "hello world 123" ]
}

@test "helper: _hr_fmt_kb humanizes KiB (KB, MB, GB)" {
    load_hr
    run _hr_fmt_kb 0
    [ "$output" = "0 KB" ]
    run _hr_fmt_kb 512
    [ "$output" = "512 KB" ]
    run _hr_fmt_kb 2048
    [ "$output" = "2.0 MB" ]
    run _hr_fmt_kb 1572864
    [ "$output" = "1.5 GB" ]
}

@test "helper: _hr_fmt_kb renders garbage as an em dash" {
    load_hr
    run _hr_fmt_kb "not-a-number"
    [ "$output" = "—" ]
}

@test "helper: _hr_severity maps percentages to ok/warn/crit" {
    load_hr
    run _hr_severity 10;  [ "$output" = "ok" ]
    run _hr_severity 59;  [ "$output" = "ok" ]
    run _hr_severity 60;  [ "$output" = "warn" ]
    run _hr_severity 84;  [ "$output" = "warn" ]
    run _hr_severity 85;  [ "$output" = "crit" ]
    run _hr_severity 100; [ "$output" = "crit" ]
    run _hr_severity "x"; [ "$output" = "ok" ]
}

@test "helper: _hr_add_cat skips empty, non-numeric and zero sizes" {
    load_hr
    HR_CATS_NAME=() HR_CATS_KB=()
    _hr_add_cat "good" "5000"
    _hr_add_cat "zero" "0"
    _hr_add_cat "empty" ""
    _hr_add_cat "junk" "abc"
    [ "${#HR_CATS_NAME[@]}" -eq 1 ]
    [ "${HR_CATS_NAME[0]}" = "good" ]
    [ "${HR_CATS_KB[0]}" = "5000" ]
}

# ---------- Function level: the pure renderer ----------

@test "render: seeded globals produce a complete document skeleton" {
    load_hr; seed_hr
    run _disk_report_render
    [ "$status" -eq 0 ]
    [[ "$output" == "<!DOCTYPE html>"* ]]
    [[ "$output" == *'dir="rtl" lang="fa"'* ]]
    [[ "$output" == *'<meta charset="utf-8">'* ]]
    [[ "$output" == *"</html>"* ]]
}

@test "render: big usage bar carries the severity class and percent width" {
    load_hr; seed_hr
    HR_PCT_NUM=30
    run _disk_report_render
    [[ "$output" == *'bigbar ok'* ]]
    [[ "$output" == *'width:30%'* ]]
    HR_PCT_NUM=90
    run _disk_report_render
    [[ "$output" == *'bigbar crit'* ]]
}

@test "render: category bars are relative to the largest entry" {
    load_hr; seed_hr
    HR_CATS_NAME=("big" "half" "tiny")
    HR_CATS_KB=(50000 25000 100)
    run _disk_report_render
    [[ "$output" == *'width:100%'* ]]
    [[ "$output" == *'width:50%'* ]]
    [[ "$output" == *'width:1%'* ]]   # floor so 0.2% stays visible
    [[ "$output" == *"48.8 MB"* ]]   # _hr_fmt_kb on the max row (50000 KiB)
}

@test "render: low disk warning appears only under the 2 GB threshold" {
    load_hr; seed_hr
    HR_AVAIL_MB=1500
    run _disk_report_render
    [[ "$output" == *"فضای دیسک کم است"* ]]
    [[ "$output" == *"1500"* ]]
    HR_AVAIL_MB=50000
    run _disk_report_render
    [[ "$output" != *"فضای دیسک کم است"* ]]
}

@test "render: hostile names are HTML-escaped everywhere" {
    load_hr; seed_hr
    HR_CATS_NAME=('cat <script>alert(1)</script> & "x"')
    HR_CATS_KB=(1000)
    HR_DEB_NAME=('pkg">&x<')
    HR_DEB_KB=(2000)
    run _disk_report_render
    [ "$status" -eq 0 ]
    [[ "$output" == *"cat &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;x&quot;"* ]]
    [[ "$output" == *"pkg&quot;&gt;&amp;x&lt;"* ]]
    # the raw payload must never survive into the document
    [[ "$output" != *'cat <script>'* ]]
    [[ "$output" != *'pkg">&x<'* ]]
}

@test "render: old-kernel and timeshift banners render on demand" {
    load_hr; seed_hr
    HR_OLD_KERNELS=3
    HR_CATS_NAME=("x") HR_CATS_KB=(1000)
    run _disk_report_render
    [[ "$output" == *"۳ هستهٔ قدیمی"* || "$output" == *"3 هستهٔ قدیمی"* ]]
    HR_TS_COUNT=2
    run _disk_report_render
    [[ "$output" == *"تعداد اسنپ‌شات‌های تایم‌شیفت: 2"* ]]
}

@test "render: empty sections fall back to placeholders, never broken markup" {
    load_hr; seed_hr
    HR_CATS_NAME=() HR_CATS_KB=()
    HR_OPT_NAME=() HR_OPT_KB=()
    HR_DEB_NAME=() HR_DEB_KB=()
    run _disk_report_render
    [ "$status" -eq 0 ]
    [[ "$output" == *"هیچ داده‌ای برای نمایش یافت نشد."* ]]
    [[ "$output" == *"چیزی در /opt نصب نیست."* ]]
    [[ "$output" == *"</html>"* ]]
}

@test "render: table rows carry numeric data-v for the sorter" {
    load_hr; seed_hr
    HR_DEB_NAME=("abc" "def")
    HR_DEB_KB=(1234 5678)
    run _disk_report_render
    [[ "$output" == *'data-v="1234"'* ]]
    [[ "$output" == *'data-v="5678"'* ]]
    [[ "$output" == *'addEventListener("click"'* ]]
}

@test "render: footer shows the version and the repo link" {
    load_hr; seed_hr
    run _disk_report_render
    [[ "$output" == *"v$SCRIPT_VERSION"* ]]
    [[ "$output" == *"https://github.com/CheginiSoroush/ubuntu-optimizer"* ]]
}

# ---------- Function level: collect (real probes, graceful) ----------

@test "collect: fills the numeric usage fields from the real filesystem" {
    load_hr
    # direct call (not via run): the collected HR_* globals must land in
    # this shell — bats run() captures in a subshell and drops them
    _disk_report_collect
    [ "$?" -eq 0 ]
    [ -n "$HR_TIMESTAMP" ]
    [[ "$HR_PCT_NUM" =~ ^[0-9]+$ ]]
    [[ "$HR_OLD_KERNELS" =~ ^[0-9]+$ ]]
    [ -n "$HR_TOTAL" ]
}

@test "collect: user-readable categories appear, missing ones are skipped" {
    load_hr
    mkdir -p "$HOME/.local/share"
    dd if=/dev/zero of="$HOME/.local/blob" bs=1024 count=16 2>/dev/null
    _disk_report_collect
    local found=0
    for c in "${HR_CATS_NAME[@]}"; do
        [[ "$c" == *"~/.local"* ]] && found=1
    done
    [ "$found" -eq 1 ]
}
