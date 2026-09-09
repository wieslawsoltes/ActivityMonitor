# Adaptive monitoring

## Visual thesis
Preserve the quiet light/dark instrument panel at 1440 × 900, allowing the same content to reflow into a compact utility window, a larger workspace, and a menu-bar popover.

## Content plan
- Primary: selected metric, live value and interactive history.
- Support: breakdown and hardware context, kept in the original three-panel row at default size; chart above two details at medium widths; expandable stacked details at compact widths.
- Detail: all processes with adaptive priority columns, search/filter/sort and full-column mode; inspector beside wide workspaces and overlaid on smaller windows.
- Primary action in the menu bar: open the full monitor at the selected metric/process. Share the monitor, layout, overview panels, history controls and charts.

## Interaction thesis
- Preserve selected metric, process, search, sorting and history range while resizing.
- Fast disclosure and inspector transitions, disabled by Reduce Motion; existing hover/press feedback throughout.
- Swift Charts history inspection with pointer selection, keyboard navigation, exact values, timestamps, readable axes and observation gaps.

## Layout contract
| Width | Window behavior |
| --- | --- |
| 420–719 | Two-row compact toolbar, full-width chart, expandable details, priority process columns and inspector overlay |
| 720–1119 | Compact toolbar, chart above two details, scrolling workspace where height is constrained |
| 1120–1599 | Original three-panel proportions and 213-point overview; original toolbar at default size |
| 1600+ | Larger 280-point charts, flexible process workspace, 340-point inspector |

Minimum window: 420 × 480. Short windows scroll the workspace without losing controls. Menu-bar surface: 420 points wide, height bounded by screen; six metrics, range/device selection, overview, top processes, pause, settings and open/quit actions. No second sampler or separate mock data in production.

## Verification
Exercise all six metrics in light/dark, minimum/default/expanded sizes and short-wide windows; compact filter/search/sort/columns, inspector actions and resizing with selection; actual menu-bar opening, chart/range/metric/device controls and reopening the main window; test breakpoint geometry, chart gaps/domain/selection and priority-column rules. Package universal app; open PR with design and running-app screenshots.
