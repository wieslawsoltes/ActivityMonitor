import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile
import unittest

script = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "ci-tests.py"
spec = importlib.util.spec_from_file_location("ci_tests", script)
ci_tests = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_tests)


class TestRunnerTests(unittest.TestCase):
    def test_success_and_failure_preserve_status_and_output(self):
        for status in (0, 7):
            with tempfile.TemporaryDirectory() as directory:
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    actual = ci_tests.run(
                        [sys.executable, "-c", f"print('test output'); raise SystemExit({status})"],
                        pathlib.Path(directory))
                self.assertEqual(actual, status)
                self.assertEqual(output.getvalue(), "test output\n")
                self.assertEqual((pathlib.Path(directory) / "tests.log").read_text(), "test output\n")

    def test_terminated_test_process_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                status = ci_tests.run(
                    [sys.executable, "-c", "import os, signal; os.kill(os.getpid(), signal.SIGTERM)"],
                    pathlib.Path(directory))
            self.assertEqual(status, 143)


if __name__ == "__main__":
    unittest.main()
