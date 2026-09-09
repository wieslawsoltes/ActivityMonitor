Activity Monitor 1.2 adds GPU monitoring alongside CPU, memory, energy, disk and network activity.

### What's new

- A dedicated **GPU view** with device utilization, 1/5/15-minute histories, renderer and tiler activity, and driver-reported GPU memory. Open it with **Command–6**.
- Sort processes by **GPU usage** or **observed GPU time**. GPU counters also appear in the CPU and Memory views and the process inspector.
- Choose a GPU for its device overview. Process counters cover all reporting devices.
- Export GPU snapshot and history data as JSON, with GPU counters included in process CSV and JSON exports.
- Light and dark GPU layouts in the six-view gallery, with navigation that fits narrower windows.

| Light | Dark |
| --- | --- |
| ![GPU monitoring in light appearance](https://raw.githubusercontent.com/wieslawsoltes/ActivityMonitor/v1.2.0/docs/screenshots/gpu/gpu-light.jpg) | ![GPU monitoring in dark appearance](https://raw.githubusercontent.com/wieslawsoltes/ActivityMonitor/v1.2.0/docs/screenshots/gpu/gpu-dark.jpg) |

### Install

Download the **universal DMG**, open it, and drag **Activity Monitor** to **Applications**. The **universal ZIP** contains the complete `.app` bundle as an alternative. Both support Apple silicon and Intel on macOS 14 or later. `SHA256SUMS` verifies download contents; `INSTALL.md` contains installation details.

### Measurement notes

GPU counter availability depends on your Mac and graphics driver. Unavailable values appear as **—**. Observed process GPU time accumulates during the monitoring session; overlapping GPU work can produce process rates above 100%. Device utilization and process rates measure different things.

Live GPU counters were validated on an M3 Pro, including a GPU-time comparison with Apple's Activity Monitor. Intel and multiple-device behavior have automated test coverage; physical Intel/eGPU counter validation remains unavailable.

[Measurement definitions](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.2.0/docs/METRICS.md#gpu) · [All screenshots](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.2.0/docs/screenshots/README.md) · [Changes since 1.1.0](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.1.0...v1.2.0)
