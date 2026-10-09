#!/usr/bin/env python3
"""Safe, synthetic-only contract tests for the isolated restoration script."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "restore-supabase-github-isolated.sh"


class IsolatedRestoreContract(unittest.TestCase):
    def test_bash_syntax(self):
        result = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_remote_database_target(self):
        contents = SCRIPT.read_text()
        self.assertIn('REMOTE_DB_URL_FORBIDDEN', contents)
        self.assertIn('--network none', contents)
        self.assertIn('--rm -d --network none', contents)
        self.assertIn('ISOLATED_RESTORE_PROOF_OK', contents)
        self.assertIn('--single-transaction', contents)
        self.assertNotIn('aws-1-eu-north-1.pooler.supabase.com', contents)
        self.assertNotIn('db.wesqmwjjtsefyjnluosj.supabase.co', contents)

    def run_script(self, *, confirm="", remote="", source=None, passphrase="dummy"):
        env = dict(os.environ)
        for name in ("SUPABASE_DB_URL", "RESTORE_DB_URL", "BACKUP_PASSPHRASE",
                     "CONFIRM_ISOLATED_RESTORE", "SOURCE_ARTIFACT_DIR"):
            env.pop(name, None)
        env.update({
            "CONFIRM_ISOLATED_RESTORE": confirm,
            "BACKUP_PASSPHRASE": passphrase,
            "SUPABASE_DB_URL": remote,
            "SOURCE_ARTIFACT_DIR": str(source or "/nonexistent-test-artifact"),
        })
        return subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_refuses_unconfirmed_restore_without_side_effects(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 78)
        self.assertIn("ISOLATED_RESTORE_NOT_CONFIRMED", result.stderr)

    def test_refuses_remote_db_uri_even_when_confirmed(self):
        result = self.run_script(
            confirm="YES", remote="postgresql://fake:fake@remote.invalid/postgres")
        self.assertEqual(result.returncode, 78)
        self.assertIn("REMOTE_DB_URL_FORBIDDEN", result.stderr)
        self.assertNotIn("postgresql://", result.stderr)

    def test_refuses_nonexistent_archive_source(self):
        result = self.run_script(confirm="YES")
        self.assertEqual(result.returncode, 78)
        self.assertIn("SOURCE_ARTIFACT_MISSING", result.stderr)

    def test_refuses_missing_passphrase(self):
        with tempfile.TemporaryDirectory() as folder:
            result = self.run_script(confirm="YES", source=folder, passphrase="")
        self.assertEqual(result.returncode, 78)
        self.assertIn("BACKUP_PASSPHRASE_MISSING", result.stderr)

    def test_never_prints_synthetic_secret(self):
        with tempfile.TemporaryDirectory() as folder:
            result = self.run_script(confirm="YES", source=folder, passphrase="synth-only-sentinel")
        self.assertEqual(result.returncode, 78)
        self.assertNotIn("synth-only-sentinel", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
