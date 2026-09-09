# GPU monitoring design

## Visual thesis

Extend the existing quiet macOS instrument panel: the same light/dark surfaces, blue activity accent, typography, 213-point overview and dense process workspace, with one clear GPU history as the main visual.

## Content plan

- **Navigation:** append GPU as the sixth tab, preserving Command–1 through Command–5 and adding Command–6. Keep the complete tab bounds clickable and existing hover/press feedback. Lay out navigation and toolbar together so six tabs cannot overlap controls at minimum width.
- **Overview:** selected GPU name/device menu in the heading; left: device utilization (0–100%) and 1/5/15-minute history; middle: separate renderer and tiler activity bars (they overlap and must not be summed); right: device identity and GPU memory in use / driver allocation, with unified/discrete memory identified where Metal supplies it.
- **Workspace:** sortable GPU %, observed GPU time, CPU %, memory, kind, PID and user. Existing CPU/Memory GPU columns become functional. Filters, search, column visibility, selection, process actions and CSV/JSON export retain their established behavior.
- **Inspector:** show GPU execution-time rate and observed execution time, with a concise explanation of scope and availability. Per-process rates can exceed 100% when GPU work overlaps; these are not shares of the device-utilization chart.
- **Gallery and docs:** six views in both appearances, including real screenshots of the new GPU view and inspector in the PR.

## Interaction thesis

1. Reuse the restrained 120 ms hover feedback and pressed states, respecting Reduce Motion.
2. Reuse history inspection with a crosshair and exact value; missing samples create gaps, never false zeroes.
3. Device switching changes device history/context immediately, without resetting unrelated process selection or sorting. Process counters cover all reporting GPU devices and are explicitly labeled as such.

## Data states and semantics

| State | Presentation |
| --- | --- |
| Driver reports zero | `0.0%` and an empty activity bar |
| Waiting for a second process sample | `—`, “Waiting for a second GPU sample” |
| No readable driver counter | `—`, “GPU counters unavailable for this process” |
| GPU disconnected / unavailable | Preserve clear device identity where possible; show unavailable state, never a fabricated utilization |
| Process exits or PID is reused | Discard its rate baseline and observed time |
| Driver counter resets / clients change | Rebaseline that client; do not produce negative rates or spikes |

Observed per-process GPU time accumulates valid sampled execution-time deltas during this monitoring session. It excludes work before the first baseline and cannot recover clients that appear and disappear entirely between samples. Only driver-reported counters are shown; no estimates from CPU load, GPU memory allocation, or process presence.

## Implementation boundary

Use public IOKit registry-reading and Metal device-enumeration APIs. Registry property names are driver-defined rather than a documented cross-vendor telemetry contract: parse defensively, expose availability, and test missing/partial data. No administrator helper, SIP change, private framework linking, or periodic shell command is needed. Apple silicon counters are directly observable on the development Mac; Intel/multiple-GPU behavior requires parser fixtures and device-identity tests in addition to native CI compilation.

## Initial evidence (before implementation)

September 9, 2026, M3 Pro: `IOAccelerator` exposes `PerformanceStatistics` with `Device Utilization %`, `Renderer Utilization %`, `Tiler Utilization %`, `In use system memory`, and `Alloc system memory`. Its child `AGXDeviceUserClient` nodes expose `IOUserClientCreator` and `AppUsage[].accumulatedGPUTime`. Several live Metal clients have nonzero cumulative counters. The implementation will validate units and behavior using a controlled Metal workload before treating these as verified process rates.

## Design study and implementation evidence

[Open the light/dark layout study](gpu-preview.html). The [light study capture](gpu-study-light.jpg) uses illustrative values. The implemented view uses live data; see [counter validation](../GPU_VALIDATION.md) and [product screenshots](../screenshots/README.md#gpu-preview).
