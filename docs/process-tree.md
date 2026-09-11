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

Sorting a column sorts roots and siblings while keeping children with their parent. All columns, resizing, reordering, selection, copy, inspection and process actions work in both modes. Values always describe the individual process; parent values do not add up their children.

## Search with context

Search by display name, executable name, PID or user, and use the existing process filters independently of List/Tree mode. Tree mode shows matches and their ancestor paths. Ancestors that do not match are muted and marked **Parent** where the name column has room; their tooltip and accessibility description identify them as context.

The process count reports matches. Hover over it to see the number of ancestor rows and visible rows. A new search reveals its matches automatically. You can collapse branches within the filtered tree; clearing the search restores your normal expansion state. Changing a process filter also reveals its matching paths.

Collapsing a selected descendant moves selection to its visible ancestor. Filtering out a selection clears it instead of selecting a different result. Hidden selections are excluded from copy and quit actions. Quitting retains the existing confirmation and process identity checks.

## Live updates and narrow windows

Tree mode uses the parent PID reported by macOS. A process with no available parent appears at the root; an exited or reused parent is not invented. Reparented processes move to their current parent on the next update. Expansion tracks both PID and start time, so a recycled PID does not inherit another process's collapsed state.

At narrow widths, the switch uses List and Tree icons. Indentation adapts to the name column and long names truncate within that column. Hover to read the complete name, immediate parent and nesting level, or double-click the name-column divider to fit its contents. Resizing the window preserves the mode, branches and visible selection. Wide tables keep their scrollbars at the viewport edge.

**Copy selected rows** follows their displayed order and your visible column order. Toolbar CSV and JSON exports include visible tree rows and ancestor context, preserving each process's real parent PID; collapsed descendants are omitted. **Monitor → Export Processes…** continues to export all running processes.
