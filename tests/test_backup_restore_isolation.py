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

    def test_offline_bootstrap_matches_supabase_auth_contract(self):
        sql = (ROOT / "scripts" / "restore-local-auth-jwt.sql").read_text()
        script = SCRIPT.read_text()
        fixture = (ROOT / "tests" / "make-synthetic-backup.sh").read_text()
        self.assertIn("CREATE FUNCTION auth.jwt()", sql)
        self.assertIn("RETURNS jsonb", sql)
        self.assertIn("LANGUAGE sql STABLE", sql)
        self.assertIn("request.jwt.claims", sql)
        self.assertIn("request.jwt.claim", sql)
        self.assertIn("to_regprocedure('auth.jwt()')", sql)
        self.assertIn("auth.jwt() ->> 'sub'", fixture)
        self.assertIn('--network none', script)
        self.assertIn("--single-transaction", script)
        self.assertIn("--file /digiy-local-auth-jwt.sql", script)
        self.assertIn("ISOLATED_AUTH_JWT_HELPER_OK", script)
        # Bootstrap runs separately as the local auth schema owner before
        # the normal roles -> schema -> data transaction begins.
        self.assertIn("psql -U supabase_admin", script)
        self.assertIn("ISOLATED_AUTH_JWT_BOOTSTRAP_OK", script)
        self.assertLess(
            script.index("--file /digiy-local-auth-jwt.sql"),
            script.index("--file /restore/roles.sql"),
        )
        self.assertLess(
            script.index("--file /restore/roles.sql"),
            script.index("--file /restore/schema.sql"),
        )
        # The helper must NEVER be part of a production migration or backup.
        self.assertNotIn("SUPABASE_DB_URL", sql)
        self.assertNotIn("SECURITY DEFINER", sql)

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
                         "::error::ISOLATED_RESTORE_SQL_STAGE=schema SQLSTATE=42P07 SQL_LINE=44 MISSING_SYMBOL=unknown")
        self.assertNotIn(secret, output.stdout + output.stderr)
        self.assertNotIn("customer", output.stdout + output.stderr)

    def test_data_phase_and_unknown_sqlstate(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_DATA\n"
            "psql: error: connection refused, private hostname\n"
        )
        self.assertEqual(output.returncode, 0)
        self.assertIn("STAGE=data SQLSTATE=unknown SQL_LINE=unknown", output.stdout)
        self.assertNotIn("hostname", output.stdout)

    def test_unknown_when_missing_log(self):
        classifier = ROOT / "scripts" / "classify-restore-sql-failure.py"
        output = subprocess.run(["python3", str(classifier), "/missing/private.log"],
                                capture_output=True, text=True)
        self.assertEqual(output.returncode, 0)
        self.assertIn("STAGE=unknown SQLSTATE=unknown SQL_LINE=unknown", output.stdout)

    def test_location_rejects_untrusted_path_and_hidden_detail(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/tmp/private/customer.sql:25: ERROR: 42883\n"
            "DETAIL: SECRET_CUSTOMER_DATA\n"
        )
        self.assertIn("SQLSTATE=unknown SQL_LINE=unknown", output.stdout)
        self.assertNotIn("SECRET", output.stdout + output.stderr)
        self.assertNotIn("/tmp/private/", output.stdout + output.stderr)

    def test_identifies_safe_function_without_leaking_arguments(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/restore/schema.sql:61977: ERROR:  42883: function extensions.unaccent(text, unknown) does not exist\n"
            "LINE 1: SELECT SECRET_DO_NOT_EXPOSE\n"
            "DETAIL: PRIVATE_CUSTOMER_DATA\n"
        )
        self.assertEqual(output.returncode, 0, output.stderr)
        self.assertEqual(
            output.stdout.strip(),
            "::error::ISOLATED_RESTORE_SQL_STAGE=schema SQLSTATE=42883 SQL_LINE=61977 MISSING_SYMBOL=extensions.unaccent"
        )
        self.assertNotIn("SECRET", output.stdout + output.stderr)
        self.assertNotIn("PRIVATE", output.stdout + output.stderr)
        self.assertNotIn("unknown)", output.stdout + output.stderr)

    def test_rejects_quoted_arbitrary_function_name(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/restore/schema.sql:61977: ERROR:  42883: function \"user_secret@example.com\"(text) does not exist\n"
        )
        self.assertIn("MISSING_SYMBOL=unknown", output.stdout)
        self.assertNotIn("user_secret", output.stdout + output.stderr)

    def test_recognizes_operator_as_safe_category(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/restore/schema.sql:61977: ERROR:  42883: operator does not exist: unknown > text\n"
        )
        self.assertIn("MISSING_SYMBOL=operator", output.stdout)
        self.assertNotIn("unknown > text", output.stdout + output.stderr)


    def test_safe_bootstrap_sql_error_location(self):
        output = self.run_classifier(
            "DIGIY_RESTORE_STAGE_SCHEMA\n"
            "psql:/digiy-local-auth-jwt.sql:12: ERROR:  42601: syntax error\n"
            "DETAIL: PRIVATE_DATA_NEVER_PRINT\n"
        )
        self.assertEqual(output.returncode, 0)
        self.assertIn(
            "STAGE=auth-bootstrap SQLSTATE=42601 SQL_LINE=12 MISSING_SYMBOL=unknown",
            output.stdout,
        )
        self.assertNotIn("PRIVATE_DATA", output.stdout + output.stderr)

    def test_sql_restore_keeps_no_network_and_private_log(self):
        script = SCRIPT.read_text()
        self.assertIn("--network none", script)
        self.assertIn("--single-transaction", script)
        self.assertIn("--variable VERBOSITY=verbose", script)
        self.assertIn("sql-private.log", script)
        self.assertIn("classify-restore-sql-failure.py", script)



if __name__ == "__main__":
    unittest.main()
