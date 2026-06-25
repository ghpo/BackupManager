# shellcheck shell=bash
# =============================================================================
# bhm — encrypt.sh
# GPG symmetric encryption for backup snapshots
# =============================================================================

# shellcheck disable=SC2034  # sourced, not executed

# --- Encryption configuration (set by config.sh) ---------------------------
# ENCRYPT_ENABLE — "yes" or "no"
# ENCRYPT_PASSWORD_FILE — path to gpg passphrase file
# ENCRYPT_ALGO — cipher algorithm (default AES256)

# --- Resolve passphrase ----------------------------------------------------
# Priority: ENCRYPT_PASSWORD_FILE > BHM_ENCRYPT_PASSWORD env > prompt

_encrypt_passphrase() {
  if [[ -n "${ENCRYPT_PASSWORD_FILE:-}" ]] && [[ -f "$ENCRYPT_PASSWORD_FILE" ]]; then
    cat "$ENCRYPT_PASSWORD_FILE"
    return 0
  fi
  if [[ -n "${BHM_ENCRYPT_PASSWORD:-}" ]]; then
    echo "$BHM_ENCRYPT_PASSWORD"
    return 0
  fi
  if [[ -t 0 ]]; then
    read -r -s -p "  Encryption password: " pw
    echo "" >&2
    echo "$pw"
    return 0
  fi
  log_error "No encryption password found. Set ENCRYPT_PASSWORD_FILE or BHM_ENCRYPT_PASSWORD."
  return 1
}

# --- Check if gpg is available ---------------------------------------------

_encrypt_check_gpg() {
  if ! command -v gpg &>/dev/null; then
    log_error "gpg not found. Install gnupg to use encryption."
    return 1
  fi
  return 0
}

# --- Encrypt a snapshot directory to .tar.gpg ------------------------------
# Usage: _encrypt_snapshot <source_dir> <output_path>
#   source_dir — the snapshot directory to encrypt (e.g. .../2026-06-25_14-00-00)
#   output_path — where to write the .tar.gpg file (e.g. .../2026-06-25_14-00-00.tar.gpg)
# Returns 0 on success, 1 on failure.

_encrypt_snapshot() {
  local src_dir="$1"
  local out_file="$2"

  _encrypt_check_gpg || return 1

  if [[ ! -d "$src_dir" ]]; then
    log_error "Encrypt: source dir not found: ${src_dir}"
    return 1
  fi

  local pw
  pw="$(_encrypt_passphrase)" || return 1

  log_info "Encrypting snapshot: ${src_dir} → ${out_file}"

  # tar + gpg in one pass (no temp files)
  # Use --no-symkey-cache to avoid leaving key material on disk
  if tar cf - -C "$(dirname "$src_dir")" "$(basename "$src_dir")" 2>/dev/null | \
     gpg --symmetric \
         --cipher-algo "${ENCRYPT_ALGO:-AES256}" \
         --batch \
         --no-symkey-cache \
         --passphrase-fd 3 \
         3< <(echo "$pw") \
         -o "$out_file" 2>/dev/null; then
    local size
    size="$(stat -c '%s' "$out_file" 2>/dev/null || echo "0")"
    log_info "Encrypted snapshot created: $(_format_bytes "$size")"
    return 0
  else
    log_error "Encryption failed for: ${src_dir}"
    rm -f "$out_file" 2>/dev/null || true
    return 1
  fi
}

# --- Decrypt a .tar.gpg snapshot to stdout ---------------------------------
# Usage: _encrypt_decrypt_to_stdout <file> [destination]
#   If destination is provided, extracts tar to that path.
#   If omitted, outputs raw decrypted tar to stdout.

_encrypt_decrypt_to_stdout() {
  local src_file="$1"

  _encrypt_check_gpg || return 1

  if [[ ! -f "$src_file" ]]; then
    log_error "Decrypt: file not found: ${src_file}"
    return 1
  fi

  local pw
  pw="$(_encrypt_passphrase)" || return 1

  gpg --decrypt \
      --batch \
      --no-symkey-cache \
      --passphrase-fd 3 \
      3< <(echo "$pw") \
      "$src_file" 2>/dev/null
}

# --- Decrypt and extract tar to a directory --------------------------------
# Usage: _encrypt_decrypt_extract <file> <dest_dir> [path...]
#   If path(s) given, extracts only those paths. Otherwise extracts all.

_encrypt_decrypt_extract() {
  local src_file="$1"
  local dest_dir="$2"
  shift 2

  _encrypt_check_gpg || return 1

  if [[ ! -f "$src_file" ]]; then
    log_error "Decrypt: file not found: ${src_file}"
    return 1
  fi

  local pw
  pw="$(_encrypt_passphrase)" || return 1

  _ensure_dir "$dest_dir" || return 1

  if (( $# > 0 )); then
    # Extract specific paths
    gpg --decrypt \
        --batch \
        --no-symkey-cache \
        --passphrase-fd 3 \
        3< <(echo "$pw") \
        "$src_file" 2>/dev/null | tar xf - -C "$dest_dir" "$@"
  else
    # Extract all
    gpg --decrypt \
        --batch \
        --no-symkey-cache \
        --passphrase-fd 3 \
        3< <(echo "$pw") \
        "$src_file" 2>/dev/null | tar xf - -C "$dest_dir"
  fi

  local rc=$?
  if (( rc == 0 )); then
    log_info "Decrypted and extracted to: ${dest_dir}"
    return 0
  else
    log_error "Decryption/extraction failed (exit ${rc})"
    return 1
  fi
}

# --- List contents of an encrypted snapshot (tar tf via pipe) --------------
# Usage: _encrypt_list_files <file> [pattern]

_encrypt_list_files() {
  local src_file="$1"
  local pattern="${2:-}"

  _encrypt_check_gpg || return 1

  if [[ ! -f "$src_file" ]]; then
    log_error "List: file not found: ${src_file}"
    return 1
  fi

  local pw
  pw="$(_encrypt_passphrase)" || return 1

  if [[ -n "$pattern" ]]; then
    gpg --decrypt \
        --batch \
        --no-symkey-cache \
        --passphrase-fd 3 \
        3< <(echo "$pw") \
        "$src_file" 2>/dev/null | tar tf - --wildcards "$pattern"
  else
    gpg --decrypt \
        --batch \
        --no-symkey-cache \
        --passphrase-fd 3 \
        3< <(echo "$pw") \
        "$src_file" 2>/dev/null | tar tf -
  fi

  local rc=$?
  if (( rc != 0 )); then
    log_error "Failed to list encrypted snapshot (exit ${rc})"
    return 1
  fi
  return 0
}

# --- Generate a random password file ---------------------------------------
# Usage: _encrypt_generate_keyfile <output_path>

_encrypt_generate_keyfile() {
  local out_file="$1"

  if [[ -f "$out_file" ]]; then
    if _confirm "Overwrite existing key file?" n; then
      :  # continue
    else
      return 1
    fi
  fi

  _ensure_dir "$(dirname "$out_file")" || return 1

  # 64 random base64 characters = 384 bits of entropy
  local key
  key="$(openssl rand -base64 48 2>/dev/null | tr -d '\n')"
  if [[ -z "$key" ]]; then
    key="$(gpg --gen-random 1 48 2>/dev/null | base64 -w0)"
  fi
  if [[ -z "$key" ]]; then
    log_error "Cannot generate random key (install openssl or haveged)"
    return 1
  fi

  echo "$key" > "$out_file"
  chmod 600 "$out_file"
  ok "Encryption key generated: ${out_file}"
  log_info "Key file saved to: ${out_file} (chmod 600)"
  echo "  Keep this file safe! Without it you CANNOT restore your backups."
  return 0
}
