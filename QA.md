# Verification

Verified on September 5, 2026, on macOS 26.6, Apple M3 Pro, using Xcode 26.4.1 / Swift 6.3.1.

## Automated checks

`swift test`: 11 tests passed. Coverage includes live process enumeration (including protected PID 1), memory and system counters, CPU time compared with `getrusage`, finite CPU accounting, CSV escaping and unavailable values, network CSV parsing and export, duration formatting, process identity validation, and termination of a disposable child process. No user application was terminated by these tests.

The release is built for both arm64 and x86_64. Package validation checks the executable architectures, strict code-signature integrity, DMG integrity, archive contents, and SHA-256 checksums.

## Native UI checks

- Inspected CPU, Memory, Energy, Disk and Network against the supplied mockups in both light and dark appearances.
- Checked fixed overview layout, independent process scrolling, native process icons, metric highlighting, graph axes, mirrored transfer plots and battery history.
- Checked selection and the compact process inspector in both appearances.
- Opened the view/theme gallery and selected its CPU / Light preview; the main window changed accordingly.
- Verified live per-process network byte counts and unavailable packet indicators.
- Exported through the native Save panel; parsed the resulting CSV and confirmed 583 process records with all 11 expected columns.
- Exercised search, pause/resume, process sampling and open-file inspection during development. A real stack sample was returned successfully.

## Limits

Intel compilation is verified, but no physical Intel runtime test was performed. Deployment targets macOS 14; runtime verification was on macOS 26.6. Protected counters, proprietary Energy Impact, GPU accounting and per-process packet counts remain explicitly unavailable as described in README.md. Histories begin with real samples at launch and are never fabricated to fill the graph.

The local artifacts are ad-hoc signed. Developer ID signing and Apple notarization were not performed because a distribution identity was not available. The packaging script supports both when credentials are supplied.
