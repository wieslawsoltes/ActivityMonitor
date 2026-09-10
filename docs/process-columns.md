# Process names and columns

Every perspective offers the same 28 column types as Apple’s Activity Monitor process lists. Existing column visibility and order remain the defaults. Numeric columns use compact preferred widths; the process-name column fills the remaining space. Open **Choose columns** to opt into more detail. Choices are saved separately for each perspective; **Restore columns** restores that perspective only. The process-name column is always enabled. At narrow widths, additional columns you enable remain available through horizontal scrolling. The header and rows scroll together horizontally, the header stays pinned vertically, and the vertical scrollbar stays at the visible viewport edge. Keyboard selection reveals rows without resetting the horizontal position.

Application names come from macOS registration through [NSRunningApplication.localizedName](https://developer.apple.com/documentation/appkit/nsrunningapplication/localizedname). This resolves Parallels VMs to names such as Windows 11 and Ubuntu 24.04.3 ARM64, and improves other registered apps without application-specific rules. Unregistered helpers retain their executable names. Search accepts both names. Application metadata and cached counters are matched to process start times to protect against PID reuse.

| Columns | Measurement |
| --- | --- |
| PID, User, Kind | Process identifier, account and native/translated architecture |
| % CPU, CPU time, Threads | Kernel process counters; 100% CPU means one logical processor |
| % GPU, GPU time | Driver counters where available; GPU time is observed during this session |
| Ports | Mach port count from Apple’s bundled `top` inspection client; not file descriptor count |
| Real memory | Resident bytes |
| Real private memory, Real shared memory | Resident VM region pages, deduplicating shared objects and excluding the global dyld shared cache, following [Apple’s top region accounting](https://github.com/apple-oss-distributions/top/blob/main/libtop.c) |
| Memory | Physical footprint, falling back to resident bytes when unavailable |
| Purgeable memory, Compressed memory | Task VM purgeable resident and compressed logical bytes; compressed bytes include swapped-out compressed pages and are not the physical compressor allocation |
| Idle wake-ups | Interrupt wake-up counter delta per second, with a baseline before the first value |
| Sent bytes, Sent packets, Received bytes, Received packets | Apple’s `nettop` per-process counters; values are associated with their named output headers |
| Bytes written, Bytes read | Kernel process disk I/O counters |
| Sandbox | Read-only runtime sandbox query, including dynamic sandboxes |
| Restricted | Process code-signing `CS_RESTRICT` status; not a summary of every SIP or process-access restriction |
| Preventing sleep | Active display/system sleep-prevention assertions attributed to the process |
| Energy impact | Unavailable: Apple’s proprietary score is not a public CPU percentage or energy unit |
| App nap | Unavailable: no reliable public process-state query |
| Sudden termination | Unavailable: no public query for another process’s live sudden-termination counter |

**—** means unavailable or awaiting a sample; it never means zero or No. The three Apple-only fields remain selectable with an explanation, and do not offer misleading sorting. All readable columns sort on numeric or textual values rather than formatted display strings; missing values stay last in both directions and equal values use PID order.

Detailed memory/security/port/assertion data refreshes in a separate background sampler at approximately five-second intervals. VM-region traversal runs only when private/shared memory columns have been enabled. Core charts and process sampling continue independently. Access-denied, exited or recycled processes discard their cached observations. The optional sandbox and code-status system symbols are resolved at runtime; absence or failure produces **—**. No administrator helper, process-control rights or permission changes are required.

Sources: [Apple XNU process definitions](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h), [task VM statistics](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/task_info.h), [resource counters](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h), and [IOKit sleep assertions](https://developer.apple.com/documentation/iokit/1557070-iopmcopyassertionsbyprocess).

## Customize the list

Drag a header divider to resize its column, or double-click the divider to fit its title and current values. Drag a header to reorder columns, including the process-name column. Widths, order and visibility are saved independently for all six perspectives and survive relaunch. Hidden columns retain their saved position and width. Header context menus provide fit, reset and move commands, and the column picker can reset widths or order without changing visibility. Resize dividers also support accessibility increment/decrement actions.

Click to select one process, Command-click to toggle individual processes, and Shift-click or Shift-arrow to select a range. Home, End, Page Up and Page Down navigate the list; Command-A selects visible rows. Command-C and **Copy selected rows** copy a tab-separated table using the displayed column order. Quit and Force Quit confirm the selected processes and recheck their identities before sending signals. Protected processes and the monitor itself cannot be stopped.

The process filter includes other users, active/inactive samples, GPU activity, windowed applications, a snapshot of selected processes, and a hierarchical view. Active/inactive filters use known CPU activity in the current sample; GPU activity requires a positive reported GPU sample. Windowed applications use macOS regular application registration. Hierarchical mode retains the active sort among siblings. Use disclosure arrows or Left/Right keys to collapse/expand branches, or the column menu to expand/collapse all. Search temporarily expands matching branches.

These are process-list features, not a claim of access to Apple’s privileged diagnostics or its private telemetry. The three unavailable columns above remain explicitly marked.
