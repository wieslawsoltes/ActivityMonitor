# Measurement details

Process enumeration uses `KERN_PROC_ALL`; protected processes remain listed even when macOS denies access to detailed counters. Such counters display **—**, and CSV exports leave the corresponding cells empty. JSON includes `accessible` and `ioAccessible` flags; ignore numerical placeholders when the relevant flag is false. Some protected process names are truncated by the kernel.

Process CPU time is converted from Mach absolute ticks to seconds using the machine's timebase. CPU percentage is a delta over the sampling interval and may exceed 100% for multi-core processes. The first sample has no CPU/rate baseline. The CPU overview and menu-bar percentage measure **total CPU capacity**, normalized to 0–100% across all logical processors; User + System + Idle = 100%. This matches [Apple’s system CPU summary](https://support.apple.com/guide/activity-monitor/view-cpu-activity-actmntr43452/mac). Process percentages instead use 100% per logical processor: a process can use 400% on four logical processors or 1000% on ten. For example, 250% is 2.5 logical processors’ worth of CPU time, equivalent to 25% of a ten-processor machine’s total capacity. Neither process values nor the application CPU workload chart are capped at 100%. Thread counts cover readable processes.

Memory used is active + wired + compressed physical pages. Inactive pages are shown separately as cached/inactive. These categories are not a reproduction of Apple's private App Memory accounting. Process memory prefers physical footprint, falling back to resident size. Shared pages mean process totals do not necessarily sum to physical usage.

Disk totals are process-lifetime counters, not whole-device totals. Throughput excludes processes that exit between samples and processes whose counters cannot be read. Per-process network bytes use Apple's `nettop -P -L 1 -n -x -J bytes_in,bytes_out` output and refresh every five seconds. Processes without observed network accounting show —. These counters follow the connections available to nettop and may differ from interface totals. Network interface totals aggregate non-loopback interfaces since their creation; VPN/bridge traffic may be counted at multiple interfaces. Interface removal/reset can interrupt a rate interval. Histories remain in memory for fifteen minutes and begin at app launch; pausing stops collection.

Apple's proprietary per-process Energy Impact, 12-hour power, App Nap, and per-process packet counts are not implemented or fabricated. Sampling and open-file inspection may be denied for protected processes. This app does not elevate privileges or bypass macOS protections.

Exports and reports are written only to a user-chosen local location. `sample` may also create its standard temporary report under `/tmp`. No monitoring data is transmitted.

## GPU

Device enumeration uses Metal and public IOKit registry-reading APIs. `IOAccelerator` performance statistics supply device, renderer and tiler percentages. `GPU Activity(%)` is supported as an alternate device-utilization key. Device IDs are matched to Metal registry IDs directly or through their ancestors, keeping histories separate when more than one GPU is present. Selecting a device changes the overview; process counters always cover **all reporting devices**.

GPU memory is driver-reported system memory in use / allocated, where available. Allocation is not VRAM capacity, and unified memory is shared with the rest of the system. No total is invented from Metal's recommended working-set budget. Renderer and tiler can overlap and must not be summed.

Per-process data comes from accelerator clients' `IOUserClientCreator` PID and `AppUsage[].accumulatedGPUTime` counters. The counter is interpreted as nanoseconds; this conversion was checked against Apple's GPU Time display on an M3 Pro. Process GPU percentage is the sum of valid counter deltas, divided by monotonic elapsed time and multiplied by 100. It is driver-reported GPU time, not a command buffer's elapsed duration or a share of the device graph. Overlapping work can produce rates above 100%.

**GPU time is observed during this session**, not lifetime time: initial client samples, resets, changed counter arrays and new clients establish baselines. They do not add old work. Work from clients that appear and disappear entirely between samples cannot be recovered. Partially readable processes include only valid sampled clients. PID/start-time identities prevent attributing exited processes' work to reused PIDs. When a client disappears, its observed time remains while the process lives, but its current rate becomes unavailable.

The first process sample shows “Waiting for a second GPU sample.” Missing or malformed counters display **—**, while measured zero displays **0.0**. Missing device samples and long observation gaps split history lines. A disconnected selected device retains its name and history with unavailable current values. Histories retain fifteen minutes; collection pauses with the rest of the app.

Registry properties are **driver-defined, not a documented cross-vendor telemetry contract**. Apple silicon was checked on physical hardware. Intel/AMD may supply device utilization through the supported keys, but missing engine, memory or process counters remain unavailable. No private framework, administrator helper or SIP change is used. The automated multi-device and alternate-driver tests are fixtures, not physical Intel/eGPU validation.

CSV appends `GPU %` and `Observed GPU seconds`, leaving unavailable cells blank. Process JSON includes optional `gpuPercent` / `gpuTime` and the `gpuWaiting` state independently of CPU access. “Export GPU snapshot & history…” includes all device details, histories, the selected device, the filtered process list, capture time, units and scope.

See [GPU validation](GPU_VALIDATION.md) for hardware evidence, reproduction and limits.

## Refresh interval

Monitoring defaults to one-second updates. Two- and five-second options remain available in the main window and menu-bar settings. Collection runs sequentially in the background; actual sample spacing includes collection time. Rates use measured elapsed time. Per-process network accounting retains its separate five-second refresh.
