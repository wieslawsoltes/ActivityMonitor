# Process list and tree

## Research

Microsoft describes Process Explorer's process tree as a way to see parent/child relationships ([Sysinternals](https://learn.microsoft.com/en-us/sysinternals/resources/archive/v03n02), [Process Explorer](https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer)). Apple's **All Processes, Hierarchically** view serves the same purpose on macOS ([Activity Monitor guide](https://support.apple.com/en-gb/guide/activity-monitor/actmntr1001/mac)).

The collector already reads each process's parent PID and start time from the same `KERN_PROC_ALL` snapshot. The existing hierarchy is coupled to a filter, builds its tree after filtering, and stores collapsed PIDs inside an adaptive table view. That loses ancestry during search and expansion state when the table is recreated, and can reuse a collapsed state for an unrelated process with the same PID.

## Product design

Keep the current flat list as the default. Add a **List / Tree** segmented switch beside the process count in every dashboard. At compact widths, retain both choices as labelled-for-accessibility icons. The switch uses the existing inset surface, selection accent, typography and hover states. A **View → Show Process Tree** command and **⌘⇧T** provide the same choice. The preference persists across tabs, resizing, window recreation and app launches.

Tree mode preserves the current columns, row height, resizing/reordering, scrollbars, inspector and process actions. Names stay clipped inside their own column; indentation adapts to its width. A tooltip and accessibility description identify the immediate parent and the actual nesting level even in deeply nested trees. Additive columns show the process plus all current descendants, with `Σ` headers, member counts and explicit partial-data markers. The inspector and List retain own process values. [Compound usage research and calculation contract](PROCESS_SUBTREE_USAGE.md).

| Interaction | Behavior |
| --- | --- |
| Disclosure | Expand/collapse one branch; Option-click applies to the subtree. |
| Left / Right | Collapse or select parent; expand or select first child. Right on a leaf does nothing. |
| Branch context menu | Expand/collapse the subtree and select its parent. |
| View menu | Expand all or collapse all. |
| Sorting | Sort roots and siblings by the displayed subtree value, keeping descendants with their parent. |
| Search and process filters | Include matching processes plus their ancestor paths. Ancestors are marked as context; unrelated siblings and descendants are omitted. Initially reveal matches. Clearing the filter restores the unfiltered expansion state. |
| Selection | Preserve visible selected identities across mode changes. Collapsing a selected descendant moves selection to its visible ancestor; hidden selections cannot be acted on. |
| Copy/export | Copy displayed totals in tree order. Toolbar exports retain own process records and their parent PID, with separate subtree totals, member counts and report coverage. |
| Live updates | Track expansion by PID **and start time**, prune exited identities, honor reparenting and reveal new children unless their branch is collapsed. |

List/tree mode is independent of the process filter and column sort. Unlike a sort mode that switches back to a flat list, choosing a different column leaves Tree selected. Expansion belongs to the main window, outside adaptive view branches; it survives switching to List and back, but is not saved across app launches because process identities change.

## Data and layout contracts

Build a forest from the complete snapshot before filtering. Ignore self-parent links, absent parents and a parent known to have started after its child. Break malformed cycles deterministically; every process appears once. Use iterative traversal for arbitrarily deep ancestry. Build matching ancestor paths without repeated full-tree scans. Restricted counters do not remove a process or imply zero usage.

Keep the existing virtualized two-axis table and pinned header. Do not construct an independent SwiftUI outline per process or nest scroll views. A flattened visible tree provides the same absolute row indices used for striping, selection, reveal and bounded row rendering. The default list performance budgets stay unchanged.

## Verification

Test sibling sorting in all six views, filtering with ancestor context, cycles, absent/recycled parents, deep chains, identity reuse, reparenting, nested collapse/expand, filtered expansion restoration, keyboard navigation and selection reconciliation. Render and inspect both appearances at compact and wide widths, including narrow/reordered name columns. Exercise switching, disclosure, search and adaptive reconstruction through the actual UI. Run the full correctness suite, release performance gates, workflow validation and universal packaging before completing the PR.
