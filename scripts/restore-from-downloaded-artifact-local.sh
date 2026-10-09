#!/usr/bin/env bash
# DIGIY CORE — explicitly operator-initiated restore from a downloaded,
# ENCRYPTED GitHub backup artifact ZIP. No cloud credentials; no remote DB URL.
set -Eeuo pipefail
set +x
umask 077

fail() { printf 'RESTORE_LOCAL_REFUSED: %s\n' "$1" >&2; exit 78; }
[[ -z "${GITHUB_ACTIONS:-}" && -z "${CI:-}" ]] || fail "NO_CI"
[[ "${DIGIY_ENCRYPTED_STORAGE_CONFIRMED:-}" == "YES" ]] || fail "ENCRYPTED_DISK_NOT_CONFIRMED"
[[ -z "${SUPABASE_DB_URL:-}" && -z "${RESTORE_DB_URL:-}" ]] || fail "REMOTE_DB_URL_FORBIDDEN"
[[ -z "${BACKUP_PASSPHRASE:-}" ]] || fail "PASSPHRASE_ENV_FORBIDDEN_USE_PRIVATE_PROMPT"
[[ "$#" == 1 && -f "$1" ]] || fail "ARGUMENT_REQUIRED_DOWNLOADED_ZIP"
[[ -r /dev/tty && -t 0 ]] || fail "INTERACTIVE_PRIVATE_TERMINAL_REQUIRED"
for command in bash python3 docker openssl gzip tar; do
  command -v "$command" >/dev/null 2>&1 || fail "REQUIRED_TOOL_NOT_FOUND"
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail "SHA256_CHECK_TOOL_MISSING"
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$script_dir/extract-encrypted-backup-zip.py" &&
   -f "$script_dir/restore-supabase-github-isolated.sh" ]] || fail "REQUIRED_RESTORE_SCRIPT_MISSING"
[[ "$HOME" != "/" && -n "$HOME" ]] || fail "PRIVATE_HOME_REQUIRED"

# Docker Desktop normally shares the user's home folder on macOS. Keep
# ciphertext and temporary decrypted SQL under the encrypted HOME volume.
root="$HOME/DIGIY_PRIVATE_RESTORE"
[[ ! -L "$root" ]] || fail "PRIVATE_WORK_ROOT_SYMLINK_FORBIDDEN"
mkdir -p -m 700 "$root"
chmod 700 "$root"
workdir="$(mktemp -d "$root/session.XXXXXXXX")"
trap 'rm -rf -- "$workdir"' EXIT
mkdir -m 700 "$workdir/encrypted"
python3 "$script_dir/extract-encrypted-backup-zip.py" "$1" "$workdir/encrypted" || fail "CIPHERTEXT_ZIP_INVALID"

printf 'Restauration DIGIY CORE — conteneur PostgreSQL JETABLE sans réseau.\n' >&2
printf 'La base de production ne sera PAS utilisée.\n' >&2
printf 'Phrase secrète : ' >&2
IFS= read -r -s passphrase </dev/tty || fail "SECRET_READ_FAILED"
printf '\n' >&2
[[ -n "$passphrase" ]] || fail "EMPTY_PASSPHRASE"

# Passphrase is passed solely to the local child process as an ephemeral
# environment variable. Never use argv, a local file, GitHub CI, or chat.
# On shared Macs, process environments can be observable by local administrators.
BACKUP_PASSPHRASE="$passphrase" \
CONFIRM_ISOLATED_RESTORE=YES \
SOURCE_ARTIFACT_DIR="$workdir/encrypted" \
RESTORE_WORK_ROOT="$workdir" \
bash "$script_dir/restore-supabase-github-isolated.sh"
unset passphrase
echo 'RESTORE_LOCAL_ISOLATED_SUCCESS: vérifier le rapport agrégé ci-dessus.'
