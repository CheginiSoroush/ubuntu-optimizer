# Security Policy

## Supported versions

Only the latest release (the `main` branch) is supported with security
fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private vulnerability reporting instead:
**github.com/CheginiSoroush/ubuntu-optimizer → Security →
"Report a vulnerability"**. Reports are acknowledged as soon as possible.

## Built-in safety design

This tool changes system settings, so safety is part of its architecture:

- The script runs as a **regular user** — running it as root is refused;
  `sudo` is requested per operation (and pre-authenticated before long
  flows, never in the middle of one).
- **sudoers** edits go through a separate drop-in file validated with
  `visudo -c -f` and removed automatically when invalid.
- The optional **polkit** rule covers local active sessions only — SSH and
  remote sessions are never covered.
- Destructive operations (app removal, polkit, dangerous tools) always ask
  for confirmation unless `-y` is explicitly given.
- App names are sanitized; protected paths (`/`, `/opt`, `$HOME`, shared
  config dirs, …) can never become removal targets.
- GitHub release downloads go through a `mktemp` directory (symlink-safe)
  and API tokens are only sent to `api.github.com` and never logged.
- The status report (`--report`) and disk analysis (`--disk`) are completely
  read-only.
