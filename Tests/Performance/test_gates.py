import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gate", ROOT / "scripts/check-performance.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class PerformanceGateTests(unittest.TestCase):
    budgets = {"architecture_factor": {"arm64": 1},
               "benchmarks": {"work": {"median_ms": 10, "p95_ms": 20}},
               "memory_growth_bytes": {"memory": 100}}

    def log(self, samples=(1, 2, 3), growth=10):
        return "PERF " + json.dumps({"name": "work", "samples_ms": samples}) + "\nMEMORY " + json.dumps({"name": "memory", "growth_bytes": growth})

    def test_valid_measurements_pass(self):
        result = gate.evaluate(self.log(), self.budgets, "arm64")
        self.assertEqual(result["failures"], [])
        self.assertEqual(result["benchmarks"][0]["median_ms"], 2)

    def test_missing_measurements_fail(self):
        self.assertEqual(len(gate.evaluate("", self.budgets, "arm64")["failures"]), 2)

    def test_regressions_and_memory_growth_fail(self):
        self.assertEqual(len(gate.evaluate(self.log((30, 40, 50), 101), self.budgets, "arm64")["failures"]), 3)

    def test_invalid_samples_are_rejected(self):
        for values in [(1, 2), (1, 2, float("nan")), (1, 2, -1)]:
            with self.assertRaises(ValueError):
                gate.evaluate(self.log(values), self.budgets, "arm64")

    def test_duplicates_are_rejected(self):
        with self.assertRaises(ValueError):
            gate.evaluate(self.log() + "\n" + self.log(), self.budgets, "arm64")

    def test_unknown_architecture_cannot_bypass_gates(self):
        with self.assertRaises(KeyError):
            gate.evaluate(self.log(), self.budgets, "unknown")
