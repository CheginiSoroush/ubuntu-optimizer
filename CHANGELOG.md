# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
