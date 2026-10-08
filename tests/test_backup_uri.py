#!/usr/bin/env python3
"""Offline tests, synthetic URLs only; never require real GitHub secrets."""
import importlib.util
import pathlib
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "validate-backup-uri.py"
spec = importlib.util.spec_from_file_location("backup_uri_validator", SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
validate = module.diagnostic
ref = "wesqmwjjtsefyjnluosj"
pooler = f"postgresql://postgres.{ref}:fake-pwd@aws-0-eu-north-1.pooler.supabase.com:5432/postgres"
direct = f"postgresql://postgres:fake-pwd@db.{ref}.supabase.co:5432/postgres"


class BackupUrlTests(unittest.TestCase):
    def test_valid_pooler(self):
        self.assertIsNone(validate(pooler))

    def test_valid_direct(self):
        self.assertIsNone(validate(direct))

    def test_absent(self):
        self.assertEqual(validate(""), "BACKUP_URI_MISSING")

    def test_command_pasted(self):
        self.assertIsNotNone(validate("psql " + direct))

    def test_not_a_uri(self):
        self.assertIsNotNone(validate("fake-pwd"))

    def test_default_supabase_template(self):
        self.assertEqual(
            validate(f"postgresql://postgres:[YOUR-PASSWORD]@db.{ref}.supabase.co:5432/postgres"),
            "BACKUP_URI_TEMPLATE_NOT_FILLED"
        )

    def test_missing_password(self):
        self.assertEqual(
            validate(f"postgresql://postgres@db.{ref}.supabase.co:5432/postgres"),
            "BACKUP_URI_INCOMPLETE"
        )

    def test_wrong_project(self):
        self.assertEqual(
            validate("postgresql://postgres.otherref:fake-pwd@aws-0-eu-north-1.pooler.supabase.com:5432/postgres"),
            "BACKUP_URI_WRONG_PROJECT"
        )

    def test_malformed_port(self):
        self.assertEqual(
            validate(f"postgresql://postgres:fake-pwd@db.{ref}.supabase.co:bad/postgres"),
            "BACKUP_URI_MALFORMED"
        )

    def test_terminal_bracketed_paste(self):
        self.assertIsNotNone(validate("[200~" + pooler))

    def test_embedded_whitespace(self):
        self.assertIsNotNone(validate(direct + "\n"))

    def test_wrong_host(self):
        self.assertEqual(
            validate("postgresql://postgres:fake-pwd@db.example.com:5432/postgres"),
            "BACKUP_URI_UNEXPECTED_HOST"
        )

    def test_never_return_secret(self):
        private_password = "hidden-SUPER-SECRETE-THIS-NEVER-LOG"
        result = validate(f"postgresql://postgres:{private_password}@somewhere.invalid:5432/postgres")
        self.assertNotIn(private_password, str(result))


if __name__ == "__main__":
    unittest.main()
