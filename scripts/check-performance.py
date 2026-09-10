#!/usr/bin/env python3
"""Fail closed on missing/invalid measurements; preserve raw samples and machine metadata."""
import json
import math
import pathlib
import platform
import subprocess
import sys


def evaluate(log, budgets, architecture):
    results = {}
    memory = {}
    for line in log.splitlines():
        if line.startswith("PERF "):
            entry = json.loads(line[5:])
            name = entry["name"]
            if name in results:
                raise ValueError(f"duplicate benchmark: {name}")
            values = entry["samples_ms"]
            if len(values) < 3 or any(type(x) not in (float, int) or not math.isfinite(x) or x < 0 for x in values):
                raise ValueError(f"invalid samples: {name}")
            ordered = sorted(values)
            entry["median_ms"] = ordered[len(ordered) // 2]
            entry["max_ms"] = ordered[-1]
            entry["p95_ms"] = ordered[math.ceil(len(ordered) * .95) - 1]
            results[name] = entry
        elif line.startswith("MEMORY "):
            entry = json.loads(line[7:])
            if entry["name"] in memory:
                raise ValueError("duplicate memory measurement")
            memory[entry["name"]] = entry
    factor = budgets["architecture_factor"][architecture]
    failures = []
    for name, limits in budgets["benchmarks"].items():
        if name not in results:
            failures.append(f"missing benchmark: {name}")
            continue
        for statistic, ceiling in limits.items():
            actual = results[name][statistic]
            if actual > ceiling * factor:
                failures.append(f"{name} {statistic}: {actual:.2f} > {ceiling * factor:.2f} ms")
    for name, ceiling in budgets["memory_growth_bytes"].items():
        value = memory.get(name, {}).get("growth_bytes")
        if type(value) is not int or value < 0 or value > ceiling:
            failures.append(f"{name} memory growth: {value}, limit {ceiling} bytes")
    return {"architecture": architecture, "architecture_factor": factor,
            "benchmarks": list(results.values()), "memory": list(memory.values()), "failures": failures}


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    budgets = json.loads((root / "docs/performance/budgets.json").read_text())
    result = evaluate(pathlib.Path(sys.argv[1]).read_text(), budgets, platform.machine())
    result["platform"] = platform.platform()
    result["commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    result["configuration"] = "release"
    pathlib.Path(sys.argv[2]).write_text(json.dumps(result, indent=2) + "\n")
    for benchmark in result["benchmarks"]:
        print(f'{benchmark["name"]}: median {benchmark["median_ms"]:.2f} ms, p95 {benchmark["p95_ms"]:.2f} ms')
    if result["failures"]:
        print("\n".join(result["failures"]), file=sys.stderr)
        return 1
    print("Performance gates passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
