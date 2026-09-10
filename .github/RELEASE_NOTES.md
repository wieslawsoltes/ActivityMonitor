Activity Monitor 1.4.0 adds macOS application names and a complete process-column picker.

### Improved

- Virtual machines and other registered apps use their macOS display names. Search also recognizes the underlying executable name.
- All 28 column types from Apple’s process lists are available across CPU, Memory, Energy, Disk, Network and GPU. New columns are hidden by default, preserving the existing column choices.
- Compact column sizing gives process names the remaining space. Resize dividers, double-click to fit, and drag headers to reorder. Widths, order and visibility persist separately for each view, with independent reset commands.
- Added multiple/range selection, keyboard navigation, Select All, copying selected rows in displayed column order, and confirmed batch Quit/Force Quit.
- Added a collapsible process hierarchy and filters for other users, active/inactive samples, GPU activity, windowed apps and selected processes.
- Added live ports, idle wake-ups, private/shared resident memory, purgeable/compressed memory, sandbox/restricted status, sleep assertions and per-process network packets.
- Every readable column sorts by its actual value; unavailable values stay last in both directions. Slow detail sampling runs separately from chart sampling.
- Fixed wide tables pushing the vertical scrollbar off-screen. Both scrollbars now belong to the visible list viewport, with a pinned header and horizontal position preserved during keyboard navigation.

### Availability

Energy Impact, App Nap and Sudden Termination appear as **—**, with explanations, because their Apple-only measurements are unavailable. Other counters depend on process permissions and driver support. See [column details](https://github.com/wieslawsoltes/ActivityMonitor/blob/main/docs/process-columns.md).

### Install

Download the universal DMG or app ZIP for Apple silicon and Intel on macOS 14 or later. The DMG installs by dragging Activity Monitor to Applications. SHA256SUMS verifies the downloads.

[Changes since 1.3.3](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.3.3...v1.4.0)
