# Memory usage and accounting

This page records the memory investigation for the process monitor and explains which
numbers are comparable with Apple’s Activity Monitor.

## What was measured

Measurements were taken on September 11, 2026 on macOS 26.6, Apple silicon, 18 GB RAM.
Both applications were native release-style macOS processes on the same desktop. The
comparison uses `footprint`, because RSS includes pages that can be reclaimed and is not
the metric shown by Activity Monitor’s Memory column.

| Process and state | Physical footprint | RSS | Notes |
| --- | ---: | ---: | --- |
| Apple Activity Monitor, already running for about 15.5 hours | 94 MB | 83 MB | Built-in AppKit application |
| Activity Monitor, current release build, 13 seconds after launch | 203 MB | 141 MB | Main window, six-process search result |
| Activity Monitor, current release build, all 574 processes | 216–224 MB | 144–148 MB | List/tree navigation warmed the process table |

An earlier controlled run of the published 1.6.3 application measured approximately
228–241 MB after ten minutes, with a cold start around 180–186 MB. A fresh local build
settled between 190 and 214 MB during the first two minutes. The exact value varies with
window size, process population, display scale, graphics driver state and the current
SwiftUI compositor state. These runs show that the application is still above Apple’s
built-in Activity Monitor in absolute footprint; the implementation does not claim an
unmeasured reduction below that baseline.

The largest writable/compositor categories in the current all-process run were:

- about 90 MB of owned physical graphics surfaces;
- 54–59 MB of `MALLOC_SMALL` allocations;
- about 16–18 MB each of `IOSurface`, `IOAccelerator` graphics backing and one large
  allocator region.

The built-in application had about 72 MB of small malloc allocations, 9 MB of
CoreAnimation and less than 1 MB of IOSurface in the same observation. This identifies
the SwiftUI/AppKit/Metal rendering floor as the main remaining difference. `vmmap` and
`leaks` did not show a process-owned leak large enough to explain the gap (`leaks`
reported about 14 KB across 284 allocations). The graphics surfaces are managed by the
system compositor and are not equivalent to a retained application data cache.

## Changes in this PR

- Process icons now use one 128 × 128 Retina representation, an 8 MiB shared image cache,
  and a 128-entry process-identity cache. Identity entries are removed when a process
  exits or a PID is reused, and least-recently-used entries are evicted when the bound is
  reached. This prevents a long-running monitor from retaining every short-lived helper.
- Process diagnostic history remains bounded. Activity history keeps at most 3,601
  samples (15 minutes at the fastest supported cadence); memory and GPU memory histories
  keep at most 901 samples and discard entries older than 15 minutes. Session ownership
  still releases the arrays when the last diagnostic surface closes.
- Memory snapshots use native counters rather than retaining region objects: physical
  footprint from `proc_pid_rusage`, resident task bytes, compressed and purgeable bytes
  from the existing task inspection path, and private/shared resident bytes from the
  bounded memory-region traversal. Missing permissions remain optional values.
- GPU diagnostics retain only device-level driver totals. Public macOS APIs expose device
  memory counters but do not expose a reliable per-process GPU allocation total, so the UI
  labels that value unavailable instead of fabricating a process number.

These changes reduce avoidable retained data while keeping process lists, sorting,
diagnostics, exports, charts and permissions behavior intact. They cannot remove the
framework and compositor memory needed to render the existing feature set.

## Reproduce a comparison

Build a release binary, launch it with a clean bundle identifier, and record the process
ID. Keep the window size, appearance, update interval, history range and process filter
fixed while comparing runs.

```sh
swift build -c release
footprint -p PID
vmmap -summary PID
sample PID 5 -file /tmp/activity-monitor.sample.txt
```

Use `footprint` for the headline number and `vmmap -summary` to separate allocator,
graphics and compositor categories. Record RSS only as a secondary diagnostic. Allow a
fresh launch to warm for at least two minutes before comparing steady state, and repeat
after navigating List, Tree and a process diagnostics page. Do not compare a cold app
with an application that has been running for many hours without recording that
difference.

The existing [performance gates](OPTIMIZATION.md) cover bounded physical-footprint
growth during the warmed scroll and refresh cycle. This document covers absolute
steady-state observations and the platform limits that the automated gates cannot
represent.
