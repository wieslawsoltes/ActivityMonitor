# Compound process usage

## Accounting research

Apple's hierarchical process view describes parent/child relationships; it does not define a unique application-wide resource total. Apple's XPC guide explains that `launchd` launches XPC services on an application's behalf. Consequently, an application's cooperating services can live outside its own process subtree, and a `launchd` subtree can span many applications. This implementation therefore follows observed process ancestry, not application names or inferred ownership. [Apple Activity Monitor guide](https://support.apple.com/en-gb/guide/activity-monitor/actmntr1001/mac), [XPC service lifecycle](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html).

The collector reads a task's own user/system CPU time through `PROC_PIDTASKINFO`, then computes a rate from two samples of the same PID and start time. Apple's XNU implementation obtains those counters from that task. Separately, `ri_child_*` resource counters accumulate exited children's accounting; they must not be added to a sum of the current process rows. [XNU task queries](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c), [child resource accounting](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c), [getrusage manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrusage.2.html).

Physical footprint and resident memory measure different things. XNU's footprint ledger includes compressed memory and other task charges, and already corrects overlap between certain charges within a task. Adding process memory counters does not deduplicate physical pages shared between different processes. Therefore compound memory is explicitly a sum of reported process accounting, not unique physical RAM or an estimate of memory freed by quitting. Resident fallback remains identified when a footprint is unavailable. [XNU footprint ledger](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c), [Apple memory analysis](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app), [shared physical pages](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/AboutMemory.html).

## Calculation contract

For each additive metric, a process's subtree total is its own valid value plus the totals of its **direct** children. A postorder pass through the complete, validated forest adds each process once. The existing missing-parent, newer-parent, duplicate-PID and cycle checks apply before aggregation. Traversal stays iterative for deep trees.

| Metric | Compound calculation |
| --- | --- |
| CPU %, CPU workload | Sum the sampled per-process rates; 100% remains one logical processor. Never difference subtree lifetime counters across ticks, because membership changes would create spikes. A first sample, counter reset or changed identity has no valid rate yet. |
| CPU time | Sum current members' own lifetime CPU seconds, excluding exited-child accounting. |
| GPU %, GPU time | Sum the available process execution rates and observed execution seconds. These retain the collector's device scope; concurrent work can exceed 100%. An unavailable counter is not zero. |
| Memory counters | Sum the reported byte counters for current members. Shared mappings can overlap across processes; compressed bytes and resident bytes are distinct columns and are not added together. Track use of resident fallback in the main Memory column. |
| Disk/network bytes and packets | Sum the current members' reported cumulative counters. Preserve the collector's observation period; do not label these as rates or machine-wide traffic. |
| Threads, Mach ports, idle wake-ups | Sum the reported counts or rates. Ports count per-process rights, not distinct global port objects. |
| PID, user, architecture, sandbox and other states | Describe the named process. They are not added. Unavailable Energy Impact and App Nap values remain unavailable. |

Each total tracks how many members reported a valid value. No reports produce `—`. Missing reports produce a `≥` prefix on the known subtotal. Valid zero remains zero. Negative/nonfinite rates are missing, and arithmetic overflow saturates with a lower-bound marker rather than wrapping. These bounds apply to the sum of reported counters, not to unique physical memory.

Totals include every current descendant, independently of filtering and expansion. A parent whose children are hidden still represents its complete subtree. Exits, new children and reparenting rebuild membership on the next snapshot; cumulative subtree values can decrease when members leave. Processes missed between samples and inaccessible counters cannot be reconstructed.

## Presentation and actions

Tree numeric headers use `Σ`, and parent rows show their subtree process count. Header help explains each metric's scope. Tooltips and accessibility descriptions expose both the named process's own value and the subtree total, including report coverage. List and the inspector show the individual process.

Sort roots and siblings by the displayed total, with missing totals last. Copy uses the displayed totals and labelled headers. Tree exports retain own process records and add separate subtree values, member counts and coverage; callers must not sum overlapping parent and child totals. Inspection and quit actions continue to target the original process identities.

## Verification

Use independently calculated multi-level fixtures for every additive metric, including a parent whose own usage is low but whose descendants are busy. Check unavailable parents/children, legitimate zero, rate warm-up, integer precision and overflow, filtering, collapse, reparenting, exits, PID reuse, cycles and deep chains. Check sorting, copy/export and accessibility against the same displayed totals. Retain the existing performance limits, run correctness and release gates, and inspect the updated native app and screenshots.
