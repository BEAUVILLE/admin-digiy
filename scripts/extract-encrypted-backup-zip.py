#!/usr/bin/env python3
"""Extract only the two encrypted GitHub backup members; never decrypt SQL.

This extractor intentionally accepts no connection URLs, no secret arguments,
and writes only ciphertext plus its checksum into an operator-owned directory.
"""
import argparse
import hashlib
import hmac
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import zipfile

ARCHIVE_RE = re.compile(
    r"digiy-supabase-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.tar\.gz\.enc\Z"
)
MAX_ENCRYPTED_BYTES = 8 * 1024**3
MAX_CHECKSUM_BYTES = 2048


def verify_external_checksum(encrypted: Path, sidecar: Path) -> None:
    """Verify bytes, never open the absolute filename embedded by GitHub Actions.

    The production backup script writes a GNU sha256sum manifest containing
    its runner-local ABSOLUTE source path. Such a path does not exist on Mac.
    Only the basename is authoritative; the digest is checked against the
    caller-selected ciphertext file, not against the original source path.
    """
    raw = sidecar.read_bytes()
    if not raw or len(raw) > MAX_CHECKSUM_BYTES:
        raise ValueError("EXTERNAL_CHECKSUM_FORMAT_INVALID")
    try:
        line = raw.decode("utf-8").rstrip("\n")
    except UnicodeError as exc:
        raise ValueError("EXTERNAL_CHECKSUM_ENCODING_INVALID") from exc
    match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *]([^\r\n]+)", line)
    if not match:
        raise ValueError("EXTERNAL_CHECKSUM_FORMAT_INVALID")
    original_name = match.group(2)
    if Path(original_name).name != encrypted.name or "\\" in original_name:
        raise ValueError("EXTERNAL_CHECKSUM_FILE_IDENTITY_MISMATCH")
    computed = hashlib.sha256()
    with encrypted.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            computed.update(block)
    if not hmac.compare_digest(computed.hexdigest().lower(), match.group(1).lower()):
        raise ValueError("EXTERNAL_CHECKSUM_DIGEST_MISMATCH")

def extract(archive_path: Path, destination: Path) -> str:
    if not destination.is_dir() or destination.is_symlink():
        raise ValueError("PRIVATE_DESTINATION_INVALID")
    if os.stat(destination).st_mode & 0o077:
        raise ValueError("PRIVATE_DESTINATION_PERMISSIONS")
    with zipfile.ZipFile(archive_path, "r") as archive:
        entries = archive.infolist()
        if len(entries) != 2:
            raise ValueError("UNEXPECTED_ZIP_MEMBER_COUNT")
        names = [info.filename for info in entries]
        enc_names = [name for name in names if ARCHIVE_RE.fullmatch(name)]
        if len(enc_names) != 1:
            raise ValueError("ENCRYPTED_MEMBER_NAME_INVALID")
        ciphertext = enc_names[0]
        if sorted(names) != sorted([ciphertext, ciphertext + ".sha256"]):
            raise ValueError("UNEXPECTED_ZIP_MEMBER")
        for info in entries:
            if info.is_dir() or "/" in info.filename or "\\" in info.filename:
                raise ValueError("ZIP_PATH_INVALID")
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode) or stat.S_ISDIR(mode):
                raise ValueError("ZIP_SYMLINK_OR_DIRECTORY_REFUSED")
            limit = MAX_CHECKSUM_BYTES if info.filename.endswith(".sha256") else MAX_ENCRYPTED_BYTES
            if info.file_size < 1 or info.file_size > limit:
                raise ValueError("ZIP_MEMBER_SIZE_INVALID")
            target = destination / info.filename
            # The destination is newly created and private. Exclude existing
            # entries to avoid accidental overwrite/symlink redirection.
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            with archive.open(info, "r") as src:
                fd = os.open(target, flags, 0o600)
                with os.fdopen(fd, "wb") as dst:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
    verify_external_checksum(destination / ciphertext, destination / (ciphertext + ".sha256"))
    return ciphertext


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract encrypted GitHub backup ZIP into a private directory")
    parser.add_argument("--verify-only", action="store_true",
                        help="Verify an extracted ciphertext and its sidecar")
    parser.add_argument("zip_file", type=Path)
    parser.add_argument("private_dir", type=Path)
    options = parser.parse_args()
    try:
        if options.verify_only:
            verify_external_checksum(options.zip_file, options.private_dir)
        else:
            extract(options.zip_file, options.private_dir)
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as exc:
        print("RESTORE_ZIP_REJECTED: " + type(exc).__name__, file=sys.stderr)
        return 78
    print("RESTORE_CIPHERTEXT_SHA256_VERIFIED" if options.verify_only
          else "RESTORE_ZIP_CIPHERTEXT_VERIFIED: exactly two members; SHA256 valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
