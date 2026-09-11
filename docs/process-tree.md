# Follow process families

Choose **Tree** beside the process count to see which processes belong to one another. Children appear beneath their parent, with indentation and disclosure arrows. Choose **List** to return to a flat, sorted table. The same switch is available in CPU, Memory, Energy, Disk, Network and GPU; **⌘⇧T** and **View → Show Process Tree** work throughout the main window.

List is the default. Your choice is remembered across app launches. During a monitoring session, branch expansion survives switching between List and Tree, changing tabs, and resizing the window.

| List | Tree |
| --- | --- |
| ![Search matches in the flat process list](screenshots/process-tree/list-light.png) | ![The same search with parent context and expanded process families](screenshots/process-tree/tree-light.png) |

[View dark and compact screenshots](screenshots/process-tree/README.md), captured from the running app with real process data.

## Explore a branch

- Click a disclosure to expand or collapse a process. **Option-click** includes every nested branch.
- With the table focused, **Right** expands a branch or selects its first child. **Left** collapses it or selects its parent. **Option-Left / Option-Right** apply collapse/expand to the subtree. Right on a leaf leaves selection unchanged.
- Right-click a process to **Expand subtree**, **Collapse subtree**, or **Select parent**.
- Use **View → Expand All Processes / Collapse All Processes** for the whole visible tree. These actions are also available by right-clicking the List/Tree switch.

Sorting a column sorts roots and siblings by the displayed value while keeping children with their parent. All columns, resizing, reordering, selection, copy, inspection and process actions work in both modes.

## Read combined usage

In Tree, **Σ** columns show each process's own usage **plus all its current descendants**, counted once. A parent with 5% CPU and children using 20% and 30% shows **55%**. Its children still show their respective totals. CPU keeps the same scale as List: 100% means one logical processor, so combined usage can exceed 100%.

Parent name badges show the number of processes in the subtree where space permits. Hover over a row to compare **own** and **subtree** values and see how many processes reported each counter. List and the inspector show the named process's own values; PID, user, architecture and state columns always describe that process.

- **≥** marks the known subtotal when some counters are unavailable or an arithmetic limit is reached. **—** means no member reported a valid counter. A newly observed process needs a second CPU sample before it contributes a CPU rate; valid idle usage remains zero.
- **Memory totals add reported process counters.** Shared mappings can overlap, so these totals are not unique physical RAM or the amount freed by quitting. Memory uses resident size when a footprint is unavailable; row help identifies that fallback. Resident and compressed memory remain separate counters.
- CPU/GPU time and disk/network byte counters describe current members' accumulated or observed activity. They can decrease when processes exit or leave the subtree. CPU and GPU percentages sum sampled rates, so a new child's lifetime counter cannot create a false rate spike.
- Parent and child totals overlap. Do not add every visible row to calculate system usage. The overview charts continue to show their system measurements.

Expanding, collapsing or searching does not change a subtree's total. Hidden descendants still contribute; the count and tooltip describe the full subtree. Quitting or inspecting a parent targets that process, using the existing process actions.

## Search with context

Search by display name, executable name, PID or user, and use the existing process filters independently of List/Tree mode. Tree mode shows matches and their ancestor paths. Ancestors that do not match are muted and marked **Parent** where the name column has room; their tooltip and accessibility description identify them as context.

The process count reports matches. Hover over it to see the number of ancestor rows and visible rows. A new search reveals its matches automatically. You can collapse branches within the filtered tree; clearing the search restores your normal expansion state. Changing a process filter also reveals its matching paths.

Filters match individual processes. For example, an idle parent can match **Inactive processes** while its combined usage includes a busy child. The **Σ** headers and row help identify that broader scope.

Collapsing a selected descendant moves selection to its visible ancestor. Filtering out a selection clears it instead of selecting a different result. Hidden selections are excluded from copy and quit actions. Quitting retains the existing confirmation and process identity checks.

## Live updates and narrow windows

Tree mode uses the parent PID reported by macOS. A process with no available parent appears at the root; an exited or reused parent is not invented. Reparented processes move to their current parent on the next update. Expansion tracks both PID and start time, so a recycled PID does not inherit another process's collapsed state.

At narrow widths, the switch uses List and Tree icons. Indentation adapts to the name column and long names truncate within that column. Hover to read the complete name, immediate parent and nesting level, or double-click the name-column divider to fit its contents. Resizing the window preserves the mode, branches and visible selection. Wide tables keep their scrollbars at the viewport edge.

**Copy selected rows** follows their displayed order and your visible column order, with **Σ** headers for combined values. Toolbar exports include visible rows and ancestor context; hidden descendants contribute to subtree totals but are not exported as separate rows.

Tree CSV retains own process columns and adds **Subtree** values, process counts, reporting counts and status (`complete`, `partial`, `unavailable` or `overflow`). Tree JSON separates each own `process` record from its `subtree` counters and includes scope metadata. GPU snapshot exports also retain separate subtree counters. Missing values stay empty or absent, while known zero stays zero. **Monitor → Export Processes…** continues to export all running processes with individual values.
