Activity Monitor 1.3.1 fixes unwanted chart focus highlights and overlapping previews in the perspectives gallery.

### Fixed

- Charts follow macOS Keyboard navigation preferences instead of automatically taking editing focus.
- Removed the custom focus border that appeared merely because a chart received focus. The system now shows focus for intentional keyboard navigation.
- Gallery previews now fit their columns, stack in compact windows, and keep their miniature charts from intercepting input. The gallery header adapts to narrow windows, and Escape returns to the monitor.
- Pointer inspection, keyboard sample navigation, history ranges and all six monitoring views remain available in both the main window and the menu-bar monitor.

### Keyboard inspection

Enable **System Settings → Keyboard → Keyboard navigation**, then use **Tab** to reach a chart, **← / →** to inspect samples and **Escape** to clear the selection. Hover inspection works without changing any settings.

### Install

Download the **universal DMG**, open it, and drag **Activity Monitor** to **Applications**. The **universal ZIP** contains the complete app as an alternative. Both support Apple silicon and Intel on **macOS 14 or later**. `SHA256SUMS` verifies download contents; `INSTALL.md` contains installation details.

[Changes since 1.3.0](https://github.com/wieslawsoltes/ActivityMonitor/compare/v1.3.0...v1.3.1)
