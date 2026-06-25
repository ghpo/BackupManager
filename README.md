# bhm — Backup Home Manager

**bhm** is a professional incremental backup tool for Linux home directories. It uses `rsync --link-dest` for space-efficient versioned snapshots, supports Btrfs snapshots, **GPG AES256 encryption**, integrity verification, configurable retention policies, and partial restore.

## Features

- **Incremental snapshots** — `rsync --link-dest` creates hardlink forests; each snapshot looks complete yet only stores deltas.
- **Sane defaults** — excludes `node_modules/`, caches, temp files, build artifacts, `.env`, IDE configs, and more.
- **GPG AES256 encryption** — optional symmetric encryption of backup snapshots with 384-bit random keys or custom passphrases.
- **Retention policy** — configurable daily / weekly / monthly tiers.
- **Restore** — full or partial (single file/dir) with dry-run safety, transparent decryption for encrypted snapshots.
- **Integrity verification** — structural checks + configurable checksum sampling (works with encrypted snapshots via decryption to temp dir).
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
bhm encrypt status      Show encryption status
bhm encrypt generate    Generate a random encryption key
bhm encrypt enable      Enable encryption for future backups
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
| `ENCRYPT_ENABLE` | `no` | Enable GPG symmetric encryption |
| `ENCRYPT_ALGO` | `AES256` | Cipher algorithm (AES256, AES192, AES128) |
| `ENCRYPT_PASSWORD_FILE` | `""` | Path to password file (384-bit random key) |
| `BTRFS_ENABLE` | `no` | Enable Btrfs snapshots |
| `VERIFY_CHECKSUM` | `yes` | Run checksum verification after backup |

## Encryption

bhm supports optional GPG symmetric encryption for backup snapshots using AES256. When enabled, each snapshot is encrypted immediately after creation — the unencrypted directory is removed once the `.tar.gpg` file is successfully written.

### Quick start

```bash
# Generate a 384-bit random key and enable encryption
bhm encrypt generate
bhm encrypt enable

# Or use your own passphrase via environment variable
export BHM_ENCRYPT_PASSWORD="sua-frase-secreta-aqui"
bhm encrypt enable

# Next backup will produce an encrypted .tar.gpg file
bhm backup
```

### How it works

1. `rsync` creates the snapshot directory as usual
2. The directory is piped through `tar cf - | gpg --symmetric --cipher-algo AES256` in a single pass (no intermediate files)
3. The `.tar.gpg` file replaces the directory; the original is removed
4. On restore/verify, bhm automatically detects `.tar.gpg` files and decrypts them to a temporary directory (cleaned up on shell exit)

### Password sources (resolved in order)

| Priority | Source | Description |
|---|---|---|
| 1 | `ENCRYPT_PASSWORD_FILE` | Path to a file containing the passphrase (e.g. `~/.config/bhm/encrypt.key`) |
| 2 | `BHM_ENCRYPT_PASSWORD` | Environment variable with the passphrase |
| 3 | Interactive prompt | Asked at runtime (only when stdin is a terminal) |

### Security level

- **Algorithm**: AES256 (GnuPG's symmetric cipher, default since GPG 1.4.13)
- **Key derivation**: GPG's `s2k` (string-to-key) with SHA-1 hashing and multiple iterations  — the same mechanism used for OpenPGP private key protection
- **Key generation**: `bhm encrypt generate` creates a **384-bit (48-byte) random key** using `openssl rand -base64 48` or `gpg --gen-random 1 48`, encoded as 64 base64 characters
- **No key cache**: `--no-symkey-cache` prevents GPG from writing the key material to disk
- **No intermediate files**: encryption runs as a `tar | gpg` pipe — plaintext never touches disk
- **Trade-off**: encrypted snapshots are **full backups** (not incremental) — `--link-dest` cannot work across encrypted files since each is a standalone GPG blob. There is no deduplication between encrypted snapshots.

> ⚠️ **Warning**: The encryption key is unrecoverable if lost. Without the passphrase or key file, your backups **cannot** be decrypted. Keep the key file in a safe place (e.g., password manager, offline storage).

### Commands

| Command | Description |
|---|---|
| `bhm encrypt status` | Show encryption status and algorithm |
| `bhm encrypt generate [path]` | Generate a 384-bit random key file |
| `bhm encrypt password-file PATH` | Set path to an existing password file |
| `bhm encrypt enable` | Enable encryption for future backups |
| `bhm encrypt disable` | Disable encryption |

### Manual decryption

Encrypted snapshots are standard GPG symmetric files and can be decrypted with any GPG-compatible tool:

```bash
# List contents without decrypting to disk
gpg --decrypt snapshot.tar.gpg | tar tf -

# Decrypt and extract
gpg --decrypt snapshot.tar.gpg | tar xf -
```

```
bhm                          # CLI entry point
├── lib/
│   ├── config.sh            # Configuration loader
│   ├── logging.sh           # Leveled logger + rotation
│   ├── utils.sh             # Formatting, I/O helpers
│   ├── backup.sh            # rsync --link-dest engine
│   ├── encrypt.sh           # GPG symmetric encryption/decryption
│   ├── restore.sh           # Full/partial restore (with transparent decryption)
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
- `gpg` (optional, for encrypted backups)
- `btrfs-progs` (optional, for Btrfs snapshots)
- `bats` (optional, for tests)

## License

MIT — Copyright (C) 2026  Gustavo Oliveira <ghpo@protonmail.com>
