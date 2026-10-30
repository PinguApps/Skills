import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "pr_body.py"
SPEC = importlib.util.spec_from_file_location("pr_body", SCRIPT)
pr_body = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pr_body)

BODY = (
    "# Summary\n\nPingu’s fix — café 🐧\n\n"
    "- [ ] First\n- [x] Second\n\n"
    "Paragraph one.\n\n\nParagraph two.\n\n"
    "```text\nline one  \n\n\nline two\n```\n"
)


class PrBodyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_json_crlf_write_has_no_carriage_returns(self):
        source = self.root / "github.json"
        source.write_bytes(json.dumps({"body": BODY.replace("\n", "\r\n")}).encode("utf-8"))
        output = self.root / "body.md"
        with contextlib.redirect_stdout(io.StringIO()):
            pr_body.main(["write", "--input", str(source), "--json", "--output", str(output)])
        self.assertEqual(output.read_bytes(), BODY.encode("utf-8"))
        self.assertNotIn(b"\r\r\n", output.read_bytes())

    def test_raw_line_endings_spacing_unicode_and_idempotence(self):
        for ending in ("\n", "\r\n", "\r\r\n", "\r"):
            with self.subTest(ending=repr(ending)):
                source = self.root / "body.md"
                source.write_bytes(BODY.replace("\n", ending).encode("utf-8"))
                for _ in range(2):
                    pr_body.write_body(source, pr_body.read_body(source))
                    self.assertEqual(source.read_bytes(), BODY.encode("utf-8"))
                self.assertIn("- [ ] First\n- [x] Second", source.read_text(encoding="utf-8"))

    def test_saved_comparison_accepts_line_endings_and_optional_final_newline(self):
        for ending in ("\n", "\r\n", "\r\r\n", "\r"):
            for intended, saved in ((BODY, BODY), (BODY, BODY[:-1]), (BODY[:-1], BODY)):
                with self.subTest(ending=repr(ending), intended_final=intended.endswith("\n")):
                    pr_body.verify_body(intended, saved.replace("\n", ending))

    def test_saved_comparison_rejects_extra_blank_line_and_other_whitespace(self):
        for saved in (
            BODY.replace("First\n-", "First\n\n-"),
            BODY.replace("Paragraph one.\n\n\n", "Paragraph one.\n\n"),
            BODY.replace("line one  \n", "line one\n"),
            BODY + "\n",
        ):
            with self.subTest(saved=saved):
                with self.assertRaisesRegex(ValueError, "differs"):
                    pr_body.verify_body(BODY, saved)

    def test_verify_command_reads_fresh_github_json_and_propagates_failures(self):
        expected = self.root / "body.md"
        pr_body.write_body(expected, BODY)
        gh = str(self.root / "gh.exe")
        url = "https://github.com/example/repo/pull/1"
        argv = ["verify", "--expected", str(expected), "--pr", url, "--gh", gh]
        response = subprocess.CompletedProcess([], 0, json.dumps({"body": BODY.replace("\n", "\r\n")}).encode("utf-8"))
        with patch.object(pr_body.subprocess, "run", return_value=response) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                pr_body.main(argv)
            run.assert_called_once_with([gh, "pr", "view", url, "--json", "body"], check=True, capture_output=True)
        response.stdout = json.dumps({"body": BODY.replace("First\n-", "First\n\n-")}).encode("utf-8")
        with patch.object(pr_body.subprocess, "run", return_value=response):
            with self.assertRaisesRegex(ValueError, "differs"):
                pr_body.main(argv)
        with patch.object(pr_body.subprocess, "run", side_effect=subprocess.CalledProcessError(1, [gh])):
            with self.assertRaises(subprocess.CalledProcessError):
                pr_body.main(argv)

    def test_offline_cli_fails_then_passes_after_repair(self):
        expected = self.root / "body.md"
        saved = self.root / "saved.json"
        pr_body.write_body(expected, BODY)
        command = [sys.executable, "-B", str(SCRIPT), "verify", "--expected", str(expected), "--saved-json", str(saved)]
        saved.write_bytes(json.dumps({"body": BODY.replace("First\n-", "First\n\n-")}).encode("utf-8"))
        failed = subprocess.run(command, capture_output=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn(b"differs", failed.stderr)
        saved.write_bytes(json.dumps({"body": BODY.replace("\n", "\r\r\n")}).encode("utf-8"))
        passed = subprocess.run(command, capture_output=True)
        self.assertEqual(passed.returncode, 0, passed.stderr)


if __name__ == "__main__":
    unittest.main()
