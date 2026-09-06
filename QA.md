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

Tests run on both GitHub-hosted Apple silicon and Intel macOS runners. No physical Intel desktop UI test was performed. Deployment targets macOS 14; runtime verification was on macOS 26.6. Protected counters, proprietary Energy Impact, GPU accounting and per-process packet counts remain explicitly unavailable as described in README.md. Histories begin with real samples at launch and are never fabricated to fill the graph.

The local artifacts are ad-hoc signed. Developer ID signing and Apple notarization were not performed because a distribution identity was not available. The packaging script supports both when credentials are supplied.
