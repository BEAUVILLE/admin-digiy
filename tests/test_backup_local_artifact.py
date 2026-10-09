#!/usr/bin/env python3
"""Offline tests for the local-only GitHub artifact restore bridge."""
import importlib.util
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "scripts/extract-encrypted-backup-zip.py"
WRAPPER = ROOT / "scripts/restore-from-downloaded-artifact-local.sh"
RESTORE = ROOT / "scripts/restore-supabase-github-isolated.sh"

spec = importlib.util.spec_from_file_location("artifact_zip", EXTRACTOR)
artifact_zip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact_zip)

ENC = "digiy-supabase-2026-10-09T01-46-26Z.tar.gz.enc"


class SafeEncryptedArtifactExtraction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.destination = self.root / "ciphertext"
        self.destination.mkdir(mode=0o700)
        self.zip = self.root / "artifact.zip"

    def make_zip(self, contents):
        with zipfile.ZipFile(self.zip, "w", compression=zipfile.ZIP_DEFLATED) as target:
            for name, data in contents.items():
                target.writestr(name, data)

    def valid(self, *, origin=None, tamper_digest=False):
        payload = b"Salted__fake-encrypted-bytes"
        digest = hashlib.sha256(payload).hexdigest()
        if tamper_digest:
            digest = "0" * 64
        source = origin or ENC
        return {ENC: payload, ENC + ".sha256": (digest + "  " + source + "\n").encode()}

    def test_valid_exactly_two_encrypted_members(self):
        self.make_zip(self.valid())
        self.assertEqual(artifact_zip.extract(self.zip, self.destination), ENC)
        self.assertEqual((self.destination / ENC).read_bytes(), self.valid()[ENC])
        self.assertEqual((self.destination / (ENC + ".sha256")).read_bytes(),
                         self.valid()[ENC + ".sha256"])

    def test_realistic_absolute_github_actions_source_path(self):
        original = "/home/runner/work/admin-digiy/backup-output/" + ENC
        self.make_zip(self.valid(origin=original))
        self.assertEqual(artifact_zip.extract(self.zip, self.destination), ENC)

    def test_reject_mismatched_external_sha256(self):
        self.make_zip(self.valid(tamper_digest=True))
        with self.assertRaisesRegex(ValueError, "EXTERNAL_CHECKSUM_DIGEST_MISMATCH"):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_sidecar_pointing_to_other_backup(self):
        self.make_zip(self.valid(origin="/old/runner/not-our-archive.enc"))
        with self.assertRaisesRegex(ValueError, "EXTERNAL_CHECKSUM_FILE_IDENTITY_MISMATCH"):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_traversal(self):
        self.make_zip({ENC: b"x", "../escape.sha256": b"x"})
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)
        self.assertFalse((self.root / "escape.sha256").exists())

    def test_reject_unexpected_extra_member(self):
        self.make_zip({**self.valid(), "roles.sql": b"private"})
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_nested_path(self):
        self.make_zip({ENC: b"x", "folder/" + ENC + ".sha256": b"x"})
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_malformed_archive_name(self):
        self.make_zip({"secret.sql": b"x", "secret.sql.sha256": b"x"})
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_symlink_member(self):
        with zipfile.ZipFile(self.zip, "w") as target:
            target.writestr(ENC, b"ciphertext")
            link = zipfile.ZipInfo(ENC + ".sha256")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            target.writestr(link, "../private")
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)

    def test_reject_world_readable_output_directory(self):
        self.make_zip(self.valid())
        self.destination.chmod(0o755)
        with self.assertRaises(ValueError):
            artifact_zip.extract(self.zip, self.destination)

    def test_refuse_to_overwrite_existing_archive(self):
        self.make_zip(self.valid())
        (self.destination / ENC).write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            artifact_zip.extract(self.zip, self.destination)
        self.assertEqual((self.destination / ENC).read_bytes(), b"existing")


class PrivateLocalRestoreGuard(unittest.TestCase):
    def test_native_macos_bash32_and_bsd_tar_compatibility(self):
        source = RESTORE.read_text()
        # This script runs under macOS's built-in Bash 3.2, not Bash 4+.
        self.assertNotIn("mapfile", source.split("source_dir=")[1])
        self.assertNotIn("-maxdepth", source.split("source_dir=")[1])
        self.assertNotIn("tar --no-same-owner", source)
        self.assertIn('shopt -s nullglob', source)
        self.assertIn('encrypted_files=( "$source_dir"/digiy-supabase-*.tar.gz.enc )', source)
        self.assertIn('backup_dirs=( "$tmpdir/extracted"/digiy-supabase-* )', source)
        self.assertIn('tar -xzf "$tmpdir/private.tar.gz"', source)
        self.assertIn('! -L "$archive"', source)
        self.assertIn('! -L "$checksum"', source)

    def test_shell_syntax(self):
        for script in (WRAPPER, RESTORE):
            result = subprocess.run(["bash", "-n", str(script)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def check_guard(self, **overrides):
        env = dict(os.environ)
        for key in ("CI", "GITHUB_ACTIONS", "DIGIY_ENCRYPTED_STORAGE_CONFIRMED",
                    "BACKUP_PASSPHRASE", "SUPABASE_DB_URL", "RESTORE_DB_URL"):
            env.pop(key, None)
        env.update(overrides)
        return subprocess.run(["bash", str(WRAPPER), "unused.zip"], env=env,
                              capture_output=True, text=True, timeout=10)

    def test_refuses_ci(self):
        result = self.check_guard(CI="true")
        self.assertEqual(result.returncode, 78)
        self.assertIn("NO_CI", result.stderr)

    def test_refuses_unconfirmed_disk_encryption(self):
        result = self.check_guard()
        self.assertEqual(result.returncode, 78)
        self.assertIn("ENCRYPTED_DISK_NOT_CONFIRMED", result.stderr)

    def test_refuses_remote_url(self):
        result = self.check_guard(DIGIY_ENCRYPTED_STORAGE_CONFIRMED="YES",
                                  SUPABASE_DB_URL="postgres://password@invalid.local/")
        self.assertEqual(result.returncode, 78)
        self.assertIn("REMOTE_DB_URL_FORBIDDEN", result.stderr)
        self.assertNotIn("password", result.stderr)

    def test_refuses_environment_passphrase(self):
        result = self.check_guard(DIGIY_ENCRYPTED_STORAGE_CONFIRMED="YES",
                                  BACKUP_PASSPHRASE="do-not-show-me")
        self.assertEqual(result.returncode, 78)
        self.assertIn("PASSPHRASE_ENV_FORBIDDEN", result.stderr)
        self.assertNotIn("do-not-show-me", result.stderr)


if __name__ == "__main__":
    unittest.main()
