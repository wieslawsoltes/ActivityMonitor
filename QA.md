# Verification

Verified on September 6, 2026, on macOS 26.6, Apple M3 Pro, using Xcode 26.4.1 / Swift 6.3.1.

## Automated checks

`swift test`: 13 tests passed. Coverage includes live process enumeration (including protected PID 1), memory and system counters, CPU time compared with `getrusage`, finite CPU accounting, CSV escaping and unavailable values, network CSV parsing and export, duration formatting, process identity validation, and termination of a disposable child process. No user application was terminated by these tests.

The release is built for both arm64 and x86_64. Package validation checks the executable architectures, strict code-signature integrity, DMG integrity, archive contents, and SHA-256 checksums.

## Native UI checks

- Inspected CPU, Memory, Energy, Disk and Network against the supplied mockups in both light and dark appearances.
- Checked fixed overview layout, independent process scrolling, native process icons, metric highlighting, graph axes, mirrored transfer plots and battery history.
- Checked selection and the compact process inspector in both appearances.
- Opened the view/theme gallery and selected its CPU / Light preview; the main window changed accordingly.
- Verified live per-process network byte counts and unavailable packet indicators.
- Exported through the native Save panel; parsed the resulting CSV and confirmed 583 process records with all 11 expected columns.
- Exercised search, pause/resume, process sampling and open-file inspection during development. A real stack sample was returned successfully.

## Version 1.1 interaction and performance checks

- Reproduced the v1.0.0 tab hit-area defect by clicking Memory’s upper padding. The same coordinate selects Memory after the fix.
- Verified search by process name, the no-results state, reverse sorting, the Applications filter, and clearing the search.
- Verified keyboard selection and Return to inspect, context-menu inspection, and disabled self-termination.
- Checked all five metric views and the inspector in both appearances; see [screenshots](docs/screenshots/README.md).
- Reviewed hover/press colors against the original design CSS. Hover state is local to controls and rows; transitions respect Reduce Motion.
- Repeated process CPU measurements with an unchanged two-second sampling interval. See [methodology and raw results](docs/performance/README.md). Automation timings are not display frame latency.
- Added focused query tests for filtering, metric sorting, direction and stable PID ties.

## Limits

Tests run on both GitHub-hosted Apple silicon and Intel macOS runners. No physical Intel desktop UI test was performed. Deployment targets macOS 14; runtime verification was on macOS 26.6. Protected counters, proprietary Energy Impact, per-process packet counts remain explicitly unavailable as described in README.md. Histories begin with real samples at launch and are never fabricated to fill the graph.

The local artifacts are ad-hoc signed. Developer ID signing and Apple notarization were not performed because a distribution identity was not available. The packaging script supports both when credentials are supplied.

## GPU feature verification — September 9, 2026

The GPU feature adds eleven focused tests (24 total): parser validation, real zero versus unavailable values, nanosecond rate conversion, warmup, resets, individual counters resetting inside a growing total, queue changes, PID reuse, duplicate client observations, multiple devices, disconnect/reconnect, bounded histories, graph gaps, alternate driver keys, Metal identity matching, missing-last sorting, and CSV/JSON GPU data.

A controlled Metal process reported 1,233,367,625 cumulative driver nanoseconds. Apple's Activity Monitor displayed 1.23 seconds for the same PID, validating the conversion. Metal command-buffer elapsed time differed, so it is explicitly not used as the GPU process-time definition. See [reproduction and evidence](docs/GPU_VALIDATION.md).

The initial GPU build averaged 4.50% CPU over 30 seconds with the GPU view live and a two-second sampling interval. This is one observation on a busy development machine, not a cross-hardware benchmark. Universal DMG/ZIP verification passed locally. Native GPU screenshots use live driver values.

Native GPU checks confirmed Command–6 selection, a narrower tiled-window layout without overlapping tabs, GPU time sorting in both directions, fifteen-minute history selection, light/dark main views and inspectors, and the gallery's paired GPU previews. A GPU export saved through the native panel parsed successfully with one device, 13 history points and 536 process rows, including 17 processes reporting GPU values and explicit absence for unavailable counters.

## Version 1.5.0 performance validation — September 10, 2026

- `swift test`: 87 tests, four opt-in benchmarks skipped, zero failures. The four release-mode benchmark tests passed separately, producing all 15 required measurements and the memory-growth result. Six performance-gate failure tests and six packaging/notarization failure tests also passed.
- Headless tests render all six lists at 420 and 1,000 points in both themes, at the top, middle, bottom and after returning. Dedicated regressions verify filtering from the bottom through no results and an opaque pinned header during horizontal and vertical overflow.
- Native checks exercised all six compact views, light/dark appearance, jump-to-end selection, filtering and no-results recovery, column divider dragging, draggable header reordering, overflow scrollbars, gallery previews and view selection. The menu-bar monitor retained Memory / 5 min after closing and reopening.
- Exact chart samples, gaps, step paths, Audio Graph descriptors, limited-query/full-sort equivalence, network single-flight/PID identity, first populated snapshot, bounded caches, icon sizing and monitor deallocation have retained correctness checks.
- The universal arm64/x86_64 app, strict ad-hoc signature, version 1.5.0, DMG integrity, mounted DMG contents, ZIP contents and checksums passed local verification.
- See [measurements and interpretation](docs/performance/V1_5_RESULTS.md) and [future performance gates](docs/performance/OPTIMIZATION.md). Raster timings are not display FPS; memory growth is not a steady-state footprint claim.
- Hosted macOS CI remained queued during validation. This release uses the locally tested and verified package; hosted Intel execution and physical Intel UI performance are not claimed. Signing remains ad-hoc, without Apple notarization.
