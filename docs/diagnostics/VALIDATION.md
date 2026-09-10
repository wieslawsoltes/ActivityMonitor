# Diagnostics and CPU scale validation

Validated on 10 September 2026, on an Apple silicon Mac with 11 logical processors and 18 GB memory.

## Automated checks

- `swift test`: 110 tests, zero failures; six opt-in performance tests skipped in the normal run.
- Release performance run: all 19 measurement budgets and memory gates passed. The 15-minute diagnostic workspace measured 66.48 ms median / 67.96 ms p95; the 2,500-row diagnostic table measured 34.39 ms median / 36.47 ms p95.
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

## Design refinement

All 15 pages now share the main monitor’s theme, rounded panels, typography, history controls and hover feedback. Overview groups all collected fields without dropping unknown counters; activity pages show charts and process counters; the seven native tables share an entry/filter/export toolbar, viewport scrollbars and clear empty states. Reports provide a chooser and a separate reading surface.

After refinement, the full 103-test suite passed. The final focused rendering suite passed all pages in both appearances at 760 × 500 and 1060 × 740, including explicit checks that all seven tables are present. Native checks confirmed arrow-key sidebar navigation, a filtered-empty table, readable long paths, a completed memory report and both appearances. Updated screenshots are in the [user guide](README.md#appearances).

The universal 1.6.0 local candidate was rebuilt and its DMG/ZIP contents verified after these changes.

## Individual CPU charts

- Live host topology reports 11 physical/logical processors: five performance and six efficiency cores. Explicit IODeviceTree logical IDs match processor slot IDs; no classification is inferred from order.
- Six CPU-detail tests cover independent tick baselines, nice time, counter wrap, missing/reappearing cores, thread resets and churn, opt-in/pause behavior, history budgets, live Mach buffer bounds and narrow/wide rendering in both themes.
- Native checks exercised logical processor selection and inspection, thread pagination, filtering the live VM’s VCPU workers, separate user/system rates, and pause/resume in a process menu-bar pin. One combined chart remains the launch default.
- Histories are capped at 131,072 points per grid/session. Release performance gates cover appending 4,096 thread histories and rendering twelve charts with fifteen minutes of data (1.77 ms and 41.31 ms median respectively).
- The full suite passed, followed by the focused CPU-detail suite and all release performance gates after the final grid layout refinement. The universal 1.6.0 candidate and DMG/ZIP were rebuilt and verified again.

## Limits

Physical runtime validation was on Apple silicon. Intel was cross-compiled; it was not tested on physical Intel hardware. Access to another process’s Mach port names and some memory/GPU details remains subject to macOS permissions. Reports label collection failures and do not invent unavailable values. The optional unique-thread-ID kernel flavor has an explicit fallback to thread handles.

The candidate is intended for user validation before merge. No release tag or public release was created.
