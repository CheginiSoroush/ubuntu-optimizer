# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
