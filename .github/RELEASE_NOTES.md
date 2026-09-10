Activity Monitor 1.6.0 adds a complete process diagnostics workspace, individual CPU charts and memory mapping visualizations.

### New

- Inspect each process in a dedicated workspace with six activity histories, detailed counters, threads, files, connections, Mach ports, fileports, memory maps, mapped images and on-demand reports.
- Detach diagnostics into a floating tool window or pin a process to the menu bar. Retained sessions preserve histories and collected reports.
- Show individual logical processors, including performance and efficiency core counts where available, or enable per-process thread CPU histories.
- Fit all CPU charts to the viewport or use optional pagination. Chart mode, filters and pagination survive adaptive layout and metric changes.
- Compare memory by protection, inspect virtual address ranges with gaps preserved, and rank mapped images by resident or virtual size. Repeated executable mappings are counted correctly.

### Improved

- Total CPU load, usage breakdown and charts use 100% per logical processor, matching process-list units. Sixteen logical processors have a 1600% combined chart maximum.
- All fifteen diagnostics pages share the main monitor’s light and dark appearance, with resizable/reorderable tables, filtering, selection and exports.
- CPU grids balance rows and adapt their height to processor count and available space.

### Install

Download the universal DMG or app ZIP for Apple silicon and Intel on macOS 14 or later. Drag Activity Monitor to Applications. SHA256SUMS verifies the downloads.

[Process diagnostics guide](https://github.com/wieslawsoltes/ActivityMonitor/blob/main/docs/diagnostics/README.md) · [Installation guide](https://github.com/wieslawsoltes/ActivityMonitor#installation)

### Availability

Protected process counters remain unavailable where macOS denies access. Shared-cache libraries may not appear individually in mapped images. Native Intel hardware was not used for local validation; forcing the Intel binary under Rosetta can under-report process CPU time.

[Changes since 1.5.0](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.5.0...v1.6.0)
