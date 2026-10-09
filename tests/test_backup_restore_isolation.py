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



class RestoreFailureDiagnosticContract(unittest.TestCase):
    """Only synthetic private logs are used; no real SQL or credentials."""

    def run_classifier(self, sample):
        classifier = ROOT / "scripts" / "classify-restore-sql-failure.py"
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "private.log"
            path.write_text(sample, encoding="utf-8")
            return subprocess.run(["python3", str(classifier), str(path)],
                                  capture_output=True, text=True)

    def test_reports_sql_phase_and_sqlstate_only(self):
        secret = "CLIENT_PRIVATE_DATA_MUST_NEVER_PRINT"
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_ROLES\n"
            "CREATE ROLE\n"
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/restore/schema.sql:44: ERROR: 42P07\n"
            f"DETAIL: {secret}\n"
            "CONTEXT: customer copy must be private\n"
        )
        self.assertEqual(output.returncode, 0, output.stderr)
        self.assertEqual(output.stdout.strip(),
                         "::error::ISOLATED_RESTORE_SQL_STAGE=schema SQLSTATE=42P07")
        self.assertNotIn(secret, output.stdout + output.stderr)
        self.assertNotIn("customer", output.stdout + output.stderr)

    def test_data_phase_and_unknown_sqlstate(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_DATA\n"
            "psql: error: connection refused, private hostname\n"
        )
        self.assertEqual(output.returncode, 0)
        self.assertIn("STAGE=data SQLSTATE=unknown", output.stdout)
        self.assertNotIn("hostname", output.stdout)

    def test_unknown_when_missing_log(self):
        classifier = ROOT / "scripts" / "classify-restore-sql-failure.py"
        output = subprocess.run(["python3", str(classifier), "/missing/private.log"],
                                capture_output=True, text=True)
        self.assertEqual(output.returncode, 0)
        self.assertIn("STAGE=unknown SQLSTATE=unknown", output.stdout)

    def test_sql_restore_keeps_no_network_and_private_log(self):
        script = SCRIPT.read_text()
        self.assertIn("--network none", script)
        self.assertIn("--single-transaction", script)
        self.assertIn("--variable VERBOSITY=sqlstate", script)
        self.assertIn("sql-private.log", script)
        self.assertIn("classify-restore-sql-failure.py", script)



if __name__ == "__main__":
    unittest.main()
