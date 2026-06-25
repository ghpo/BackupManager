# bhm — Backup Home Manager

**bhm** is a professional incremental backup tool for Linux home directories. It uses `rsync --link-dest` for space-efficient versioned snapshots, supports Btrfs snapshots, integrity verification, configurable retention policies, and partial restore.

## Features

- **Incremental snapshots** — `rsync --link-dest` creates hardlink forests; each snapshot looks complete yet only stores deltas.
- **Sane defaults** — excludes `node_modules/`, caches, temp files, build artifacts, `.env`, IDE configs, and more.
- **Retention policy** — configurable daily / weekly / monthly tiers.
- **Restore** — full or partial (single file/dir) with dry-run safety.
- **Integrity verification** — structural checks + configurable checksum sampling.
- **Btrfs snapshots** — optional pre/post backup read-only subvolume snapshots.
- **All rsync exit codes** — handled and reported (including 24 "vanished files", 23 partial, 25 max-delete).
- **Logging** — syslog-style leveled logger with automatic rotation.
- **Portable** — pure Bash, no exotic dependencies. Works on Fedora, Ubuntu, Debian, Arch.

## Quick Start

```bash
# Install
git clone <repo> ~/apps/BackupManager
cd ~/apps/BackupManager
sudo make install

# Or use the install script
./install.sh

# Run your first backup
bhm backup

# See your snapshots
bhm list

# Check status
bhm status
```

## Usage

```
bhm backup              Run an incremental backup
bhm list                List available snapshots
bhm restore             Dry-run restore from latest snapshot
bhm restore --no-dry-run --path Documents/foo   Partial restore
bhm verify              Verify integrity of latest snapshot
bhm cleanup             Prune old backups (retention policy)
bhm snapshot create     Create a Btrfs snapshot
bhm snapshots list      List Btrfs snapshots
bhm config              Show effective configuration
bhm status              Overview of backup health
```

## Configuration

User config: `~/.config/bhm/bhm.conf`
System config: `/etc/bhm/bhm.conf`

Key settings:

| Variable | Default | Description |
|---|---|---|
| `BACKUP_SRC` | `$HOME` | Directory to back up |
| `BACKUP_DST` | `~/.local/share/bhm/backups` | Backup storage location |
| `RETENTION_DAILY` | `7` | Number of daily backups to keep |
| `RETENTION_WEEKLY` | `4` | Weekly backups (Sundays) |
| `RETENTION_MONTHLY` | `3` | Monthly backups (1st of month) |
| `BTRFS_ENABLE` | `no` | Enable Btrfs snapshots |
| `VERIFY_CHECKSUM` | `yes` | Run checksum verification after backup |

## Architecture

```
bhm                          # CLI entry point
├── lib/
│   ├── config.sh            # Configuration loader
│   ├── logging.sh           # Leveled logger + rotation
│   ├── utils.sh             # Formatting, I/O helpers
│   ├── backup.sh            # rsync --link-dest engine
│   ├── restore.sh           # Full/partial restore
│   ├── verify.sh            # Integrity verification
│   ├── snapshot.sh          # Btrfs snapshot management
│   └── cleanup.sh           # Retention policy engine
├── etc/bhm.conf             # Default config
├── tests/
│   ├── bats/                # Bats test files
│   └── run_tests.sh         # Test runner
├── Makefile
└── install.sh
```

## Development

```bash
# Run tests
make test

# ShellCheck
make lint

# All checks
make check

# Format code
make format
```

### CI

GitHub Actions workflow runs ShellCheck, Bats tests, and rsync compatibility check on every push.

## Requirements

- Bash 4.4+
- rsync 3.1+
- `sha256sum` or `shasum` (for checksum verification)
- `btrfs-progs` (optional, for Btrfs snapshots)
- `bats` (optional, for tests)

## License

MIT — Copyright (C) 2026  Gustavo Oliveira <ghpo@protonmail.com>
