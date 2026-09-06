Activity Monitor 1.1 improves everyday navigation and process-table performance.

### Improvements

- Click anywhere inside a tab, appearance selector or history-range button.
- Switch views with less redundant sorting, application lookup and process-row layout.
- Clear hover and press feedback on tabs, toolbar controls and inspector actions; a visible search-focus outline.
- Consistent selection behavior for mouse, keyboard and view-gallery navigation.

[Light and dark screenshots](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.1.0/docs/screenshots/README.md) · [Profiling results and methodology](https://github.com/wieslawsoltes/ActivityMonitor/blob/v1.1.0/docs/performance/README.md)

### Install

Download the **universal DMG**, open it, and drag **Activity Monitor** to **Applications**. The **universal ZIP** contains the complete `.app` bundle as an alternative. Both support Apple silicon and Intel on macOS 14 or later. `SHA256SUMS` verifies download contents; `INSTALL.md` contains installation details.

This release is **ad-hoc signed, not Apple notarized**. After trying to open a downloaded copy, macOS may require **System Settings → Privacy & Security → Open Anyway**. Only proceed if you trust this source. No administrator helper is installed.

Metrics use live macOS data. Protected counters, Apple's proprietary Energy Impact, GPU accounting and per-process packet counts are explicitly unavailable. See the repository README for measurement semantics.
