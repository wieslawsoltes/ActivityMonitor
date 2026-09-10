Activity Monitor 1.4.1 improves automatic column fitting across all six perspectives.

### Improved

- Default columns adapt to the actual list viewport without unnecessary horizontal scrolling, including when macOS always shows scrollbars.
- Compact numeric columns leave more space for process names while keeping memory values readable. Wider windows reveal more default columns smoothly.
- Narrow lists keep the active sort column visible and use the available width fully.
- Dragging a divider preserves neighboring widths, including columns that were automatically compressed to fit.
- Manual sizes, header reordering and additional columns remain available per view. Use **Reset column widths** to restore automatic fitting.

### Install

Download the universal DMG or app ZIP for Apple silicon and Intel on macOS 14 or later. Drag Activity Monitor to Applications. SHA256SUMS verifies the downloads.

This release is ad-hoc signed and is **not notarized**. See the [installation guide](https://github.com/wieslawsoltes/ActivityMonitor#installation).

### Known limitation

Forcing the Intel binary to run under Rosetta on Apple silicon can under-report process CPU time. Use the normal native launch of the universal app.

[Changes since 1.4.0](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.4.0...v1.4.1)
