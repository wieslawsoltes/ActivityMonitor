# Measurement details

Process enumeration uses `KERN_PROC_ALL`; protected processes remain listed even when macOS denies access to detailed counters. Such counters display **—**, and CSV exports leave the corresponding cells empty. JSON includes `accessible` and `ioAccessible` flags; ignore numerical placeholders when the relevant flag is false. Some protected process names are truncated by the kernel.

Process CPU time is converted from Mach absolute ticks to seconds using the machine's timebase. CPU percentage is a delta over the sampling interval and may exceed 100% for multi-core processes. The first sample has no CPU/rate baseline. System CPU is normalized over all processors. Thread counts cover readable processes.

Memory used is active + wired + compressed physical pages. Inactive pages are shown separately as cached/inactive. These categories are not a reproduction of Apple's private App Memory accounting. Process memory prefers physical footprint, falling back to resident size. Shared pages mean process totals do not necessarily sum to physical usage.

Disk totals are process-lifetime counters, not whole-device totals. Throughput excludes processes that exit between samples and processes whose counters cannot be read. Per-process network bytes use Apple's `nettop -P -L 1 -n -x -J bytes_in,bytes_out` output and refresh every five seconds. Processes without observed network accounting show —. These counters follow the connections available to nettop and may differ from interface totals. Network interface totals aggregate non-loopback interfaces since their creation; VPN/bridge traffic may be counted at multiple interfaces. Interface removal/reset can interrupt a rate interval. Histories remain in memory for fifteen minutes and begin at app launch; pausing stops collection.

Apple's proprietary per-process Energy Impact, 12-hour power, App Nap, GPU usage, and per-process packet counts are not implemented or fabricated. Sampling and open-file inspection may be denied for protected processes. This app does not elevate privileges or bypass macOS protections.

Exports and reports are written only to a user-chosen local location. `sample` may also create its standard temporary report under `/tmp`. No monitoring data is transmitted.

