#!/usr/bin/env bats
# ============================================================
#   test/i18n.bats — tests for the fa/en translation framework
#   (lib/i18n.sh + its wiring)
#
#   Two layers:
#     • Unit level — lib/i18n.sh sourced standalone: _i18n_detect
#       (pure locale → language mapping), i18n_init (the documented
#       resolution chain env → config → detect → default, including
#       the real lib/config.sh pipeline for the `language` key) and
#       t() (printf substitution, FA→EN→key fallback ladder).
#     • CLI level — the real entry script with a temp HOME: Persian
#       rendering under UO_LANG=fa, the byte-identical English
#       default, --lang persistence through the config system and
#       --lang-show source attribution (env/config/detected/default).
#   Hermetic: temp HOME + XDG, locale vars pinned per test, targeted
#   copy of ubuntu-optimizer.sh + lib/*.sh only (the repo carries
#   website/ build artifacts — a full-tree cp would stall the suite),
#   `clear` as a PATH stub for deterministic menu renders; teardown
#   removes the mktemp sandbox only.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    unset UO_LANG UO_LANGUAGE LC_ALL LC_MESSAGES
    export LANG=C
    # Copy ONLY the entry script + lib/ modules: the repo carries ~700MB of
    # website build artifacts (website/node_modules, website/.next), which a
    # full-tree cp would drag into every setup. The CLI entry script sources
    # everything it needs from its own lib/ directory.
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    # clear stub — deterministic menu rendering without a terminal
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/clear"
    chmod +x "$STUB_BIN/clear"

    CONFIG_DIR="$TEST_HOME/.config/uo"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    env UO_AUTO_UPDATE=0 PATH="$STUB_BIN:$PATH" \
        bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

write_config() {
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$1" > "$CONFIG_DIR/config.conf"
}

source_i18n() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/i18n.sh"
}

# ---------- CLI level: the resolution chain end to end ----------

@test "cli: UO_LANG=fa renders the Persian banner and menu labels" {
    UO_LANG=fa run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"بهینه‌ساز و تعمیرکار اوبونتو"* ]]
    [[ "$output" == *"   1) 🌐 بهینه‌سازی شبکه"* ]]
    [[ "$output" == *"   0) خروج"* ]]
    [[ "$output" == *"خداحافظ"* ]]
    # the English label must be gone when fa is active
    [[ "$output" != *"Network optimization"* ]]
}

@test "cli: UO_LANG=en renders the English menu" {
    UO_LANG=en run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"   1) 🌐 Network optimization"* ]]
    [[ "$output" == *"   0) Exit"* ]]
    [[ "$output" == *"Goodbye"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

@test "cli: nothing set anywhere renders the byte-identical English default" {
    # no UO_LANG, no config key, LANG=C — the pre-i18n behavior
    run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ubuntu Optimizer & Fixer - v${SCRIPT_VERSION:-}"* ]]
    [[ "$output" == *"   1) 🌐 Network optimization"* ]]
    [[ "$output" == *"   0) Exit"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

@test "cli: invalid UO_LANG resolves to en silently" {
    UO_LANG=de run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Network optimization"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

@test "cli: invalid UO_LANG is terminal — a fa config cannot override it" {
    # An explicit override that is garbage must never be second-guessed
    # by the stored preference: en wins, no fall-through to the config.
    write_config 'language=fa'
    UO_LANG=de run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Network optimization"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

@test "cli: config file key language=fa renders Persian" {
    write_config 'language=fa'
    run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"بهینه‌ساز و تعمیرکار اوبونتو"* ]]
    [[ "$output" == *"بهینه‌سازی شبکه"* ]]
}

@test "cli: UO_LANG=en wins over the config file language=fa" {
    write_config 'language=fa'
    UO_LANG=en run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Network optimization"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

@test "cli: a config file with an invalid language value is rejected and en stays" {
    # config.sh's own paranoia: the value never reaches i18n at all
    write_config 'language=xx'
    run run_uo --config-show
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid value for language: xx"* ]]
    run run_uo < <(printf '0\n')
    [ "$status" -eq 0 ]
    [[ "$output" == *"Network optimization"* ]]
    [[ "$output" != *"بهینه‌سازی"* ]]
}

# ---------- unit level: _i18n_detect ----------

@test "_i18n_detect maps fa-IR fa_IR.UTF-8 and pe_IR to fa and en_US and C to en" {
    source_i18n
    run _i18n_detect "fa-IR"
    [ "$status" -eq 0 ]
    [ "$output" = "fa" ]
    run _i18n_detect "fa_IR.UTF-8"
    [ "$output" = "fa" ]
    run _i18n_detect "FA"
    [ "$output" = "fa" ]
    run _i18n_detect "pe_IR"
    [ "$output" = "fa" ]
    run _i18n_detect "en_US.UTF-8"
    [ "$output" = "en" ]
    run _i18n_detect "C"
    [ "$output" = "en" ]
    run _i18n_detect ""
    [ "$output" = "en" ]
}

# ---------- unit level: i18n_init resolution chain ----------

@test "i18n_init: UO_LANG is case-insensitive and an invalid value lands on en/default" {
    source_i18n
    UO_LANG="FA" i18n_init
    [ "$UO_LANG_ACTIVE" = "fa" ]
    [ "$UO_LANG_SOURCE" = "env" ]
    UO_LANG_ACTIVE=""
    UO_LANG="En" i18n_init
    [ "$UO_LANG_ACTIVE" = "en" ]
    [ "$UO_LANG_SOURCE" = "env" ]
    UO_LANG_ACTIVE=""
    UO_LANG="de" i18n_init
    [ "$UO_LANG_ACTIVE" = "en" ]
    [ "$UO_LANG_SOURCE" = "default" ]
}

@test "i18n_init: the config language flows through the real lib/config.sh pipeline" {
    source_i18n
    # production module order is common → config; config.sh calls warn() at
    # load time, so it cannot be sourced standalone (127 without common.sh)
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/config.sh"
    write_config 'language=FA'
    uo_config_load
    i18n_init
    [ "$UO_LANGUAGE" = "fa" ]        # normalized to lowercase by config.sh
    [ "$UO_LANG_ACTIVE" = "fa" ]
    [ "$UO_LANG_SOURCE" = "config" ]
    # an invalid value is rejected by the config system → chain continues
    UO_LANG_ACTIVE=""
    UO_LANGUAGE=""
    write_config 'language=xx'
    uo_config_load
    i18n_init
    [ -z "$UO_LANGUAGE" ]
    [ "$UO_LANG_ACTIVE" = "en" ]
    [ "$UO_LANG_SOURCE" = "default" ]
}

@test "i18n_init: locale detection walks LC_ALL then LC_MESSAGES then LANG" {
    source_i18n
    LC_ALL=fa_IR.UTF-8 i18n_init
    [ "$UO_LANG_ACTIVE" = "fa" ]
    [ "$UO_LANG_SOURCE" = "detected" ]
    # LC_MESSAGES beats LANG when LC_ALL is unset
    UO_LANG_ACTIVE=""
    unset LC_ALL
    LC_MESSAGES=fa_IR.UTF-8 LANG=C i18n_init
    [ "$UO_LANG_ACTIVE" = "fa" ]
    [ "$UO_LANG_SOURCE" = "detected" ]
    # a non-fa LC_ALL does not stop the walk — LANG is still consulted
    UO_LANG_ACTIVE=""
    unset LC_MESSAGES
    LC_ALL=C LANG=fa_IR.UTF-8 i18n_init
    [ "$UO_LANG_ACTIVE" = "fa" ]
    [ "$UO_LANG_SOURCE" = "detected" ]
    # nothing Persian anywhere → the documented default
    UO_LANG_ACTIVE=""
    LC_ALL=C LANG=C i18n_init
    [ "$UO_LANG_ACTIVE" = "en" ]
    [ "$UO_LANG_SOURCE" = "default" ]
}

# ---------- unit level: t() ----------

@test "t() substitutes printf-style arguments and prints literal values without any" {
    source_i18n
    UO_LANG_ACTIVE=en
    run t banner.title "9.9"
    [ "$status" -eq 0 ]
    [ "$output" = "       Ubuntu Optimizer & Fixer - v9.9" ]
    UO_LANG_ACTIVE=fa
    run t banner.title "9.9"
    [ "$output" = "       بهینه‌ساز و تعمیرکار اوبونتو - نسخه 9.9" ]
    # without arguments the value is printed literally — a %s inside a
    # translation must never misfire as a format spec (en: back to the
    # English default after the fa banner check above)
    UO_LANG_ACTIVE=en
    run t msg.report_saved
    [ "$output" = "Report saved to: %s" ]
}

@test "t() falls back to the English string for a key missing from fa and to the key itself when missing from both" {
    source_i18n
    EN_MSG[msg.untranslatable]="English only"
    UO_LANG_ACTIVE=fa
    run t msg.untranslatable
    [ "$status" -eq 0 ]
    [ "$output" = "English only" ]
    # missing from BOTH catalogs → the key itself, silently
    run t msg.totally_bogus_key
    [ "$output" = "msg.totally_bogus_key" ]
    # a dot-less key has no catalog group → the key itself
    run t boguskey
    [ "$output" = "boguskey" ]
}

# ---------- CLI level: --lang persistence ----------

@test "cli: --lang fa persists language=fa into the config file" {
    [ ! -f "$CONFIG_DIR/config.conf" ]
    run run_uo --lang fa
    [ "$status" -eq 0 ]
    [ -f "$CONFIG_DIR/config.conf" ]
    grep -qx 'language=fa' "$CONFIG_DIR/config.conf"
    # the confirmation is printed in the NEW language
    [[ "$output" == *"زبان روی fa تنظیم شد"* ]]
    # and the choice takes effect on the very next run
    run run_uo < <(printf '0\n')
    [[ "$output" == *"بهینه‌سازی شبکه"* ]]
    # case-insensitive value, same result
    run run_uo --lang FA
    [ "$status" -eq 0 ]
    grep -qx 'language=fa' "$CONFIG_DIR/config.conf"
}

@test "cli: --lang replaces an existing language line and keeps the rest of the config" {
    write_config 'ASSUME_YES=1
language=en
DNS_SERVERS=1.1.1.1'
    run run_uo --lang fa
    [ "$status" -eq 0 ]
    local content
    content="$(cat "$CONFIG_DIR/config.conf")"
    [ "$(grep -c '^language=fa$' <<< "$content")" -eq 1 ]
    [[ "$content" == *"ASSUME_YES=1"* ]]
    [[ "$content" == *"DNS_SERVERS=1.1.1.1"* ]]
    [ "$(wc -l < "$CONFIG_DIR/config.conf")" -eq 3 ]
}

@test "cli: --lang rejects invalid values and persists nothing" {
    run run_uo --lang xx
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid language: xx"* ]]
    [[ "$output" == *"Valid languages: fa · en"* ]]
    [ ! -e "$CONFIG_DIR/config.conf" ]
    # a missing value is a usage error too
    run run_uo --lang
    [ "$status" -eq 1 ]
    [[ "$output" == *"--lang requires a value"* ]]
    [ ! -e "$CONFIG_DIR/config.conf" ]
}

# ---------- CLI level: --lang-show source attribution ----------

@test "cli: --lang-show reports the effective language and its exact source" {
    # default
    run run_uo --lang-show
    [ "$status" -eq 0 ]
    [ "$output" = "Language: en (source: default)" ]
    # env
    UO_LANG=en run run_uo --lang-show
    [ "$output" = "Language: en (source: env)" ]
    # config (label renders in Persian because fa is the effective language)
    write_config 'language=fa'
    run run_uo --lang-show
    [[ "$output" == *"fa"* ]]
    [[ "$output" == *"config"* ]]
    # detected from the locale — the config language=fa written above must
    # go first: config outranks detection by the documented resolution order
    write_config '# no language key in this config'
    LC_ALL=fa_IR.UTF-8 run run_uo --lang-show
    [[ "$output" == *"fa"* ]]
    [[ "$output" == *"detected"* ]]
}

# ---------- wiring: docs & completions ----------

@test "usage documents --lang/--lang-show and the UO_LANG environment variable" {
    run run_uo --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--lang fa|en"* ]]
    [[ "$output" == *"--lang-show"* ]]
    [[ "$output" == *"UO_LANG"* ]]
}

@test "both completions offer --lang with fa/en values and --lang-show as a plain flag" {
    grep -q -- '--lang' "$BATS_TEST_DIRNAME/../completions/uo"
    grep -q -- '--lang-show' "$BATS_TEST_DIRNAME/../completions/uo"
    grep -q -- 'fa en' "$BATS_TEST_DIRNAME/../completions/uo"
    grep -q -- '--lang' "$BATS_TEST_DIRNAME/../completions/_uo"
    grep -q -- '--lang-show' "$BATS_TEST_DIRNAME/../completions/_uo"
    grep -q -- 'language:(fa en)' "$BATS_TEST_DIRNAME/../completions/_uo"
}
