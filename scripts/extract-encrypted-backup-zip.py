#!/usr/bin/env python3
"""Extract only the two encrypted GitHub backup members; never decrypt SQL.

This extractor intentionally accepts no connection URLs, no secret arguments,
and writes only ciphertext plus its checksum into an operator-owned directory.
"""
import argparse
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
    return ciphertext


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract encrypted GitHub backup ZIP into a private directory")
    parser.add_argument("zip_file", type=Path)
    parser.add_argument("private_dir", type=Path)
    options = parser.parse_args()
    try:
        extract(options.zip_file, options.private_dir)
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as exc:
        print("RESTORE_ZIP_REJECTED: " + type(exc).__name__, file=sys.stderr)
        return 78
    print("RESTORE_ZIP_CIPHERTEXT_EXTRACTED: exactly two encrypted artifact members")
    return 0


if __name__ == "__main__":
    sys.exit(main())
