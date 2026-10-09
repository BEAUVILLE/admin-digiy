#!/usr/bin/env python3
"""Only synthetic secrets and offline tests. Never reads GitHub secrets."""
import importlib.machinery
import io
import pathlib
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "prepare-backup-connection.py"
prep = importlib.machinery.SourceFileLoader("prepare_backup_connection", str(SOURCE)).load_module()


class LegacySecretCompatibility(unittest.TestCase):
    def test_legacy_secret_rebuilds_official_pooler_uri(self):
        password = "fake_password-1234"
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare(password, envfile.name, logs), "legacy_password_candidate")
            saved = pathlib.Path(envfile.name).read_text()
            self.assertTrue(saved.startswith("SUPABASE_DB_URL=postgresql://"))
            parsed = urlsplit(saved.strip().split("=", 1)[1])
            self.assertEqual(parsed.hostname, prep.HOST)
            self.assertEqual(parsed.username, "postgres." + prep.REF)
            self.assertEqual(parsed.port, 5432)
            self.assertEqual(parsed.password, password)
            self.assertEqual(parsed.path, "/postgres")
            self.assertEqual(logs.getvalue().count("::add-mask::"), 1)
            self.assertNotIn(password, logs.getvalue().splitlines()[-1])

    def test_isolated_restore_script_is_available_for_offline_validation(self):
        script = SOURCE.parent / "restore-supabase-github-isolated.sh"
        self.assertTrue(script.is_file())
        content = script.read_text(encoding="utf-8")
        self.assertIn("--network none", content)
        self.assertIn("REMOTE_DB_URL_FORBIDDEN", content)

    def test_existing_uri_with_outer_whitespace_is_normalized(self):
        raw_uri = f"postgresql://postgres.{prep.REF}:fake@{prep.HOST}:5432/postgres"
        for padded in (" " + raw_uri, raw_uri + "\n", "\n" + raw_uri + "  "):
            with self.subTest(padded_kind=(padded != padded.strip(), len(padded))):
                with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
                    logs = io.StringIO()
                    self.assertEqual(prep.prepare(padded, envfile.name, logs), "existing_uri")
                    self.assertEqual(pathlib.Path(envfile.name).read_text(), "SUPABASE_DB_URL=" + raw_uri + "\n")
                    self.assertIn("BACKUP_URI_OUTER_WHITESPACE_FIXED", logs.getvalue())
                    self.assertIn("::add-mask::" + raw_uri + "\n", logs.getvalue())

    def test_trim_does_not_accept_wrong_password_placeholder(self):
        raw = f" postgresql://postgres.{prep.REF}:[YOUR-PASSWORD]@{prep.HOST}:5432/postgres\n"
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare(raw, envfile.name, logs), "error")
            self.assertEqual(pathlib.Path(envfile.name).read_text(), "")
            self.assertNotIn(raw.strip(), logs.getvalue())

    def test_reserved_password_characters_are_percent_encoded(self):
        secret = "fake#?:/@password&"
        url = prep.candidate_from_legacy_password(secret)
        self.assertIsNotNone(url)
        self.assertEqual(unquote(urlsplit(url).password), secret)
        self.assertIsNone(prep.diagnostic(url))

    def test_unencoded_password_reserved_chars_are_repaired_only_for_core_pooler(self):
        passwords = (
            "MySecret#2033",
            "MySecret?2033",
            "MySecret#?@:/[]&2033",
            "MySecret%invalid",
            "MySecret%23and#raw",
        )
        for password in passwords:
            raw_uri = f"postgresql://postgres.{prep.REF}:{password}@{prep.HOST}:5432/postgres"
            with self.subTest(password_kind=len(password)):
                with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
                    logs = io.StringIO()
                    self.assertEqual(prep.prepare(raw_uri, envfile.name, logs), "existing_uri")
                    stored = pathlib.Path(envfile.name).read_text().split("=", 1)[1].strip()
                    self.assertIsNone(prep.diagnostic(stored))
                    # Existing valid %23 is an encoded # and is preserved.
                    expected = password.replace("%23", "#")
                    self.assertEqual(unquote(urlsplit(stored).password), expected)
                    self.assertIn("BACKUP_URI_PASSWORD_URL_ENCODED", logs.getvalue())
                    self.assertEqual(logs.getvalue().count("::add-mask::"), 1)
                    self.assertNotIn(password, logs.getvalue().splitlines()[-1])

    def test_no_repair_of_query_params_other_hosts_or_template(self):
        valid = f"postgresql://postgres.{prep.REF}:MySecret2033@{prep.HOST}:5432/postgres"
        wrong_host = "postgresql://postgres.otherref:MySecret#2033@other.pooler.supabase.com:5432/postgres"
        for raw in (valid + "?sslmode=require", wrong_host,
                    valid.replace("MySecret2033", "[YOUR-PASSWORD]"),
                    "postgresql://postgres.otherref:MySecret#2033@"
                    + prep.HOST + ":5432/postgres"):
            with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
                logs = io.StringIO()
                self.assertEqual(prep.prepare(raw, envfile.name, logs), "error")
                self.assertEqual(pathlib.Path(envfile.name).read_text(), "")

    def test_repair_outer_whitespace_and_reserved_password(self):
        raw_uri = f"postgresql://postgres.{prep.REF}:MySecret#2033@{prep.HOST}:5432/postgres"
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare("  " + raw_uri + "\n", envfile.name, logs), "existing_uri")
            stored = pathlib.Path(envfile.name).read_text().split("=", 1)[1].strip()
            self.assertIsNone(prep.diagnostic(stored))
            self.assertEqual(unquote(urlsplit(stored).password), "MySecret#2033")

    def test_an_existing_valid_uri_does_not_get_rewritten(self):
        raw = f"postgresql://postgres.{prep.REF}:fake@{prep.HOST}:5432/postgres"
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare(raw, envfile.name, logs), "existing_uri")
            self.assertEqual(pathlib.Path(envfile.name).read_text(), "SUPABASE_DB_URL=" + raw + "\n")
            self.assertNotIn(raw, logs.getvalue())

    def test_wrong_project_uri_is_not_treated_as_password(self):
        raw = "postgresql://postgres:fake@db.other.supabase.co:5432/postgres"
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare(raw, envfile.name, logs), "error")
            self.assertEqual(pathlib.Path(envfile.name).read_text(), "")
            self.assertNotIn(raw, logs.getvalue())

    def test_reject_possible_api_endpoint(self):
        self.assertIsNone(prep.candidate_from_legacy_password("https://project.supabase.co"))

    def test_reject_possible_psql_command(self):
        self.assertIsNone(prep.candidate_from_legacy_password("psql postgresql://postgres:pwd@host/postgres"))

    def test_reject_placeholders_and_shell_bracketed_paste(self):
        self.assertIsNone(prep.candidate_from_legacy_password("[YOUR-PASSWORD]"))
        self.assertIsNone(prep.candidate_from_legacy_password("[200~abcdefgh"))

    def test_reject_jwt_like_values(self):
        self.assertIsNone(prep.candidate_from_legacy_password("eyJabc.def.ghijk"))

    def test_reject_whitespace_and_multiline(self):
        self.assertIsNone(prep.candidate_from_legacy_password(" fake-password"))
        self.assertIsNone(prep.candidate_from_legacy_password("fake-password\nanother"))

    def test_reject_unknown_values_without_writing(self):
        with tempfile.NamedTemporaryFile(mode="r+", encoding="utf-8") as envfile:
            logs = io.StringIO()
            self.assertEqual(prep.prepare("https://project.supabase.co", envfile.name, logs), "error")
            self.assertEqual(pathlib.Path(envfile.name).read_text(), "")
            self.assertNotIn("https://project.supabase.co", logs.getvalue())

    def test_missing_github_env_refuses_fallback(self):
        logs = io.StringIO()
        self.assertEqual(prep.prepare("fake-password-1234", "", logs), "error")
        self.assertNotIn("fake-password-1234", logs.getvalue())


if __name__ == "__main__":
    unittest.main()
