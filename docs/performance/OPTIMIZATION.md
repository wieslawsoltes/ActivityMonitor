# Performance gates

These gates protect startup, all six dashboards, process scrolling and refresh, chart inspection, the gallery, inspector, menu-bar monitor, and memory stability. Telemetry, column configuration, selection, sorting, exports and accessibility remain part of the correctness suite.

## Run before merging

```sh
swift test
python3 -m unittest discover -s Tests/Performance -v
python3 -m unittest discover -s Tests/Packaging -v
./scripts/performance.sh
```

`swift test` includes real offscreen SwiftUI/AppKit rendering in unordered windows. No windows are shown or made key, no input is synthesized, and no user preferences are changed. All six process lists render at standard and compact widths in both themes, at the top, middle and bottom and after returning to the top. The tests check row pixels, scroll position and constant document height, so an empty viewport cannot pass as a fast render. Overview and inspector rendering, column sizing/order/visibility, hierarchy, selection, counter availability and process identity checks remain required.

A live startup test requires the first populated system/process snapshot within two seconds. A separate blocking-reader test proves slow network collection cannot block the sampler or start overlapping requests. Lifecycle and icon tests check monitor deallocation, unused popover content, exited/reused process identities and bounded Retina icon representations.

## Timing and memory budgets

`performance.sh` builds and runs the retained benchmarks in **release mode**, then validates every required measurement against [budgets.json](budgets.json). A missing case, duplicate case, invalid number, unknown architecture, test failure or budget violation fails the command. Profiling filters and screenshot output are cleared in gating runs. Raw samples, median and p95 are saved in `.build/performance/results.json`; the test log is retained alongside it.

Fixtures use 1,000 processes, 901 chronological history samples, and a populated GPU. They contain no live process names or external network data. Chart benchmarks cover CPU, memory pressure, energy, mirrored disk/network rates and GPU. The main workspace, gallery, inspector and popover use their actual SwiftUI views. The startup-model benchmark excludes process loading and window creation; it is not whole-app cold-launch latency.

| Gate | Apple silicon budget |
| --- | ---: |
| Each 15-minute chart, creation plus offscreen raster | 25 ms median |
| Filter/sort 1,000 processes in all six views | 5 ms median |
| Format every available column for 1,000 processes | 75 ms median |
| Main workspace, creation plus offscreen raster | 800 ms median |
| Gallery / inspector / popover raster | 350 / 150 / 350 ms median |
| Startup model and tray-controller construction | 20 ms median |
| One-row scroll and layout | 20 ms median, 50 ms p95 |
| Refresh 1,000 rows and layout | 30 ms median, 50 ms p95 |
| Physical-footprint growth during the warmed scroll/refresh cycle | 64 MiB maximum |

Intel timing ceilings use the explicit factor of two in the budget file. This is conservative runner headroom, not a claim that Intel is twice as slow. Memory uses the same bound on both architectures. Budget changes need a measured explanation in the PR; never automatically increase them to make a failure pass.

Scrolling benchmarks attach an actual process table to an unordered AppKit window and drive its native clip view. A published fixture replaces process metrics through SwiftUI observation. Forty iterations warm a repeating set of viewports, then 80 iterations measure scroll/layout and refresh/layout separately. Main-queue layout work drains inside autorelease pools. Physical footprint comes from `proc_pid_rusage`, not RSS. The memory ceiling catches persistent growth; bounded-cache and lifecycle tests provide additional evidence independent of allocator behavior.

Offscreen raster times include Core Graphics software rendering and are **not display frame times**. Scroll/layout timings include main-queue scheduling, but not screen compositing. Keep native interaction checks and live profiling: microbenchmarks alone do not establish smoothness or FPS.

## Implementation contracts

- Render exact chart paths in one Canvas. Keep every raw sample, separate missing-data segments, step interpolation for memory pressure, native axes and pointer/keyboard inspection, and complete Audio Graph descriptors.
- Resolve sort keys once per matching process. Top-process previews use bounded selection and must match the corresponding full sort, including missing values and PID ties.
- Keep scroll-position invalidation inside the row viewport. Materialize the visible rows plus two rows of overscan on each side; retain full process data for searching, exporting, hierarchy and selection. The header stays at the viewport edge and follows horizontal movement.
- Parse column preferences once per input string. Cache text measurement by full text, exact width and font. All caches are bounded and synchronized; changing a preference cannot mutate another cached value.
- Sample nettop asynchronously with one request in flight, retain its five-second cadence, and validate PID/start identity before using cached counters. Unavailable data remains unavailable.
- Build the menu-bar SwiftUI content only on opening; release it on closing while retaining the chosen metric and range.
- Keep icon images to one 128-pixel representation for Retina display, bound the shared cache, and discard entries for exited or reused processes. Retain only the I/O counters needed for disk deltas.

## Native and release checks

Test live scrolling, rapid jumps, Home/End/Page Up/Page Down, selection and Shift/Command extension, horizontal overflow, resizing/reordering, filtering and no-results, hierarchy, inspector, all views/themes, gallery, pause/resume and reopening the menu-bar popover. Compare a release build with the previous release under the same appearance, window size, history range, update interval and visible surface.

```sh
python3 scripts/measure-process.py PID 30 /tmp/live.json
# Profile separately from timed comparisons:
sample PID 5 -file /tmp/activity-monitor.sample.txt
# Capture headless bitmaps for inspection; these runs are not timing comparisons:
AM_PERFORMANCE=1 AM_RENDER_DIR=/tmp/activity-renders \
  swift test -c release --filter PerformanceTests
```

For focused investigation, `AM_PERFORMANCE_CASE` selects a named synchronous benchmark and `AM_PERFORMANCE_ITERATIONS` repeats it. The scroll/refresh test always runs both related phases. Use the complete script for release gates.

GitHub Actions runs correctness, headless tests and performance gates on both configured macOS architectures before packaging. Logs and JSON measurements are uploaded even on failure. Universal app signatures, DMG/ZIP contents, versions and download checksums remain separate release gates. Do not label queued CI as passed.
