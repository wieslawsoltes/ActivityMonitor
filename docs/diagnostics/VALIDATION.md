# Diagnostics and CPU scale validation

Validated on 10 September 2026, on an Apple silicon Mac with 11 logical processors and 18 GB memory.

## Automated checks

- `swift test`: 103 tests, zero failures; five opt-in performance tests skipped in the normal run.
- Release performance run: all 17 measurement budgets and memory gates passed. The 15-minute diagnostic workspace measured 93.24 ms median / 104.35 ms p95; the 2,500-row diagnostic table measured 51.46 ms median / 55.63 ms p95.
- Performance gate tests: six passed. Packaging/notarization failure-path tests: six passed.
- Universal release build: arm64 and x86_64 compiled successfully.
- App signature, DMG integrity, ZIP contents, version, Applications link and SHA-256 checksums verified for the local 1.6.0 candidate. It is ad-hoc signed, not notarized or published.
- CPU regression fixtures cover 1, 4, 10 and 16 logical processors, full-load samples, matching headline/chart units, tick wrap, process PID reuse and uncapped per-process rates. GPU utilization remains on its independent 0–100% device scale.

## Native interaction checks

- Opened the real virtual-machine process in a dialog and a separate tool window; verified process identity and retained histories.
- Checked CPU above 100%, process memory in bytes, real thread IDs/times, file/network details and a completed code-signature report.
- Resized and reordered diagnostic table columns; both scrollbars remained at the viewport edges.
- Pinned a process, opened its popover, changed CPU to Memory, paused/resumed, and reopened the tool window. Closing the window retained the pinned session and its report.
- Verified light/dark appearances and captured the process workspace and host CPU overview. Automated rendering covers all 15 pages in both appearances at two sizes.
- Host CPU displayed values above 100% with an 1100% axis maximum on the local 11-logical-processor machine. A 16-processor fixture reaches a 1600% maximum.

## Limits

Physical runtime validation was on Apple silicon. Intel was cross-compiled; it was not tested on physical Intel hardware. Access to another process’s Mach port names and some memory/GPU details remains subject to macOS permissions. Reports label collection failures and do not invent unavailable values. The optional unique-thread-ID kernel flavor has an explicit fallback to thread handles.

The candidate is intended for user validation before merge. No release tag or public release was created.
