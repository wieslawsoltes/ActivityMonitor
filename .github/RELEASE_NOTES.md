Activity Monitor 1.3 brings responsive workspaces and a complete menu-bar monitor to all six performance views.

### What's new

- **Adaptive windows:** retain the familiar default layout, use a compact workspace down to 420 × 480 points, or expand for larger charts. Breakdowns collapse on small windows; process details open alongside or over the table to fit the available space.
- **A full menu-bar monitor:** live CPU, memory, energy, disk, network and GPU charts, history ranges, GPU selection, top processes, pause and appearance controls. Open any listed process in the main inspector.
- **Interactive histories:** hover for timestamped values, or focus a chart and use the arrow keys. Missing observations remain gaps.
- **Compact process controls:** search, filter, sort and choose columns at smaller sizes, with access to the full column set.
- **Clearer CPU readings:** total-capacity labels explain the overview’s 0–100% scale, while process values retain 100% per logical processor and can exceed 100%. Monitoring now defaults to one-second updates; two- and five-second options remain available.
- **Window shortcuts:** Command–Option–1/2/3 selects compact, minimum or default size; Command–Shift–M opens the menu-bar monitor.

| Light | Dark |
| --- | --- |
| ![Light menu-bar monitor](https://raw.githubusercontent.com/wieslawsoltes/ActivityMonitor/v1.3.0/docs/screenshots/adaptive/tray-light.jpg) | ![Dark menu-bar monitor](https://raw.githubusercontent.com/wieslawsoltes/ActivityMonitor/v1.3.0/docs/screenshots/adaptive/tray-dark.jpg) |

### Install

Download the **universal DMG**, open it, and drag **Activity Monitor** to **Applications**. The **universal ZIP** contains the complete app as an alternative. Both support Apple silicon and Intel on **macOS 14 or later**. `SHA256SUMS` verifies download contents; `INSTALL.md` contains installation details.

### Measurement notes

Counter availability depends on macOS and your hardware. Unavailable values appear as **—**. Energy shows application CPU workload. GPU process counters cover all reporting devices; observed GPU time begins with the monitoring session.

[Measurement definitions](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.3.0/docs/METRICS.md) · [Changes since 1.2.0](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.2.0...v1.3.0)
