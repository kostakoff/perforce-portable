# Portable P4 Server

A self-contained [Perforce Helix Core](https://www.perforce.com/products/helix-core) server that runs from a flash drive or external disk. Plug it in, start the server, and use P4 for version control on local game projects — no network setup, no cloud, no installation.

## Why

Git is self-contained: `git init` and you're done. P4 is not — it requires a client-server architecture even for solo local work. That's a dealbreaker for quick setups, but P4 has real advantages for game development:

- Handles large binary files (textures, audio, video, models) efficiently
- Partial checkout — sync only what you need instead of cloning everything
- Native integration with Unreal Engine, Unity, and other DCC tools
- Per-file changelists and locking — the workflow game teams actually use

This project bridges the gap: a complete P4 server on a portable disk that works like a local tool.

## The Idea

Put the entire P4 server — binaries, database, depot files, journals, logs — on a flash drive or external disk. The directory structure lives on the disk itself:

```
/Volumes/p4server/
├── .p4config                    # client config (credentials)
├── helix-core-server-mac/       # binaries + scripts
│   ├── p4d                      # server
│   ├── p4                       # CLI client
│   ├── p4p                      # proxy
│   ├── p4broker                 # broker
│   ├── setup-p4d.sh             # first-time initialization
│   ├── p4ctl.sh                 # start / stop / status
│   ├── p4d-maintenance.sh       # checkpoints & cleanup
│   ├── download.sh              # fetch binaries
│   └── archive.sh               # backup before upgrades
├── root/                        # database files
├── journals/                    # transaction journal + checkpoints
├── logs/                        # server logs (CSV)
└── archives/                    # binary backups
```

The server binds to `0.0.0.0:1666`. Projects on your machine connect to `127.0.0.1:1666` using the generated `.p4config`. When you're done, stop the server and unplug — your entire version history travels with the disk.

## Quick Start

### 1. Get the binaries

```bash
./download.sh
```

Downloads the official Helix Core Server package and installs `p4`, `p4d`, `p4p`, `p4broker` into `helix-core-server-mac/`.

### 2. Initialize the server

```bash
cd helix-core-server-mac
./setup-p4d.sh
```

Interactive setup asks for a super-user password. Or run non-interactively:

```bash
./setup-p4d.sh -n -P "YourPassword1"
```

This creates `root/`, `journals/`, `logs/`, `archives/` in the parent directory, starts the server, creates a super user, and writes `.p4config`.

### 3. Use it

```bash
./p4ctl.sh status    # is it running?
./p4ctl.sh start     # start the server
./p4ctl.sh stop      # graceful shutdown (safe to unplug after this)
```

### 4. Connect from your game project

Add `helix-core-server-mac` to your `PATH` so `p4` is available from anywhere:

```bash
export PATH="/Volumes/p4server/helix-core-server-mac:$PATH"
```

Copy `.p4config` to your project root and activate it:

```bash
cp /Volumes/p4server/.p4config /path/to/my-game/
cd /path/to/my-game/
p4 set P4CONFIG=.p4config
p4 info                # verify connection
```

## Usage Examples

TBD...

## Maintenance

### Checkpoints

```bash
./p4d-maintenance.sh               # checkpoint + cleanup
./p4d-maintenance.sh --checkpoint-only
./p4d-maintenance.sh --cleanup-only --days 30
```

### Backup the server binary

Before upgrading to a new P4 version:

```bash
./archive.sh
```

Creates `archives/helix-core-server-mac-<timestamp>.tar.gz` — a full snapshot of the current binaries and scripts.

### Upgrade P4 version

```bash
./p4ctl.sh stop       # stop server
./archive.sh          # backup current version
./download.sh         # fetch new version (edit URL for new release)
./p4ctl.sh start      # start with new binaries
```

## Scripts Reference

| Script | Purpose |
|---|---|
| `download.sh` | Download and install Helix Core binaries |
| `setup-p4d.sh` | Initialize a new server (first run) |
| `p4ctl.sh` | Start / stop / restart / status |
| `p4d-maintenance.sh` | Create checkpoints, clean old journals |
| `archive.sh` | Backup binaries before version upgrades |

All scripts default to the parent directory (`..`) as the server root, so they work from the portable disk without arguments.

## How It Works

The server runs entirely from the disk. `p4d` reads its database from `root/`, writes transactions to `journals/journal`, and logs to `logs/`. The `.p4config` file carries connection credentials so `p4ctl.sh` can authenticate for graceful shutdown (`p4 admin stop` requires a logged-in user at security level 4).

When the server is stopped, the disk contains a complete, consistent P4 installation — database, depot archives, full transaction history, and checkpoints. Plug it into any Mac, run `p4ctl.sh start`, and you're back in business.

## Requirements

- macOS (Apple Silicon — `bin.macosx12arm64`)
- Flash drive or external disk (APFS or HFS+ recommended for file locking)
- No installation, no admin privileges, no network configuration

## Notes

- The server listens on `0.0.0.0:1666` — other machines on your LAN can connect too
- For single-user local use, `127.0.0.1` is sufficient
- `.p4config` contains a password in plain text — this is a local development tool, not a production deployment
