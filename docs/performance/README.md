# Performance measurements

The final 1.1 candidate used **32% less CPU during automated navigation** than v1.0.0 in the same-day repeat comparison. Idle CPU was **16–19% lower**. These are observations on one busy desktop, not a CPU ceiling or a guarantee for other Macs.

## Final comparison

September 6, 2026; macOS 26.6, M3 Pro, 18 GB RAM, roughly 550–575 processes. Release builds, CPU view, light appearance, one-minute history, no inspector or search filter, default two-second collection interval. Both versions were freshly launched before their idle observations. Only one tested version ran at a time; other desktop applications remained running.

| Workload | v1.0.0 repeat | Final candidate (`55728f5`) |
| --- | ---: | ---: |
| Visible, no interaction, 30 seconds | 5.56% CPU | 4.70%, 4.53% CPU |
| 20 tab switches within 40 seconds | 18.57% CPU | 12.60% CPU |

Raw results: [baseline idle](baseline-repeat-idle.json), [baseline navigation](baseline-repeat-navigation.json), [candidate idle 1](final-idle-1.json), [candidate idle 2](final-idle-2.json), [candidate navigation](final-navigation-2.json). The second candidate idle observation followed navigation and is a warmed session. The baseline was repeated immediately afterward to check the changed desktop load. There is one uninstrumented final navigation trial per version, so no statistical confidence interval is claimed.

The candidate binary has Mach-O UUID `CA108ED2-CAA4-3E6C-A888-3063653CECF1` (arm64). Its temporary preview bundle retained the old version label; the executable was built from the final merged UI source. Version 1.1.0 packaging updates the bundle version separately.

## Method

CPU is process CPU-time delta divided by elapsed monotonic time, with 100% representing one fully occupied core. Measurement uses `ps` accumulated time, not the app’s own display. Child-process CPU is not included. RSS is recorded in KiB but is not physical footprint. No claim of a memory reduction or a hard peak-CPU limit is made.

The navigation workload cycles Command–2, 3, 4, 5, 1 four times, waiting for an accessibility snapshot after every keypress. All 20 switches completed; the remainder of the 40-second window is idle. This measures application CPU during automated interaction, including accessibility work. It does **not** establish frame latency or FPS. [Baseline call timings](baseline-repeat-navigation-timings.json) and [candidate call timings](final-navigation-timings-2.json) include automation and accessibility latency.

```sh
python3 scripts/measure-process.py PID 30 /tmp/measurement.json
# Capture stacks separately from timed comparisons:
sample PID 5 -file /tmp/stacks.txt
```

An additional complete candidate navigation trial recorded [13.07% CPU](final-navigation-1.json), but a five-second stack sample overlapped its idle tail. It is retained for transparency and excluded from the headline comparison. Its [20 call timings](final-navigation-timings-1.json) are also available. No stack sampling ran during the final uninstrumented trial.

## What changed

Native stack samples identified repeated process sorting, row construction and synchronous application activation-policy lookups. The changes cache filtered/sorted presentation results, use workspace events for application membership, cache icon lookup by PID/start time, cache UID names, and isolate row hover state. Numeric cells now use one SwiftUI Canvas per row, reducing nested cell layout while preserving the row button, accessibility summary, keyboard selection, inspector and context menu. Gallery previews share the top-process calculation. Sampling frequency and live history are unchanged.

The final five-second stack capture found the main thread predominantly waiting in the normal run loop (3,733 of 4,047 main-thread samples in the Mach-message wait path). This supports the absence of a continuous main-thread busy loop in that observation; it does not mean rendering or collection is free.

## Earlier observations

| Workload | Initial v1.0.0 | First optimization pass | Canvas pass |
| --- | ---: | ---: | ---: |
| Idle, 30 seconds | 3.66% | 2.47% | — |
| 20 switches, 40 seconds | 18.57% | 15.27% | 10.90% |

[Original idle](v1.0.0-idle.json) · [Original navigation](v1.0.0-navigation.json) · [First-pass idle](pass1-idle.json) · [First-pass navigation](pass1-navigation.json) · [Canvas navigation](canvas-navigation.json)

Desktop activity and process populations changed across these earlier runs, which is why the final baseline was repeated. A native-table prototype increased accessibility inspection cost and was discarded. Interrupted automation trials were excluded.

## Delivered in incremental PRs

[Full control hit areas (#1)](https://github.com/wieslawsoltes/ActivityMonitor/pull/1) · [Monitoring and presentation work (#2)](https://github.com/wieslawsoltes/ActivityMonitor/pull/2) · [Process-table rendering (#3)](https://github.com/wieslawsoltes/ActivityMonitor/pull/3) · [Hover, press and focus feedback (#4)](https://github.com/wieslawsoltes/ActivityMonitor/pull/4)

See the [light and dark screenshots](../screenshots/README.md) and [verification notes](../../QA.md).
