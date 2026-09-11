# List and Tree process views

Captured from the running PR 20 app on September 11, 2026. These are real macOS process snapshots, paused with the same **Google Chrome** search for comparison.

List shows the matching processes in column order. Tree keeps children under their parents and includes the muted **kernel_task** and **launchd** ancestor rows. The count reports the 41 search matches; those two context rows are additional.

| List | Tree |
| --- | --- |
| ![Flat CPU process list in light appearance](list-light.png) | ![Expanded Chrome process family with ancestor context in light appearance](tree-light.png) |

## Dark appearance and compact window

The wide window is 1,440 × 900 points. The compact window is 520 × 760 points and preserves the expanded branch and selected Chrome process. Long names truncate within the name column; hover reveals their complete name and parent.

| Wide | Compact |
| --- | --- |
| ![Expanded Chrome process family in dark appearance](tree-dark.png) | ![The same selected process and expanded family in a compact dark window](tree-compact.png) |

See [Follow process families](../../process-tree.md) for sorting, searching, keyboard navigation and export behavior.
