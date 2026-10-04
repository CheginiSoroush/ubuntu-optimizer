# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
