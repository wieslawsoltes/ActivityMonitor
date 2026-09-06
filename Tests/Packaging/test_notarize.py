"""Exercise notarization failure gates without Apple credentials or network access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NotarizationTests(unittest.TestCase):
    def run_submission(self, status="Accepted", exit_code="0", profile=True):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            tool = temporary / "xcrun"
            tool.write_text('''#!/usr/bin/env python3
import json, os, sys
if sys.argv[2] == "submit":
    assert "--wait" in sys.argv and "--timeout" in sys.argv
    assert "--keychain-profile" in sys.argv and "--keychain" in sys.argv
    status = os.environ["TEST_NOTARY_STATUS"]
    if status == "Malformed":
        print("not json")
    else:
        print(json.dumps({"id": "test-submission", "status": status}))
    sys.exit(int(os.environ["TEST_NOTARY_EXIT"]))
elif sys.argv[2] == "log":
    open(sys.argv[-1], "w").write('{"issues": ["test failure"]}')
else:
    sys.exit(99)
''')
            tool.chmod(0o700)
            archive = temporary / "app.zip"
            archive.touch()
            report = temporary / "submission.json"
            environment = dict(os.environ, PATH=str(temporary) + os.pathsep + os.environ["PATH"],
                               NOTARY_KEYCHAIN=str(temporary / "test.keychain"),
                               TEST_NOTARY_STATUS=status, TEST_NOTARY_EXIT=exit_code)
            environment.pop("NOTARY_PROFILE", None)
            if profile:
                environment["NOTARY_PROFILE"] = "test-profile"
            result = subprocess.run(["/bin/bash", str(ROOT / "scripts/notarize.sh"),
                                     str(archive), str(report)], env=environment,
                                    capture_output=True, text=True)
            return result, Path(str(report) + ".log.json").exists()

    def test_accepted_submission_succeeds(self):
        result, log = self.run_submission()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(log)

    def test_invalid_submission_fails_and_fetches_log(self):
        result, log = self.run_submission("Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(log)

    def test_in_progress_is_not_success(self):
        result, _ = self.run_submission("In Progress")
        self.assertNotEqual(result.returncode, 0)

    def test_timeout_exit_fails_even_with_status_text(self):
        result, _ = self.run_submission("Accepted", "1")
        self.assertNotEqual(result.returncode, 0)

    def test_malformed_response_fails(self):
        result, _ = self.run_submission("Malformed")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_credentials_fail(self):
        result, _ = self.run_submission(profile=False)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
