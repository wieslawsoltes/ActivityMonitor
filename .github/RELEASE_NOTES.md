Activity Monitor 1.5.0 improves startup, charts, process-list updates and memory use while retaining the existing design and features.

### Improved

- All six charts render exact histories with fewer view objects. Pointer and keyboard inspection, missing-data gaps and accessibility Audio Graphs retain every sample.
- Process sorting prepares comparison values once. Gallery and menu-bar previews select only the processes they need.
- Scrolling updates the visible row viewport without rebuilding the toolbar and menus. Column resizing, reordering, visibility, selection and hierarchy remain available.
- Slow network accounting no longer delays the first process snapshot or regular system sampling.
- The menu-bar popover creates its content on opening and releases it on closing, while remembering its view and history range.
- Bounded text and preference caches reduce repeated work. Process icons retain a small Retina representation and discard stale process entries.

### Validation

The repository retains release-mode benchmarks, headless rendering and scrolling tests, memory-growth checks and documented regression budgets. See [performance gates](https://github.com/wieslawsoltes/ActivityMonitor/blob/main/docs/performance/OPTIMIZATION.md).

### Install

Download the universal DMG or app ZIP for Apple silicon and Intel on macOS 14 or later. Drag Activity Monitor to Applications. SHA256SUMS verifies the downloads.

This release is ad-hoc signed and is **not notarized**. See the [installation guide](https://github.com/wieslawsoltes/ActivityMonitor#installation).

### Known limitation

Forcing the Intel binary to run under Rosetta on Apple silicon can under-report process CPU time. Use the normal native launch of the universal app.

[Changes since 1.4.1](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.4.1...v1.5.0)
