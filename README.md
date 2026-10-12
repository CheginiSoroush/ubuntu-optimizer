<div align="center">
  <a href="https://github.com/CheginiSoroush/ubuntu-optimizer">
    <img src="docs/logo.svg" width="130" alt="Ubuntu Optimizer &amp; Fixer logo" />
  </a>

# Ubuntu Optimizer &amp; Fixer

**One command. A faster, cleaner, healthier Ubuntu.**

The all-in-one optimization, app-management and repair toolkit —
17 friendly menu tools, 35+ CLI options, honest dry-run previews.

[![CI](https://github.com/CheginiSoroush/ubuntu-optimizer/actions/workflows/lint.yml/badge.svg)](https://github.com/CheginiSoroush/ubuntu-optimizer/actions/workflows/lint.yml)
[![Website](https://img.shields.io/website?url=https%3A%2F%2Fcheginisoroush.github.io%2Fubuntu-optimizer&logo=github&label=website)](https://cheginisoroush.github.io/ubuntu-optimizer/)
[![Version](https://img.shields.io/badge/version-v7.8-E95420?logo=ubuntu)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-007EC6)](LICENSE)
![ShellCheck](https://img.shields.io/badge/ShellCheck-clean-brightgreen)
![Tests](https://img.shields.io/badge/bats-123%20%2F%20123-brightgreen)
![Bash](https://img.shields.io/badge/made%20with-Bash-4EAA25?logo=gnubash&logoColor=white)

[English](README.md) · [فارسی](README.fa.md)

</div>

<p align="center">
  <img src="docs/demo.svg" alt="The uo interactive menu" width="620" />
</p>

---

## ✨ What you get

| Area | Capabilities |
|---|---|
| 🌐 **Network** | BBR congestion control · fast DNS (8.8.8.8 / 1.1.1.1) · MTU auto-tuning · full TCP tuning (fastopen, 16 MB buffers) · Wi-Fi power-saving off |
| 💾 **System &amp; memory** | swappiness &amp; vfs_cache_pressure · noatime (applied instantly via remount) · preload · TLP · journal size limit |
| 🔐 **Security** | extended sudo timeout · opt-in polkit rule (local sessions only, clearly warned) |
| 🕐 **Time** | chrony sync with an independent emergency fallback |
| 🛠 **fixnet** | standalone bilingual script that repairs connectivity after a VPN disconnect — restores resolv.conf and *waits* for the network to come back |
| 💿 **Disk** | usage analysis by category + one-command cleanup (apt cache, journal, old kernels, snap revisions, crash reports) |
| 📊 **Diagnostics** | ping, DNS, internet-speed tests · read-only system status report · **machine-readable JSON** (`--report --json`, v7.5) for cron & dashboards · **JSONL time-series log** (`--report --json --append --output`, v7.7) |
| ⚙ **Config file** | `~/.config/uo/config.conf` — persist ASSUME_YES / NO_COLOR / NO_LOG / DRY_RUN / DNS_SERVERS for cron & shared machines; never sourced, never eval'd — every line is parsed and validated (v7.8) |
| 📦 **Install** | deb packages · **smart tar.gz/tgz install** (main-executable detection, architecture check, automatic dependencies) · AppImage |
| 🐙 **GitHub Releases** | install / update / remove apps — automatic architecture-aware asset pick · **SHA-256 checksum verification** when the release ships one (v7.4) |
| ⬆ **Self-update** | `uo --self-update` — the toolkit updates itself: version check against the official repo, git pull for clones, verified archive + automatic backup for static copies (v7.6) |
| 🧹 **Full removal** | completely remove any app from **any source** (apt / snap / flatpak / tar.gz / manual) — including user data |
| 🔄 **Updates** | apt + snap + flatpak + tar.gz + GitHub in one command, fully automatic with `-y` |
| 🚑 **Recovery** | fix broken packages, reinstall the desktop environment |
| 📜 **Logging** | every action logged, with a clear end-of-run summary |

> 💡 Never memorized a flag in your life? Just run `uo` and pick from the menu.
> Live in the terminal? Every feature is a flag away — `uo --help`.

---

## ⚡ Quick start

```bash
git clone https://github.com/CheginiSoroush/ubuntu-optimizer.git
cd ubuntu-optimizer
./install.sh          # health-check + `uo` command + PATH + bash completion
source ~/.bashrc      # once — new terminals pick it up automatically
```

```bash
uo                    # interactive menu
uo --report           # read-only system report
uo --report --json | jq '.summary'   # same report, machine-readable (v7.5)
uo --report --json --append --output ~/.local/share/ubuntu-optimizer/report-log.jsonl
                      # one JSON line per run → a time-series log for dashboards (v7.7)
uo --config-show      # inspect the effective configuration (v7.8)
uo --self-update      # keep the toolkit itself on the latest version (v7.6)
uo --optimize --dry-run -y   # preview everything before changing anything
```

**Requirements:** Ubuntu 20.04+ (other Debian-family distros work too) · Bash 4.3+ · `sudo`.
**Optional:** `jq` (faster GitHub API parsing — works fine without it) · [`GH_TOKEN`](#-optional-github-api-token).

> ⚠️ Run `uo` **without sudo** — it asks for the sudo password itself, only when an operation actually needs it.

<details>
<summary><b>📦 Managing the installation</b> (update / uninstall / health check)</summary>

```bash
./install.sh --check       # file health & install status (CI-friendly exit code)
./install.sh --update      # update from git (if a git repository)
./install.sh --uninstall   # remove shortcut, alias, completion — project files stay
```
</details>

---

## ⚡ Profiles — one flag for the whole scenario

Instead of memorizing steps, pick the situation you are in — the profile runs
a safe, curated subset of the optimizer (plan shown first, reversible with
`uo --undo`):

| Profile | Runs | Deliberately skips |
|---|---|---|
| `laptop` | memory · noatime · TLP · BBR/TCP · Wi-Fi powersave off · journal cap | preload |
| `server` | memory · noatime · journal cap · BBR/TCP · unneeded services off | TLP, Wi-Fi steps, preload |
| `gaming` | memory · BBR/TCP · Wi-Fi powersave off · journal cap | noatime, services, installs |
| `minimal` | memory · journal cap · unneeded services off | everything else — installs nothing |

```bash
uo --profile laptop --dry-run -y   # preview the exact plan first
uo --profile server -y             # apply it hands-free
```

---

## 🌐 Website — live on GitHub Pages

The project ships with a bilingual landing page (فارسی / English) — RTL/LTR aware,
light & dark themes, animated terminal demo — built with Next.js 16 + Tailwind CSS 4
and hosted **for free on GitHub Pages**:

> **🔗 https://cheginisoroush.github.io/ubuntu-optimizer/**

- Source lives in [`website/`](website); every push that touches it is built and
  published automatically by [`.github/workflows/website.yml`](.github/workflows/website.yml)
- One-time setup after creating the repo: **Settings → Pages → Source → GitHub Actions**
- No server, no database, no cost — a pure static export (`output: 'export'`)

Local development & manual builds: [`website/README.md`](website/README.md).

---

## 🖥 The menu — 17 tools, zero memorization

| # | Tool | What it does |
|:--:|---|---|
| 1 | 🌐 Network optimization | BBR, DNS, MTU, TCP tuning, Wi-Fi power management |
| 2 | 💾 System &amp; memory optimization | swappiness, noatime, preload, TLP, journal limit |
| 3 | 🔐 Security &amp; passwords | sudo timeout + polkit settings |
| 4 | 🕐 Time &amp; NTP | sync the system clock |
| 5 | ⚡ Optimization profiles | curated presets: laptop · server · gaming · minimal |
| 6 | 🛠 Create &amp; run fixnet | build the standalone network-repair script |
| 7 | 📊 Network &amp; speed tests | ping, DNS, speed, full network info |
| 8 | 📦 Install packages &amp; apps | deb · tar.gz · GitHub Releases · AppImage |
| 9 | 🧹 Manage &amp; fully remove apps | any app, from any source, incl. user data |
| 10 | 🔄 Update apps | all sources in one go |
| 11 | 🧩 snap &amp; flatpak management | list, install, remove, clean revisions |
| 12 | 🚑 System recovery &amp; rescue | broken packages, desktop reinstall, `--undo` |
| 13 | ☠ Advanced tools *(dangerous)* | clearly separated, explicit warnings |
| 14 | 📜 Activity log | what happened, when |
| 15 | 📊 System status report | read-only health &amp; optimization snapshot |
| 16 | 📊 Disk space analysis | where your gigabytes went |
| 17 | 🧹 Disk cleanup | reclaim them |

---

## ⌨ CLI mode — for scripts and terminal people

| Command | Action |
|---|---|
| `uo --optimize` | all network + system optimizations |
| `uo --network` / `--system` / `--security` / `--time` | just one area |
| `uo --undo` | **reverse everything** the optimizer changed — one command |
| `uo --profile laptop\|server\|gaming\|minimal` | apply a curated preset for the scenario |
| `uo --dry-run` | **preview** commands without executing (with the six above) |
| `uo --self-update` | update the toolkit itself — git pull or verified archive, with backup & rollback (v7.6) |
| `uo --report` · `--report --json` · `--disk` | status report · JSON report for automation · disk analysis · cleanup |
| `uo --report --json --output FILE [--append]` | write the report into a file — `--append` builds a JSONL time-series log for dashboards (v7.7) |
| `uo --doctor` | health check &amp; repair of all installed/tracked apps |
| `uo --github-install OWNER/REPO [NAME]` | install an app from the latest GitHub release |
| `uo --github-update` · `--github-list` · `--github-remove` | update · list · remove GitHub apps |
| `uo --install-targz FILE [NAME]` | smart install from a .tar.gz (name auto-detected) |
| `uo --cleanup NAME` (`--purge-data`) | fully remove an app — any source |
| `uo --update` · `--update-apt/snap/flatpak/targz` | update everything or one source |
| `uo --list-apps` · `--snap-clean` | inventory apps · clean old snap revisions |
| `uo --fixnet` · `--fixnet-run` · `--test` | create · run fixnet · network tests |
| `uo --git-ssh` · `--git-ssh-status` | GitHub SSH key wizard · status |
| `uo --log` · `--log-clear` | show · delete the activity log |
| `uo --config-show` · `--config-example` | inspect the effective config · print an annotated template (v7.8) |
| `uo --config FILE` · `--no-config` | use an alternative config file · ignore configs for one run (v7.8) |
| `uo -y` · `--no-color` · `--no-log` | auto-confirm · plain output · don't log |

### Real-world examples

```bash
uo --optimize                                    # after a fresh Ubuntu install
uo --optimize --dry-run -y                       # paranoid? preview every command first
uo --update -y                                   # update everything, no questions asked
uo --install-targz ~/Downloads/app.tar.gz myapp  # install from an archive
uo --github-install junegunn/fzf                 # install from a GitHub release
uo --cleanup abdownloadmanager --purge-data -y   # remove an app without a trace
uo --doctor                                      # health check & repair of your apps
```

---

## 🧠 Why it feels smart

<details open>
<summary><b>Smart tar.gz install</b> — click to see the flow</summary>

1. The archive is extracted and the **main executable is detected** (priority: AppImage → name match → single candidate → manual choice) — Electron/JVM helper binaries (`chrome_crashpad_handler`, `jspawnhelper`, …) are automatically skipped
2. The **package architecture is checked** against your system — wrong downloads (e.g. arm64 on x86_64) are caught *before* install
3. **Missing dependencies** are discovered with `ldd` and installed automatically
4. The app lands in `/opt/<name>` with a terminal shortcut and a spec-compliant `.desktop` file
5. It is registered in the **registry** — so updates find it, and removal cleans up every trace

</details>

<details>
<summary><b>Full removal</b> — every source, every trace</summary>

All sources are searched: registry, apt (exact and fuzzy), snap, flatpak, `/opt` directories, desktop files. `/opt` directories owned by a deb package (like Obsidian) are detected, so removal goes through the **right path** (apt). With `--purge-data`, user config/data directories are removed too — base directories like `~/.config` are never offered.

</details>

<details>
<summary><b>Doctor</b> — a health check for everything this tool installed</summary>

`uo --doctor` verifies every tracked app: files exist, binary format and permissions are right, symlinks resolve, the desktop entry is correct (including the terminal wrapper), dependencies still load — and offers to repair what it can.

</details>

---

## 🛡 Safety first

This tool changes system settings — so it is built to be **reversible and honest**:

- 🔍 **Dry-run previews** — `uo --optimize --dry-run` prints *every command* it would run. What you preview is exactly what happens.
- 💾 **Automatic backups** — `/etc/fstab.bak` is created before the noatime edit; sudoers edits go through a separate file validated with `visudo -c -f` and are removed automatically on error.
- ⚠️ **Warnings before risky changes** — disabling avahi-daemon breaks mDNS printing; the polkit rule lowers security; DNS changes drop the connection (**don't run over SSH**) — all stated up front.
- 🧹 **Sanitized names** — app names are sanitized before every operation; sensitive paths (`/`, `/opt`, `$HOME`…) are blocked from removal.
- ✅ **Confirmation by default** — destructive operations always ask (unless `-y`).
- 📖 **Read-only mode** — `--report` and `--disk` never touch anything.

<details>
<summary><b>↩️ Undoing changes</b> — one command, or every file by hand</summary>

**The easy way — v7.2 and later:**

```bash
uo --undo                 # shows the plan, asks for confirmation, then reverses:
                          # drop-in files, fstab backup, disabled services,
                          # DNS / Wi-Fi power management overrides
uo --undo --dry-run -y    # preview the plan first
```

**The manual way (all versions):**

```bash
# Kernel/network parameters (BBR, swappiness, TCP…)
sudo rm /etc/sysctl.d/99-ubuntu-optimizer.conf && sudo sysctl --system

# fstab (noatime) — restore the automatic backup
sudo cp /etc/fstab.bak /etc/fstab

# Journal size limit
sudo rm /etc/systemd/journald.conf.d/99-optimizer.conf

# sudo timeout / polkit rule
sudo rm /etc/sudoers.d/99-optimizer-timeout
sudo rm /etc/polkit-1/rules.d/10-disable-password-timeout.rules

# Re-enable the optional services
sudo systemctl enable --now cups-browsed whoopsie avahi-daemon

# Then reboot (or remount /) for the fstab change.
```

DNS and MTU are per-connection settings (NetworkManager) — change them back in your network settings, or re-run the menu option and pick different values.

</details>

### 📍 Files &amp; paths created or modified

| Path | Purpose |
|---|---|
| `/etc/sysctl.d/99-ubuntu-optimizer.conf` | kernel parameters (BBR, swappiness, …) |
| `/etc/systemd/journald.conf.d/99-optimizer.conf` | journal size limit |
| `/etc/sudoers.d/99-optimizer-timeout` | sudo timeout (120 minutes) |
| `/etc/polkit-1/rules.d/10-disable-password-timeout.rules` | polkit rule (opt-in only) |
| `/opt/<name>` | install location for tar.gz apps |
| `~/.local/share/ubuntu-optimizer/apps.db` | tar.gz app registry |
| `~/.local/share/ubuntu-optimizer/github.db` | GitHub app database |
| `~/.local/state/ubuntu-optimizer/optimizer.log` | activity log |
| `~/fix-network.sh` | fixnet script + `fixnet` shell alias |
| `~/.local/bin/uo` | run shortcut |

---

## 🐙 Optional: GitHub API token

`--github-update` and `--github-install` query the GitHub API, which is rate-limited to
**60 requests/hour per IP** — a limit shared with everyone behind your ISP's NAT.
A personal token raises it to **5,000/hour**:

1. Create a classic read-only token: github.com → Settings → Developer settings →
   Personal access tokens → *Generate new token (classic)* — **no scopes needed**.
2. Add it to your shell:

```bash
echo 'export GH_TOKEN="ghp_your_token"' >> ~/.bashrc
source ~/.bashrc
```

Both `GH_TOKEN` and `GITHUB_TOKEN` are supported. The token is only sent to
`api.github.com` and is never written to the log.

---

## 🌐 Optional: custom DNS servers

The network optimization (`--network`, `--optimize`) sets the DNS to
`8.8.8.8` and `1.1.1.1` by default. If your ISP or region handles those
resolvers poorly, pick your own:

```bash
echo 'export UO_DNS_SERVERS="1.1.1.1 9.9.9.9"' >> ~/.bashrc
source ~/.bashrc
```

- Space-separated **IPv4 addresses** only; an invalid value is refused before
  anything is changed.
- The generated `fixnet` repair script honors it too (its fallback
  `resolv.conf` branch).

---

## ⚙ Optional: config file

Repeated flags belong in a file. Create `~/.config/uo/config.conf` and every
run — interactive or cron — picks your preferences up automatically:

```bash
uo --config-example > ~/.config/uo/config.conf   # start from the annotated template
nano ~/.config/uo/config.conf
uo --config-show                                 # verify what is in effect
```

```ini
# ~/.config/uo/config.conf — a non-interactive cron machine
ASSUME_YES=1
NO_LOG=0
DRY_RUN=0
DNS_SERVERS="1.1.1.1 9.9.9.9"
```

- **Supported keys:** `ASSUME_YES`, `NO_COLOR`, `NO_LOG`, `DRY_RUN`,
  `DNS_SERVERS` — every value is validated; unknown keys and malformed lines
  are reported and skipped, never fatal.
- **Parsing is paranoid by design:** the file is never `source`d or `eval`'d —
  only `KEY=VALUE` lines are read (comments and optional quotes allowed), so a
  config file can never execute a command.
- **Precedence:** built-in defaults < config file < environment
  (`UO_DNS_SERVERS`) < explicit CLI flags (`-y`, `--dry-run`, `--no-color`,
  `--no-log`).
- **Per-run control:** `uo --config FILE` uses an alternative file,
  `--no-config` ignores every config for one run, `--config-show` prints the
  effective configuration with the source of every value.

---

## 📁 Project structure

```
ubuntu-optimizer/
├── ubuntu-optimizer.sh        ← the only file you execute (CLI + menu)
├── install.sh                 ← install / update / uninstall the tool itself
├── completions/uo             ← bash tab-completion for the uo command
├── docs/                      ← logo & README artwork (SVG)
├── lib/
│   ├── common.sh              ← colors, helpers, registry, logging
│   ├── network.sh             ← network optimization & tests
│   ├── system.sh              ← system, memory, security, time
│   ├── fixnet.sh              ← creates & runs the bilingual fixnet script
│   ├── packages.sh            ← deb & tool installation
│   ├── targz.sh               ← smart tar.gz installer + AppImage
│   ├── github.sh              ← install/updates from GitHub Releases
│   ├── appmgmt.sh             ← full app removal from all sources
│   ├── snapflatpak.sh         ← snap/flatpak management & updates
│   ├── recovery.sh            ← system recovery + advanced tools
│   ├── undo.sh                ← one-command reversal of all optimizations
│   ├── profile.sh             ← curated presets: laptop / server / gaming / minimal
│   ├── selfupdate.sh          ← `--self-update`: version check + git/archive update
│   ├── report.sh              ← system status report
│   ├── jsonreport.sh          ← the same report as one JSON document
│   ├── doctor.sh              ← app health check & repair
│   ├── disk.sh                ← disk space analysis & cleanup
│   ├── gitssh.sh              ← GitHub SSH setup
│   └── menus.sh               ← menu engine & all menus
├── test/                      ← bats unit tests (common, appmgmt, github, undo, profile, jsonreport, selfupdate, reportfile, config, syntax)
├── completions/               ← uo (bash) · _uo (zsh) — tab completion for every flag
├── .github/workflows/
│   ├── lint.yml               ← CI: shellcheck + syntax + bats on every push
│   └── website.yml            ← CI: build & publish the website to GitHub Pages
├── website/                   ← bilingual landing page (Next.js 16, fa/en) → GitHub Pages
├── README.md · README.fa.md · CHANGELOG.md · CONTRIBUTING.md · SECURITY.md · LICENSE
└── .shellcheckrc              ← project lint configuration
```

> Never execute the `lib/` files directly — always go through `ubuntu-optimizer.sh` (or `uo`).

---

## 🧪 Tested like a product

| Gate | Status |
|---|---|
| `bash -n` syntax check | ✅ all 23 shell files |
| ShellCheck (strict) | ✅ zero findings — enforced in CI |
| bats unit tests | ✅ 123 / 123 passing |
| `install.sh --check` | ✅ self-health verification built in |
| GitHub Actions CI | ✅ every push & pull request |

Run the full gate locally:

```bash
sudo apt install shellcheck bats   # one-time
bats test/
shellcheck -x ubuntu-optimizer.sh install.sh lib/*.sh
bash install.sh --check
```

---

## ❓ FAQ

<details>
<summary><b>Is it safe to run?</b></summary>

Every optimization writes to a **removable drop-in file**, not your main configs. Backups are created automatically (`fstab.bak`), sudoers edits are validated before activation, risky actions show explicit warnings and require confirmation, and `--dry-run` shows you *exactly* what would happen before anything runs. See [Safety first](#-safety-first).

</details>

<details>
<summary><b>Which distros are supported?</b></summary>

Designed and tested on Ubuntu (20.04+). Other Debian-family distributions generally work — network features need NetworkManager (`nmcli`), which is standard on desktop installs.

</details>

<details>
<summary><b>Can I undo everything?</b></summary>

Yes — see the [Undoing changes](#️-undoing-changes) box. Every file the tool creates is listed in [Files &amp; paths](#-files--paths-created-or-modified); delete them and reboot.

</details>

<details>
<summary><b>Why does it warn me about SSH?</b></summary>

The DNS and Wi-Fi power-saving steps restart your network connection. On a machine you're connected to *over* SSH, that would cut your session. The tool detects and warns before running them.

</details>

<details>
<summary><b>Does it need an internet connection?</b></summary>

Only for package installs/updates and network tests. All optimizations, reports, disk analysis and app management work offline.

</details>

<details>
<summary><b>فارسی هم دارید؟ / Do you support Persian?</b></summary>

بله! مستندات کامل به فارسی اینجاست: [README.fa.md](README.fa.md). The generated fixnet script is bilingual at runtime (English/Persian, auto-detected).

</details>

<details>
<summary><b>What's new in v7.0?</b></summary>

- MIT license + full repository infrastructure: CI, issue/PR templates, contributing &amp; security policy
- ~100× faster hot-path helpers (`normalize_name` and friends — no extra processes)
- Honest dry-run previews (no more fake `[dry-run] ✓` successes)
- New `--doctor`, `--disk`, `--disk-clean` commands · disk feature in the menu
- 6 new bats tests · ShellCheck-clean across the whole project

Full history: [CHANGELOG.md](CHANGELOG.md)

</details>

---

## 🗺 Roadmap

- [x] GitHub Actions CI (shellcheck + syntax + bats)
- [x] GitHub API token support (`GH_TOKEN` / `GITHUB_TOKEN`)
- [x] bash completion for CLI options
- [x] automated tests (bats) for `lib/common.sh`
- [x] `--dry-run` mode
- [x] 7.0: repository infrastructure (license, CI, templates, changelog)
- [ ] zsh completion
- [ ] bats coverage for every `lib/` module
- [ ] translation framework (fa / more languages)

---

## 🤝 Contribute · 🔒 Report issues

- Found a bug or have an idea? [Open an issue](https://github.com/CheginiSoroush/ubuntu-optimizer/issues) — templates are provided
- Want to hack on the tool? [CONTRIBUTING.md](CONTRIBUTING.md) has the dev setup, rules and PR checklist
- Security concerns: see [SECURITY.md](SECURITY.md) — do **not** open public issues for them
- History of every release: [CHANGELOG.md](CHANGELOG.md)

---

<div align="center">

## 👤 Author

**Soroush Chegini** · [@CheginiSoroush](https://github.com/CheginiSoroush)

<a href="https://github.com/CheginiSoroush">
  <img src="https://github.com/CheginiSoroush.png" width="90" alt="CheginiSoroush" style="border-radius:50%"/>
</a>

<br/>

If `uo` made your Ubuntu faster and cleaner, a ⭐ is the best compliment!

[![Stargazers](https://img.shields.io/github/stars/CheginiSoroush/ubuntu-optimizer?style=social)](https://github.com/CheginiSoroush/ubuntu-optimizer/stargazers)
[![Forks](https://img.shields.io/github/forks/CheginiSoroush/ubuntu-optimizer?style=social)](https://github.com/CheginiSoroush/ubuntu-optimizer/network/members)

<br/>

Made with ❤️ and pure Bash · [MIT](LICENSE) © Soroush Chegini

</div>
