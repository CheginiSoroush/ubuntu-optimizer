# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [7.13.0]

### Added
- **Automatic self-update at every startup** — `uo` now keeps itself current:
  before any work runs, a TTL-cached version check (default every 5 minutes,
  `UO_UPDATE_CHECK_TTL` overrides, `0` = every run) compares the installed
  SCRIPT_VERSION with the official repository over a short 3s/6s timeout.
  When a strictly newer version exists:
  - an interactive run gets **one banner + one y/n question**; on accept the
    update applies (git pull for clones, the verified archive for static
    copies) and the process **re-execs into the fresh code with the original
    arguments** — same command, new version, no second invocation needed;
  - unattended runs (`-y`) apply the update straight away, promptless —
    scheduled `uo --update -y` timers stay current automatically;
  - machine modes (`--json`, `--output`) and piped runs get a one-line stderr
    notice, stdout stays pure, nothing is downloaded.
  Every failure path (offline, rate limit, declined, failed download, dirty
  git tree) falls through to the normal run — the check can never block real
  work. Opt out for one run with the new `--no-update` flag, or permanently
  with `UO_AUTO_UPDATE=0`; `--self-update` and `--timer-tick` keep owning
  their own flows. The check result is cached atomically under
  `~/.cache/ubuntu-optimizer/autoupdate.check`.
- Bash + zsh completions learned `--no-update`; `uo --help` documents the
  flag, both environment variables and three new examples.

### Tests
- test/selfupdate.bats: 22 new tests (37 total) covering the cache
  round-trip and malformed-cache handling, every opt-out path, the TTL
  resolution (fresh/stale/zero), the silent network fallthrough, the JSON
  and piped notice modes, the -y apply + re-exec contract, the failed-update
  fallthrough, the dirty-tree guard in auto mode and quiet-mode fetch
  behavior.

## [7.12.0]$

### Added
- **Resilient GitHub API layer** (lib/github.sh) — every API call now rides a
  retry wrapper instead of a single bare `curl`:
  - **Exponential backoff** for transient failures (transport errors, HTTP 5xx):
    1 s → 2 s → 4 s → 8 s, capped by `UO_GH_BACKOFF_MAX` (default 8), with a
    progress warning per attempt (`attempt 2/3 ...`).
  - **Rate-limit respect**: on HTTP 403 with a rate-limit message body, the
    wrapper reads `X-RateLimit-Reset` and — when the window lifts within
    `UO_GH_RATELIMIT_MAX_WAIT` seconds (default 60) — waits exactly that long
    and retries once; a longer wait fails fast with the GH_TOKEN tip so the
    user is never silently stalled for minutes. The tool never hammers a
    closed window.
  - **`Retry-After` honored** on HTTP 429/503 (capped by the same max-wait),
    falling back to the exponential backoff when the header is absent.
  - **Tuning knobs**: `UO_GH_RETRIES` (default 3, clamped 1–6),
    `UO_GH_BACKOFF_MAX`, `UO_GH_RATELIMIT_MAX_WAIT`.
  - `gh_fetch_latest` now maps failures on the HTTP status code first
    (network → 403 rate-limit → 404 not-found → generic) and keeps the
    message-body matching as a fallback for cached responses.

### Fixed
- test/github.bats, test/jsonreport.bats, test/reportfile.bats:
  three latent test bugs — a quote-nesting construct that bash 5.2's parser
  rejects outright (`"$(f "$(g "x"))"`), a `$()`-stripped newline literal, and
  a monotonicity assertion that raced the second-resolution timestamp (the
  sleep its own comment relied on was missing).

### Tests
- test/github.bats: 17 new tests (30 total) covering the backoff table, the
  caps, CRLF-safe header parsing, and the full `gh_api_get` behavior matrix
  against a stubbed curl/sleep pair (200 / 5xx-recovery / 404-no-retry /
  near-reset wait / far-reset fast-fail / Retry-After / retry clamp).

## [7.11.0]

### Added
- **Self-contained HTML disk report** (new `lib/htmlreport.sh`) —
  `uo --disk-report [FILE]` re-runs the same read-only analysis as the
  terminal's `--disk` (root usage, category breakdown, largest /opt apps,
  largest deb packages) and renders it into one standalone `uo-disk-report.html`
  (default name) that opens in any browser — far more readable than the
  terminal for heavy folders, easy to share or archive:
  - **Fully offline document:** inline CSS + ~30 lines of vanilla JS for the
    sortable tables — no CDN, no framework, no internet needed.
  - **Charts & tables:** a big severity-colored usage bar (ok < 60 % ·
    warn < 85 % · crit ≥ 85 %), per-category bars scaled to the largest
    entry, and two click-to-sort tables (`/opt` apps, deb packages) that sort
    by name or size.
  - **RTL Persian layout** with English technical terms — the file renders
    correctly everywhere; a low-space banner appears under the same 2 GB
    threshold the terminal analysis warns at.
  - **Injection-safe by construction:** every system-derived value (paths,
    package names, sizes) passes an HTML-escape helper before it enters the
    document — a folder named `<script>` can never inject markup (correct on
    bash 5.2 too, where `patsub_replacement` would otherwise mangle the
    entities).
  - **Atomic write:** rendered into a mktemp file in the target directory and
    moved into place with a single `mv` — a half-written report can never
    exist. The destination is validated up front (writable dir, writable
    existing file) and fails fast with exit 1.
  - **Graceful degradation:** missing directories or sudo-less environments
    simply omit those sections — the report never breaks or comes back empty.
- **Interactive menu, entry 19:** 🖥 Disk report (HTML, shareable) — asks
  for the output path and runs the same validated CLI code path.
- Both completions (bash + zsh) learn `--disk-report` (file-path completion).

### Fixed
- `_html_escape` guards against bash 5.2's `patsub_replacement` behavior, so
  HTML entities survive on every supported bash.

### Tests
- New `test/htmlreport.bats` — 25 cases: CLI happy paths (explicit path,
  default path, flag-not-eaten semantics, overwrite without tmp leftovers),
  fail-fast paths (unwritable destination, `--json` conflict, `--dry-run`
  rejection), helper functions (escaping incl. the five critical characters,
  KiB humanizer, severity mapping, category validation) and the pure
  renderer seeded with hand-built globals (document skeleton, severity
  classes, relative bar widths, low-space banner threshold, hostile names
  escaped everywhere, empty-section placeholders, sorter hooks, collect
  parity on the real filesystem). 207 tests total.

## [7.10.0]

### Added
- **Scheduled updates as a systemd timer** (new `lib/timer.sh`) —
  `uo --timer-install weekly` installs and enables a real `uo-update.timer`
  that runs `uo --update -y --no-color` on a schedule; missed runs are
  replayed after downtime (`Persistent=true`) and the load on mirrors is
  spread with `RandomizedDelaySec=15m`:
  - **Two scopes:** the default *user* timer lives in
    `~/.config/systemd/user` and needs no root at all (with an
    `enable-linger` hint so it also fires while you are logged out);
    `--timer-system` places the classical units in `/etc/systemd/system`
    via sudo — the right choice for headless servers.
  - **Two modes:** apply (default — unattended updates) and **monitor**
    (`--timer-notify-only`): the schedule runs `uo --timer-tick` instead,
    which mutates nothing — it appends a read-only JSON report snapshot to
    `~/.local/share/ubuntu-optimizer/report-log.jsonl` (the exact JSONL
    series the dashboard Trends tab charts), logs the verdict to the
    journal and raises a desktop notification only when the summary is not
    "good" (RAM/disk/failed-services details included).
- **Transparency & control around the timer:**
  - `--timer-preview [PERIOD]` — print the unit files an install would
    write, byte for byte. Pure text rendering works everywhere, including
    machines and containers without systemd.
  - `--timer-status` — installed? enabled? next runs? last journal verdict?
  - `--timer-log [N]` — the last N journal lines of the scheduled runs.
  - `--timer-remove` — disable + delete the units (clean no-op when absent).
  - Periods are a strict whitelist (hourly · daily · weekly · monthly)
    mapped onto systemd calendar keywords — user input never reaches the
    unit files, so there is nothing to inject.
- **Interactive menu, entry 18:** ⏰ Scheduled updates — install (apply or
  monitor), preview, status, log and remove, all through the same
  validated CLI code paths.
- Both completions (bash + zsh) learn the eight new flags (period words and
  line counts complete their values); `lib/timer.sh` joins
  `install.sh`'s required modules and the CI gate.
- 32 new bats tests (`test/timer.bats`): rendering parity between preview
  and install, the four calendar mappings, monitor/system-scope unit
  variants, modifier cross-validation, graceful degradation without
  systemd, install/remove verified end-to-end against a recording
  systemctl stub, and the monitor tick's snapshot/notification behavior
  (healthy verdicts never notify; critical ones always do).

### Changed
- Test count 150 → **182**.

## [7.9.0]

### Added
- **TTL cache for costly operations** (new `lib/cache.sh`) — results that do
  not change within minutes are stored on disk with an expiry timestamp and
  served instantly on the next run:
  - **Internet connectivity verdict** (`--report`, JSON report): the
    multi-method probe can cost up to ~10 s of timeouts; the verdict is
    cached for 120 s when online and only 60 s when offline, so a
    just-fixed connection is noticed quickly.
  - **apt list freshness** (`--update-apt`, `--update`): when this tool
    already ran a successful `apt update` within the last 10 minutes, the
    redundant refresh is skipped with an informational note — the marker
    is written only by this tool, so manually refreshed lists never
    cause a skip.
  - **GitHub release metadata** (`--github-install`, `--github-update`):
    the raw `releases/latest` API response is cached per repository for
    5 minutes — the anonymous API allows only 60 requests/hour per IP,
    and repeated installs/update checks within the TTL now cost zero API
    calls. Error responses are never cached.
- **Cache transparency & control:**
  - `--cache-stats` — list every entry with its size and remaining TTL
  - `--cache-clear` — wipe the cache; composes with other actions
    (`uo --cache-clear --update-apt` forces a fresh apt refresh)
  - `--no-cache` — bypass the cache for one run (reads miss, writes skipped)
  - `NO_CACHE=0|1` — new config-file key (same precedence machinery as the
    other keys); `UO_NO_CACHE=1` environment variable for one-off overrides
- **Engineering guarantees:** keys are restricted to a safe charset
  (path traversal impossible by construction), writes are atomic
  (tmp file + `mv`), a failing command is never cached, and cache reads
  return the value through a variable (not stdout) so the hit/miss session
  counters always stay accurate. The session summary now reports
  `⚡ Cache: N hit(s), M miss(es)` whenever the cache was consulted.
- Both completions (bash + zsh) learn the three new flags; `NO_CACHE` joins
  the `--config-show` key list and the annotated `--config-example` template.
- 27 new bats tests (`test/cache.bats`, fully offline — network probes and
  curl are replaced by stub functions with call counters, apt by a stubbed
  `sudo`) — 150 total.

## [7.8.0]

### Added
- **Optional config file: `~/.config/uo/config.conf`** (respects
  `$XDG_CONFIG_HOME`) — persist preferences for every run, interactive or
  cron, without repeating flags:
  - `ASSUME_YES` — auto-confirm everything (same as `-y` on every run)
  - `NO_COLOR` — plain, colorless output
  - `NO_LOG` — do not write log files
  - `DRY_RUN` — always preview, never change anything
  - `DNS_SERVERS` — custom resolvers for `--network`/`--optimize`
- **Parsing is paranoid by design:** the file is never `source`d or `eval`'d —
  only `KEY=VALUE` lines are read (blank lines, `#` comments and optional
  matching quotes allowed), every value is validated against its key, unknown
  keys and malformed lines report their line number and are skipped. A config
  file can never execute a command and one bad line never aborts a run.
- **Documented, enforced precedence:** built-in defaults < config file <
  environment (`UO_DNS_SERVERS`) < explicit CLI flags (`-y`, `--dry-run`,
  `--no-color`, `--no-log`). Explicit flags win exactly as they always have —
  the config only fills the gaps.
- **New flags:** `--config FILE` (use an alternative config for one run —
  missing files rejected), `--no-config` (ignore every config for this run),
  `--config-show` (print the effective configuration with the source of every
  value: default / config / env / cli), `--config-example` (print an annotated,
  fully-commented template — redirecting it onto an existing file cannot change
  behavior until edited).
- Functional guarantees covered by tests: `NO_LOG=1` from the config really
  suppresses logging; `ASSUME_YES=1` really auto-confirms; quoted DNS values
  are unquoted; the `UO_DNS_SERVERS` environment variable keeps winning.
- Both completions (bash + zsh) learn the four new flags — `--config` offers
  file completion; 19 new bats tests (`test/config.bats`, fully offline,
  running the real CLI in an isolated temp HOME) — 123 total.

## [7.7.0]

### Added
- **Report-to-file output: `uo --report --output FILE`** — the report (plain
  text or JSON) can now be written straight into a file instead of stdout,
  with writability checked up front (`Cannot write to file` before anything
  runs — an unwritable path never truncates or creates a partial file).
- **JSONL time-series logging: `uo --report --json --append --output FILE`** —
  append mode turns repeated runs into a self-describing JSON Lines log: one
  complete report document (each with its own `generated_at` timestamp) per
  line, ready for `cron` jobs and dashboard tailing:

  ```bash
  # /etc/cron.d or crontab — a health snapshot every 15 minutes
  */15 * * * * uo --report --json --append --output ~/.local/share/ubuntu-optimizer/report-log.jsonl
  ```

- Append never truncates (existing content — even non-report lines — is
  preserved), while the default overwrite mode keeps snapshot files clean
  (two runs → exactly one document). The file path is confirmed with
  `Report saved to: …` on stdout in text mode and on stderr in JSON mode, so
  piped JSON streams stay pure.
- Validation mirrors the existing flag style: `--output` only together with
  `--report`, `--append` only together with `--output`; both completions
  (bash + zsh) learn the new flags, `--output` offers file completion.
- 9 new bats tests (`test/reportfile.bats`, fully offline, running the real
  CLI in an isolated temp tree): all validation rejections, valid-JSON +
  pure-stdout guarantees, truncate vs append semantics, per-line JSONL
  validity and monotonic `generated_at` ordering — 104 total.

## [7.6.0]

### Added
- **`uo --self-update` — the toolkit updates itself** (new `lib/selfupdate.sh`
  module): a version check against the official repository
  (`raw.githubusercontent.com`, default branch detected automatically — `main`
  first, then `master`) followed by one of two update strategies, chosen by how
  the tool was installed:
  - **git checkout** (a `.git` directory beside the script): a dirty working
    tree is warned about and confirmed first, then `git pull --ff-only` — a
    diverged checkout fails safely with precise manual fix/rollback commands
    instead of force-overwriting anything.
  - **static copy** (no `.git`): the branch archive tarball is downloaded,
    extracted and verified with `bash -n` on the main script and every module
    **before** anything is touched, the current files are moved into a
    timestamped backup under
    `~/.local/share/ubuntu-optimizer/selfupdate-backups/`, and the new tree is
    swapped in with atomic renames — a running bash process keeps reading its
    own inodes, so in-place writes can never corrupt an executing script. A
    failed post-update verification restores the backup automatically.
- **Safety rails on every path:** updates are accepted from the official
  repository only (not configurable), the downloaded tree must match the
  expected remote version, both update paths end with a rollback hint, and
  `--dry-run` prints the exact plan (installation kind, remote version, method)
  while touching nothing.
- Installed **bash and zsh completions are refreshed automatically** after a
  successful update; a note reminds that running sessions keep the old code in
  memory until the next `uo` run.
- **zsh completion** (new `completions/_uo`): full flag/value completion
  mirroring the bash one — profile names, tracked app names from both
  databases and `.tar.gz` file completion. `install.sh` copies it into
  `~/.zfunc` and appends a guarded fpath/compinit block to `~/.zshrc` (only
  when zsh is in use; duplicate-safe; removed again by `--uninstall`).
- New menu entry **"Update this toolkit itself (self-update)"** in
  Update Apps.
- 18 new bats tests (`test/selfupdate.bats`, fully offline): version
  comparison incl. the 7.10 > 7.9 numeric edge case, git-checkout detection,
  tree verification (healthy / broken main / broken module / empty lib), and
  remote-version parsing with a stubbed curl (main-branch success, master
  fallback, total failure, missing version line, stale-state reset) — 95 total.

## [7.5.0]

### Added
- **Machine-readable JSON report: `uo --report --json`** (new
  `lib/jsonreport.sh` module): the read-only system status report is now also
  emitted as a single valid JSON document — built with pure Bash parameter
  expansion, no jq/python dependency on the machine that produces it.
- The document mirrors the plain-text report one-to-one (host, memory, disks,
  failed services, optimization status, network, top memory consumers, last
  logged events) but in automation-friendly form: sizes in raw bytes, real
  JSON booleans, `null` for unavailable values, load averages as numbers and
  a compact top-level `summary` block with a `good` / `attention` / `critical`
  health verdict, optimization score, RAM/swap percentages and disk warnings.
- **Strict purity guarantees:** the CLI banner, the closing summary and every
  human-only line are suppressed in JSON mode, colors are force-disabled and
  the exit code still reports failure to scripts (`0` ok / `1` errors) —
  the stream can be piped straight into `jq`, cron mail or a dashboard.
- `--json` is strictly validated: only valid together with `--report`; any
  other combination is rejected with a clear error instead of emitting a
  corrupt document.
- Strings are escaped by a dedicated `_json_escape` helper (quotes,
  backslashes, newlines, control characters) and all numeric fields pass
  through sanitizer helpers, so a tool changing its output format can never
  inject invalid JSON.
- 13 new bats tests (`test/jsonreport.bats`, fully offline): JSON validity
  against python3/jq, required keys, status verdict, version echo, counter
  consistency and the escape/sanitizer helpers — 77 total.

## [7.4.0]

### Added
- **SHA-256 checksum verification for GitHub Releases installs** (new
  `gh_verify_checksum` and helpers in `lib/github.sh`): when a release ships
  a checksum file — `checksums.txt`, goreleaser's `<project>_checksums.txt`,
  `SHA256SUMS`, `<file>.sha256` / `.sha256sum` / `.sha256sum.txt` or
  `<file>.dgst` — the downloaded asset is verified against it before
  anything is installed. Three checksum-file formats are parsed
  (`sha256sum -c` lists, OpenSSL `.dgst` output and bare single-hash files).
- A **checksum mismatch aborts the install** and deletes the download — a
  tampered or truncated asset can never reach the system through
  `--github-install` or the update flow (both go through the same verified
  download path).
- Verification is graceful by design: releases without any checksum file, or
  with a checksum file that does not list the picked asset (multi-platform
  releases), install as before with an explanatory message. A bare-hash
  fallback can never pick another file's hash from a name-based list.
- `UO_SKIP_CHECKSUM=1` escape hatch for broken upstream releases (prints a
  warning; the check stays on by default).
- 13 new bats tests (`test/github.bats`) covering checksum-asset detection,
  all three hash-file formats, multi-file lists, malformed hashes and the
  no-entry regression — 64 total.

## [7.3.0]

### Added
- `uo --profile laptop|server|gaming|minimal` (new `lib/profile.sh` module and
  main-menu entry 5 "Optimization profiles"): curated presets that run a safe,
  scenario-specific subset of the existing optimizer steps.
  - `laptop` — memory, noatime, TLP, BBR/TCP, Wi-Fi power management off,
    journal cap (no preload).
  - `server` — memory, noatime, journal cap, BBR/TCP, unneeded services off
    (no TLP, no Wi-Fi steps, no preload).
  - `gaming` — memory, BBR/TCP, Wi-Fi power management off, journal cap
    (no fstab edit, no services, installs nothing).
  - `minimal` — memory, journal cap, unneeded services off (installs nothing).
- `profile_steps()` is the single source of truth for profile composition;
  the intent and the numbered plan are printed and confirmed before anything
  runs, `--dry-run` is fully supported, and every step reuses the battle-tested
  optimizer functions (including their own confirmations and warnings).
  Profiles are reversible with `uo --undo`.
- 7 new bats tests (`test/profile.bats`) pinning name validation and the exact
  composition of every profile — 51 total.

### Changed
- `install.sh` module check and bash completion cover `--profile` (with value
  completion for the four profile names).

## [7.2.0]

### Added
- `uo --undo` (new `lib/undo.sh` module, also in the recovery menu): reverses
  every optimization the tool applied in one command. The plan is detected
  read-only first and shown before anything runs — confirmation by default
  (`-y` auto-confirms), full `--dry-run` support. The undo covers: the sysctl
  drop-in (removed, defaults reloaded with `sysctl --system`), the journald
  cap, the sudo timeout file, the polkit rule, `/etc/fstab` (restored from
  the automatic backup only when it matches the expected noatime edit, so
  later manual edits are never lost), the disabled services
  (cups-browsed/whoopsie/avahi-daemon are re-enabled with `--now`) and the
  NetworkManager overrides (DNS back to automatic, Wi-Fi power management
  back to the connection default — with the same SSH warning as the
  optimizers). Packages installed along the way (preload, tlp, chrony) are
  deliberately **left in place** and only reported with a removal hint.
- 6 new bats tests (`test/undo.bats`) for the undo function surface and the
  fstab root-line detector that guards the backup restore — 44 total.

### Changed
- `install.sh` module check now covers `lib/undo.sh` (`REQUIRED_MODULES`).
- bash completion lists `--undo`.

## [7.1.0]

### Added
- `UO_DNS_SERVERS` environment variable: the network optimization
  (`--network` / `--optimize`) and the generated fixnet script's fallback
  `resolv.conf` can now use custom DNS servers (space-separated IPv4).
  The default stays `8.8.8.8 1.1.1.1`; an invalid value is refused before
  nmcli runs. Documented in `--help` and both READMEs.
- `_ver_gt()` version-comparison helper (`sort -V` based) in `lib/common.sh`.
- Free-disk-space guard before installs: `disk_check_install` (previously
  dead code) now runs inside `targz_install_from_file` and
  `appimage_install_from_file`, requiring 500 MB free before anything is
  extracted or copied.

### Fixed
- tar.gz updates could **downgrade** an app: any archive in `~/Downloads`
  with a *different* version was offered/installed as an update. The update
  scan now only offers strictly **newer** archives (`_ver_gt`); older ones
  are listed as "(older — kept)" and skipped in `-y` mode.
- `disk_cleanup` reported success unconditionally: `apt clean`,
  crash-report removal and `apt autoremove` now report a warning when they
  actually fail.
- AppImage SVG icons were copied as `<name>.png` and the icons directory
  was not guaranteed to exist — the real extension is kept (`.svg`/`.png`)
  and `/usr/local/share/icons` is created on demand.
- `install.sh` wrote a double-quoted alias that broke when the project
  folder path contained spaces; the alias is single-quoted now and
  uninstall removes both forms.
- `set_sysctl` did not escape the `|` sed delimiter in replacement values.
- Scary "the network will go down" / "do not run over SSH" warnings no
  longer appear in `--dry-run` previews, where nothing actually drops.

### Changed
- Performance — `name_from_archive` is now pure Bash (was 2× sed + 1× tr +
  basename forks per call); it runs once per candidate archive in the
  Downloads update scan. Behavior is byte-identical (covered by tests).
- `targz_install_from_file` detects the archive layout with a single `find`
  pass instead of two.

## [7.0.0] - 2026-10-04

The "product" release: the project is now a complete, ready-to-publish
open-source product.

### Added
- MIT `LICENSE`.
- `CHANGELOG.md` (this file) — the release history now lives in one place.
- `CONTRIBUTING.md` — development quickstart, project rules, PR checklist.
- `SECURITY.md` — security policy and the tool's built-in safety design.
- `.gitignore` for editor/OS cruft and local artifacts.
- `.shellcheckrc` — pins the project lint configuration (disables SC2034,
  which cannot see cross-file usage in this modular sourced project).
- CI workflow `.github/workflows/lint.yml`: shellcheck + `bash -n` + bats
  unit tests on every push and pull request.
- Issue templates (bug report, feature request) and a pull request template.
- `docs/` — project logo (`logo.svg`) and a terminal-style README hero image
  (`demo.svg`, generated from a real menu capture — never drifts from the
  actual product).
- Redesigned `README.md` / `README.fa.md`: centered header with logo and
  badges, terminal hero image, quick start, full menu & CLI tables, safety
  & undo guide, collapsible FAQ, and a quality-gates section.
- Professional documentation comments across every module: uniform file
  headers plus function-level doc blocks (description, Globals, Arguments,
  Returns) — 2,691 comment lines across the 18 shell files, with the code
  lines verified byte-identical.
- Dry-run guards for the system/security flows (`--system --dry-run`):
  `install_preload`, `install_tlp`, `limit_journal`, `disable_extra_services`,
  `extend_sudo_timeout` and `setup_polkit_rule` now print honest
  `[dry-run] …` messages instead of fake success lines.
- New bats tests (`test/appmgmt.bats`): `sanitize_app_name`,
  desktop-entry path-escaping round-trip
  (`desktop_escape_path` ↔ `_desktop_exec_path`), and the GitHub db helpers
  (`gh_db_add` / `gh_db_has` / `gh_db_remove`).
- `test/syntax.bats` now also covers `completions/uo`.

### Changed
- Performance — hot helpers no longer spawn extra processes:
  - `normalize_name`: pure Bash (was two `tr` forks per call; it runs inside
    loops over every snap/flatpak/pipx//opt entry)
  - `pkg_installed`: the dpkg status string is now matched in Bash (no `grep`
    fork) — one of the most frequently called helpers
  - `deb_owner_of`: a single `awk` instead of `head`+`cut`+`awk`+`tr`
    (5 → 2 processes per call, identical output for single/multiple owners
    and architecture-qualified names)
  - `guess_version`, `derive_install_root`, `sanitize_app_name`: pure Bash
    parameter expansion (no `tr`/`basename`/`dirname` forks)
- `appimage_install_from_file` no longer leaks the `APP_NAME` global.

### Fixed
- Dry-run BBR preview false negative: in `--dry-run` the module is not
  actually loaded (the sudo wrapper only prints the command), so the
  availability check now uses read-only `modinfo` — previews no longer
  wrongly report "Your kernel does not support BBR".
- Doctor desktop-entry check when no terminal emulator is installed: an
  empty wrapper produced `grep -q ""` (matches anything), silently skipping
  the check; the fallback to `Terminal=true` is now explicit.
- Documentation sync: README (EN/FA) said 6.0 while `SCRIPT_VERSION` was 6.1;
  everything is now 7.0.
- README structure was missing `lib/doctor.sh` and `lib/disk.sh`; the CLI
  table was missing `--doctor`, `--disk` and `--disk-clean`.
- Removed the false "All-ASCII terminal output" claim (the banner uses
  box-drawing characters and the menus use emoji).

### Removed
- Leftover scratch files: `t.txt`, `project_dump.md`.

## [6.1.0]

- App health check & repair: `--doctor` (files, binary format, permissions,
  symlinks, desktop entries with terminal wrappers, shared-library deps).
- Disk space analysis and cleanup: `--disk` / `--disk-clean`.
- bash-completion value hints for `--cleanup` and `--github-remove`.

## [6.0.0]

- International release: English-first messages, comments and logs; Persian
  documentation kept in README.fa.md; fixnet stays bilingual (EN/FA).
- ShellCheck-clean codebase + CI workflow.
- `GH_TOKEN` / `GITHUB_TOKEN` support (60 → 5000 API requests/hour).
- Major fixes: Wi-Fi power management actually applied, `/opt` removal
  guard, base-directory protection in user-data cleanup, infinite-loop fixes
  (Ctrl+D, `-y`), emergency NTP sync, noatime false positives, orphan
  desktop-file false deletions.
- Security: polkit rule limited to local active sessions; GitHub downloads
  through a secure mktemp directory; freedesktop-compliant Exec escaping.
- Performance: fork-free logging, single `systemctl` call in service
  scanning, TCP fastopen + 16MB buffers, signal exit codes (130/143).
