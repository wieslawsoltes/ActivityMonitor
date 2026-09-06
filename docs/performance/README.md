# Performance measurements

September 6, 2026; macOS 26.6, M3 Pro, 18 GB RAM. Release builds, CPU view, light appearance, default two-second collection interval. Live desktop with roughly 550–590 processes; other applications remained running. Values are observations on this machine, not hardware-independent guarantees.

| Workload | v1.0.0 | First optimization pass (`e67b49a`) |
| --- | ---: | ---: |
| Visible, no interaction, 30 seconds | 3.66% CPU | 2.47% CPU |
| 20 tab switches within 40 seconds | 18.57% CPU | 15.27% CPU |

CPU is process CPU-time delta divided by elapsed monotonic time, with 100% representing one fully occupied core. Measurement uses `ps` accumulated time, not the app's own display. Raw observations are the adjacent JSON files. RSS is included but is not physical footprint and should not be compared as one.

The navigation workload cycles Command–2, 3, 4, 5, 1 four times, waiting for an accessibility snapshot after each keypress. The observation window includes the remainder idle. This measures application CPU during automated interaction; it does **not** establish display frame latency. Computer-use latency includes automation and accessibility work. Workload timings and background desktop activity can vary; repeat measurements for final release comparisons.

Five-second native `sample` captures identified repeated `ContentView.filtered` sorting, row view construction and synchronous `NSRunningApplication.activationPolicy` lookups. The first pass caches presentation results, uses workspace events for application membership, caches process icon lookup by PID/start time, caches UID names, and isolates row hover state. It preserves sampling frequency and live history.

To measure process CPU and RSS for a chosen duration:

```sh
python3 scripts/measure-process.py PID 30 /tmp/measurement.json
sample PID 5 -file /tmp/stacks.txt
```

The first pass is an intermediate result. Further process-table work and final screenshots/results follow in separate PRs.

## Second pass: lighter numeric-cell rendering

The SwiftUI process list now draws each row's numeric cells in one Canvas, retaining the existing process-name/icon view, full-row button, keyboard handling, context menu and accessibility summary. This removes nested per-cell layout without replacing the interaction model.

The same 40-second accessibility-driven navigation workload completed at **10.90% CPU**, compared with **18.57%** in v1.0.0 (about 41% lower in these observations). All 20 switches completed. The interrupted trial was discarded; `canvas-navigation.json` is the complete trial. A native-table prototype increased accessibility inspection cost and was not retained. Final verification will repeat measurements after visual polish.
