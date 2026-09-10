#!/usr/bin/env python3
"""Stream test output and capture stalled XCTest stacks without changing test results."""
import pathlib
import subprocess
import sys
import threading
import time


def capture_stacks(root_pid, directory):
    processes = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True)
    entries = [line.strip().split(None, 2) for line in processes.splitlines()]
    descendants = {root_pid}
    while True:
        found = {int(pid) for pid, parent, _ in entries if int(parent) in descendants}
        if found <= descendants:
            break
        descendants |= found
    for pid, _, command in entries:
        if int(pid) in descendants and pathlib.Path(command).name == "xctest":
            output = directory / f"xctest-{pid}-{int(time.time())}.sample.txt"
            subprocess.run(["sample", pid, "3", "-file", str(output)], timeout=15,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def run(command, directory, interval=300):
    directory.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, errors="replace", bufsize=1)
    stopped = threading.Event()

    def watch():
        while not stopped.wait(interval):
            try:
                capture_stacks(process.pid, directory)
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                print(f"Could not capture XCTest stacks: {error}", flush=True)

    watcher = threading.Thread(target=watch, daemon=True)
    watcher.start()
    try:
        with (directory / "tests.log").open("w") as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                sys.stdout.write(line)
                sys.stdout.flush()
        status = process.wait()
        return status if status >= 0 else 128 - status
    finally:
        process.stdout.close()
        stopped.set()
        watcher.join(timeout=20)


if __name__ == "__main__":
    sys.exit(run(["swift", "test"], pathlib.Path(".build/ci-tests")))
