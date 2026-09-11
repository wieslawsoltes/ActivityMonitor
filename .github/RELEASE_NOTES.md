Activity Monitor 1.6.2 adds a Process Explorer-style process tree and keeps settings menus stable during live telemetry updates.

### New

- Switch the main process workspace between List and Tree views, with ancestry-aware filtering, branch navigation and persistent expansion state.
- Collapse or expand individual branches, reveal a selected process in its hierarchy and export the visible tree with parent-process context.
- Inspect complete or partial CPU and memory usage for a process subtree, with explicit accounting scope in the usage panels.

### Improved

- The process tree is built and filtered efficiently during telemetry refreshes, with performance coverage for large process sets.
- Settings menus remain open while live telemetry updates, so changing an interval or display option does not dismiss the menu.
- Threads, open files, connections, memory maps, mapped images, Mach ports and fileports show a focused set of columns by default.
- Default columns fit the available window width, with more space for names, paths and endpoints.
- Right-click a header to show additional fields, fit columns to the window or restore the default layout.
- Custom column widths and ordering are retained. Wider custom layouts still support horizontal scrolling with both scrollbars attached to the viewport.
- Numeric values align to the right, empty values display a dash, and tooltips reveal complete text. Filtering and CSV exports include hidden fields.

### Install

Download the universal DMG or app ZIP for Apple silicon and Intel on macOS 14 or later. Drag Activity Monitor to Applications. SHA256SUMS verifies the downloads.

[Process diagnostics guide](https://github.com/wieslawsoltes/ActivityMonitor/blob/main/docs/diagnostics/README.md) · [Installation guide](https://github.com/wieslawsoltes/ActivityMonitor#installation)

[Changes since 1.6.1](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.6.1...v1.6.2)
