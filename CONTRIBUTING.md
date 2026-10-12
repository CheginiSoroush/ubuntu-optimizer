# Contributing to Ubuntu Optimizer & Fixer

Thanks for your interest in improving this project! 🐧 Contributions of any
size are welcome — bug reports, documentation fixes, new features, tests.

## Ways to contribute

- 🐛 **Report bugs** — open an issue with the *Bug report* template
- 💡 **Suggest features** — open an issue with the *Feature request* template
- 🔧 **Submit pull requests** — follow the checklist below
- 📖 **Improve docs** — README.md (EN) or README.fa.md (FA)

## Development quickstart

```bash
git clone https://github.com/CheginiSoroush/ubuntu-optimizer
cd ubuntu-optimizer

# 1. Syntax check — no output means healthy
for f in ubuntu-optimizer.sh install.sh lib/*.sh completions/uo; do bash -n "$f"; done

# 2. Lint (must be clean — the project .shellcheckrc is picked up automatically)
shellcheck -S warning ubuntu-optimizer.sh install.sh lib/*.sh completions/uo

# 3. Unit tests
bats test/
```

CI runs exactly these checks (plus bats) on every push and pull request —
see `.github/workflows/lint.yml`.

## Project rules

- **Bash 4.3+ compatibility** — no Bash-5-only features (printf `%(…)T`,
  negative array indices and `mapfile` are fine; the README documents the
  requirement).
- **English messages** — terminal output, comments and log lines are English;
  Persian documentation lives in `README.fa.md`. The generated fixnet script
  is intentionally bilingual (EN/FA).
- **Zero ShellCheck findings** at severity=warning, with the project
  `.shellcheckrc` (SC2034 is disabled because variables defined in one
  sourced module are used by others).
- **Never execute `lib/*.sh` directly** — they are sourced by
  `ubuntu-optimizer.sh` in a fixed order (`common.sh` first).
- **The version lives in one place:** `SCRIPT_VERSION` in `lib/common.sh`;
  `install.sh` reads it from there — never hardcode it elsewhere.
- **Destructive operations must ask for confirmation** (respect
  `ASSUME_YES`/`-y`) and reuse the shared helpers (`confirm_action`,
  `success`, `failure`, `info`, `warn`, `header`) so everything is logged.
- **No new hard dependencies** — optional tools (jq, pipx, …) must degrade
  gracefully when missing.

## Adding a menu option

1. Define the function in the relevant `lib/` module.
2. Add one line to the submenu in `lib/menus.sh`: `"Title|function_name"`.
3. The menu engine only runs defined functions (`declare -F` guard) — a
   forgotten function is reported with a clear message.

## Adding a CLI option

1. Add one line to the argument loop in `ubuntu-optimizer.sh`.
2. Add a row to the `usage()` help text.
3. Add a row to the CLI tables in **both** READMEs and to `completions/uo`.

## Pull request checklist

- [ ] `bash -n` passes on every changed file
- [ ] `shellcheck -S warning` reports nothing (with the project `.shellcheckrc`)
- [ ] `bats test/` passes (new tests added for new logic where practical)
- [ ] README.md **and** README.fa.md updated for user-facing changes
- [ ] CHANGELOG.md updated (under a new `[Unreleased]` heading if the
      release date is not decided yet)
- [ ] `completions/uo` updated when CLI options change

## Reporting bugs

Use the *Bug report* issue template and include:

- the exact command you ran,
- `uo -V` output (script version),
- your Ubuntu version and whether you were in an SSH session,
- relevant lines from `~/.local/state/ubuntu-optimizer/optimizer.log`.
