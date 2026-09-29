# 🐧 Ubuntu Optimizer & Fixer

An all-in-one Ubuntu optimization, app management and repair toolkit.

**Author & Designer:** Soroush Chegini ([CheginiSoroush](https://github.com/CheginiSoroush))

**Version:** 6.0 | **Architecture:** modular Bash | **Requires:** Ubuntu 20.04+ and Bash 4.3+

> 📖 [Persian documentation (مستندات فارسی)](README.fa.md)
>
> **Optional:** `jq` — faster GitHub API parsing (everything works without it).
> **Optional:** `GH_TOKEN` — GitHub API token, raises the rate limit from 60/hour to 5000/hour ([details](#optional-github-api-token)).

---

## ✨ Features

| Area | Capabilities |
|---|---|
| 🌐 Network | BBR, DNS, MTU, full TCP tuning (fastopen, buffers), Wi-Fi power management off |
| 💾 System | swappiness & vfs_cache_pressure, noatime (applied immediately via remount), preload & tlp, journal size limit |
| 🔐 Security | extended sudo timeout, polkit rule (optional — local sessions only) |
| 🕐 Time | chrony sync with an independent emergency fallback |
| 🛠 fixnet | standalone bilingual script that repairs connectivity after a VPN disconnect — restores resolv.conf and waits for the network to return |
| 📊 Tests | ping, DNS, internet speed, full network info |
| 📦 Install | deb packages, **smart tar.gz/tgz install** (main-executable detection + architecture check + automatic dependencies) |
| 🐙 GitHub | install / update / remove apps from GitHub Releases — automatic architecture-aware asset pick |
| 🧹 Removal | **fully remove any app from any source** (apt/snap/flatpak/tar.gz/manual) + user data |
| 🔄 Updates | apt + snap + flatpak + tar.gz (Downloads scan or URL) + GitHub — fully automatic with `-y` |
| 🧩 snap/flatpak | list, install, remove, clean old revisions & unused runtimes |
| 🚑 Recovery | fix broken packages, reinstall the desktop environment |
| 📜 Logging | every action logged + a summary at the end of each run |
| 📊 Report | read-only system status & optimization report |

---

## 🆕 What's new in 6.0

**International release**
- English-first codebase: every message, comment and log line is now English
- Persian documentation lives on in [README.fa.md](README.fa.md)
- The generated fixnet script keeps its bilingual (EN/FA) runtime messages
- All-ASCII terminal output — banner and tables align perfectly everywhere

**Reliability**
- Wi-Fi power management never actually applied before (nmcli connection-type mismatch) — fixed
- Guard against dangerous `/opt` removal with invalid app names
- User-data cleanup never offers base directories (`~/.config`, …)
- Infinite loops fixed: menu on Ctrl+D, `-y` in tar.gz updates and the SSH wizard
- Emergency NTP sync (incomplete chronyd directive) — fixed
- noatime false-positives fixed; now applied immediately via remount
- Orphan desktop-file false deletions on escaped paths — fixed
- `-y` mode is truly non-interactive (dpkg conffile prompts included)

**Security**
- polkit rule restricted to local active sessions (SSH sessions not covered)
- GitHub downloads go through a secure mktemp directory (symlink-safe)
- freedesktop-compliant `Exec` escaping in .desktop files

**Quality & performance**
- ShellCheck clean: zero findings across the whole project + CI workflow included
- Fork-free logging; single `systemctl` call in service scanning; deterministic finds
- TCP fastopen + 16MB buffers; fixnet waits for the default route after an NM restart
- Signal exit codes (130/143); `install.sh --check` is CI/script-friendly
- Resilient module loader: a broken module aborts immediately with a clear message

---

## 🚀 Installation

```bash
# 1. Put the project folder in your home directory
mv ubuntu-optimizer ~/.   # recommended path: ~/ubuntu-optimizer

# 2. Run the installer
cd ~/ubuntu-optimizer
./install.sh
```

The installer:
- checks the syntax of every file with `bash -n` (and reads the version from a single source)
- creates the `uo` shortcut in `~/.local/bin` and adds it to PATH
- adds a `uo` alias to `~/.bashrc` (and `~/.zshrc` if present)

Then run `source ~/.bashrc` once (or open a new terminal):

```bash
uo              # interactive menu
uo --report     # system status report
uo --help       # full help
```

> ⚠️ Run the script **without sudo** — it asks for the sudo password itself when needed.

### Managing the installation

```bash
./install.sh --check       # file health & install status (CI-friendly exit code)
./install.sh --update      # update from git (if a git repository)
./install.sh --uninstall   # remove shortcut and alias (project files stay)
```

### Optional: GitHub API token

`--github-update` and `--github-install` query the GitHub API, which is
rate-limited to **60 requests/hour per IP** — a limit shared with everyone
behind your ISP's NAT. Set a personal token to raise it to **5,000/hour**:

1. Create a classic read-only token: github.com → Settings → Developer
   settings → Personal access tokens → *Generate new token (classic)* —
   **no scopes needed** for public repositories.
2. Add it to your shell:

```bash
echo 'export GH_TOKEN="ghp_your_token"' >> ~/.bashrc
source ~/.bashrc
```

Both `GH_TOKEN` and `GITHUB_TOKEN` are supported. The token is only sent
to `api.github.com` and is never written to the log.

---

## ⌨️ CLI (non-interactive)

| Command | Action |
|---|---|
| `uo --report` | system status report (read-only) |
| `uo --github-install OWNER/REPO [NAME]` | install an app from the latest GitHub release |
| `uo --install-targz FILE [NAME]` | install an app from a .tar.gz file (name optional — auto-detected) |
| `uo --github-update` | check & install updates for GitHub apps |
| `uo --github-list` | list tracked GitHub apps |
| `uo --github-remove NAME` | fully remove a GitHub app + its tracking entry |
| `uo --git-ssh` | GitHub SSH key setup wizard (passwordless) |
| `uo --git-ssh-status` | SSH key / GitHub authentication status |
| `uo --optimize` | all network + system optimizations |
| `uo --network` | network optimizations (BBR, DNS, MTU, TCP) |
| `uo --system` | system & memory optimizations |
| `uo --security` | sudo timeout + polkit settings |
| `uo --time` | sync system time |
| `uo --fixnet` / `--fixnet-run` | create / run the fixnet script |
| `uo --test` | network tests (ping, DNS, speed) |
| `uo --update` | update all sources |
| `uo --update-apt / --update-snap / --update-flatpak / --update-targz` | update a single source |
| `uo --list-apps` | list all apps from all sources |
| `uo --cleanup NAME --purge-data` | fully remove an app + user data |
| `uo --snap-clean` | clean old snap revisions + unused flatpaks |
| `uo --log` / `--log-clear` | show / delete the log |
| `uo -y` | auto-confirm all questions — fully non-interactive |
| `uo --dry-run` | with --optimize/--network/--system/--security/--time: preview changes without applying |
| `uo --no-log` | do not log this run |
| `uo --no-color` | disable colors (automatic in pipes) |

### Real-world examples

```bash
uo --optimize                                   # after a fresh Ubuntu install
uo --update -y                                  # update everything, no questions
uo --install-targz ~/Downloads/app.tar.gz myapp # install from an archive
uo --github-install junegunn/fzf                # install from GitHub
uo --cleanup abdownloadmanager --purge-data -y  # fully remove an app
uo --report                                     # health check
```

---

## 🧠 How smart install/removal works

### tar.gz install (`uo` → option 7 → 4)

1. The archive is extracted and the **main executable** is detected (priority: AppImage → name match → single candidate → manual choice) — Electron/JVM helper tools (`chrome_crashpad_handler`, `jspawnhelper`, …) are skipped
2. The **package architecture** is checked against the system — wrong downloads (e.g. arm64 on x86_64) are detected before install
3. **Missing dependencies** are found with `ldd` and installed automatically
4. The app is installed to `/opt/<name>` with a terminal shortcut and a desktop file (spec-compliant escaping)
5. It is registered in the **registry** (for clean removal & update tracking)

### Full removal (`--cleanup NAME`)

All sources are searched: registry, apt (exact and fuzzy), snap, flatpak, `/opt` directories, desktop files. `/opt` directories owned by deb packages (like Obsidian) are detected so removal goes through the **right path** (apt).

### tar.gz updates

`~/Downloads` is scanned for a new version, or you provide a path/URL — with `-y` it is fully automatic.

---

## 📁 Project structure

```
ubuntu-optimizer/
├── ubuntu-optimizer.sh   ← main file (CLI + menu) — only this is executed
├── install.sh            ← install/update/uninstall of the project itself
├── README.md / README.fa.md
├── .shellcheckrc         ← project lint configuration
├── .github/workflows/lint.yml  ← CI: shellcheck + syntax on every commit
├── completions/uo          ← bash completion for the uo command
├── test/common.bats        ← bats unit tests for lib/common.sh
└── lib/
    ├── common.sh         ← colors, helpers, registry, logging system
    ├── network.sh        ← network optimization and tests
    ├── system.sh         ← system, memory, security, time
    ├── fixnet.sh         ← creates and runs the bilingual fixnet script
    ├── packages.sh       ← deb and tool installation
    ├── targz.sh          ← smart tar.gz installer
    ├── github.sh         ← install/updates from GitHub Releases
    ├── appmgmt.sh        ← full app removal from all sources
    ├── snapflatpak.sh    ← snap/flatpak + updates
    ├── recovery.sh       ← system recovery + advanced tools
    ├── report.sh         ← system status report
    ├── gitssh.sh         ← GitHub SSH setup
    └── menus.sh          ← menu engine and all menus
```

> Never execute the `lib/` files directly — always go through `ubuntu-optimizer.sh` (or `uo`).

### For developers

- **Add a menu option:** define a function in the relevant module and add one line to `menu_loop` in `lib/menus.sh`: `"Title|function_name"`
- The menu only runs defined functions (`declare -F` guard) — a forgotten function is reported with a clear message
- **Add a CLI option:** add one line to the argument loop in the main script
- **The version lives in one place:** `SCRIPT_VERSION` in `lib/common.sh`
- **Always check file health:** `bash -n lib/<file>.sh` — no output means healthy

---

## 📍 Files and paths created/modified

| Path | Purpose |
|---|---|
| `/etc/sysctl.d/99-ubuntu-optimizer.conf` | kernel parameters (BBR, swappiness, …) |
| `/etc/systemd/journald.conf.d/99-optimizer.conf` | system journal size limit |
| `/etc/sudoers.d/99-optimizer-timeout` | sudo timeout (120 minutes) |
| `/etc/polkit-1/rules.d/10-disable-password-timeout.rules` | polkit rule (only with user consent) |
| `/opt/<name>` | install location for tar.gz apps |
| `~/.local/share/ubuntu-optimizer/apps.db` | tar.gz app registry |
| `~/.local/share/ubuntu-optimizer/github.db` | GitHub app database |
| `~/.local/state/ubuntu-optimizer/optimizer.log` | activity log |
| `~/fix-network.sh` | fixnet script + `fixnet` shell alias |
| `~/.local/bin/uo` | run shortcut |

Backup created: `/etc/fstab.bak` (before adding noatime)

---

## 🔒 Security & safety notes

- The script runs as a regular user; sudo is requested only for the operations that need it
- sudoers edits go through a separate file validated with `visudo -c -f` — removed automatically on error
- The polkit rule (if enabled) covers **local active sessions only** — SSH/remote sessions are not covered
- GitHub release downloads go through a secure temporary directory (mktemp)
- App names are sanitized before every operation — sensitive paths (`/`, `/opt`, `$HOME`, …) are blocked from removal
- Destructive operations (app removal, polkit, VEET) always ask for confirmation (unless `-y`)
- `set_dns` and Wi-Fi power management restart the connection — be careful over SSH
- The status report (`--report`) is completely read-only

---

## ⚠️ Disclaimer

This tool changes system settings. All known bugs have been carefully fixed, but the final responsibility for its use is yours:
- The "advanced tools" section (like VEET) is separated with explicit warnings
- To fully undo the settings: delete the files in the table above and reboot

---

## 🗺 Roadmap

- [x] GitHub Actions: shellcheck + `bash -n` on every commit
- [x] GitHub API token support (`GH_TOKEN` / `GITHUB_TOKEN`)
- [x] bash completion for CLI options
- [x] automated tests (bats) for `lib/common.sh`
- [x] `--dry-run` mode

---

## ✅ Final project test

```bash
uo --report          # status & optimization report
uo --list-apps       # apps from all sources
uo --test            # network tests
uo --log             # activity log
uo                   # full menu — take a tour!
```
