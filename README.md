# 🦆 Duck Hub

Single-file, cross-platform (Windows, Linux, Debian, Kali, macOS) intranet & internet communication, unrestricted file sharing, and multi-protocol remote control hub.

**v1.6.0** — download, run, done. No install, no dependencies, no build step.

## Download

Grab the latest `duck.cmd` from GitHub:

- **Direct download:** https://raw.githubusercontent.com/Digi-Worm/duck-hub/main/duck.cmd
- **Repo:** https://github.com/Digi-Worm/duck-hub

Save it anywhere and run it. That's the whole install.

## Quick Start (1-Click / 1-Command)

- **Windows**: Double-click `duck.cmd`
- **Linux / Debian / Kali / macOS**:
  ```bash
  chmod +x duck.cmd
  ./duck.cmd
  ```
  *(Or `sudo ./duck.cmd` to bind port 80 directly.)*

Useful flags:

| Flag | Effect |
| --- | --- |
| `--headless` | Run without the GUI window (server + dashboard only) |
| `--no-browser` | Don't auto-open the dashboard |
| `--register-hosts` | Register the `duck` hostname + firewall rules |

## Features

- **Always-Resolved `duck` Hostname**: Built-in mDNS (`duck.local`), LLMNR (`duck`), NetBIOS (`DUCK`), and 1-click `hosts` + firewall registration.
- **Real-Time Intranet Chat, Group Calls & Shared Clipboard**: WebSocket chat, paste images, attach any file, clear chat, WebRTC audio/video group calls with screen sharing, live presence, and desktop + toast + sound notifications.
- **Unrestricted File Vault**: Streaming upload/download for any file type or size, media range seeking, inline preview, and streaming `.zip` export.
- **GUI Remote Desktop & Terminal**: Live screen view with mouse/keyboard control and PowerShell/CMD/Bash terminal.
- **All-Protocol Hub & LAN Scanner**: ARP + port scanner with GUI clients for SSH, FTP, Telnet/TCP, UDP, HTTP/HTTPS, RDP, and SMB.
- **1-Click Internet Tunnel + 6-Digit OTP**: Built-in Cloudflare Quick Tunnel (`https://*.trycloudflare.com`) protected by a 6-digit OTP gate.
- **GitHub Auto-Update**: Checks for new versions and updates in 1 click from the dashboard.

## Auto-Update

Duck checks `Digi-Worm/duck-hub` for a newer `APP_VERSION` and can replace itself in one click. Override the repo with the `DUCK_GITHUB_REPO` environment variable.

Updates are validated before being applied: the downloaded file must contain the polyglot marker **and** compile as Python, otherwise the update is aborted and the running copy is left untouched. A `.cmd.bak` backup is kept, and the swap is atomic.

## Versioning

Every release bumps `APP_VERSION` in `duck.cmd`. That single line is what the updater compares against, so **always bump it before pushing** — otherwise clients will never see the new build.
