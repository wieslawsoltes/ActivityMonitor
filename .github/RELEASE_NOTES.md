Native SwiftUI Activity Monitor for macOS 14 or later, with CPU, memory, energy, disk and network views, light/dark themes, process inspection, search, sorting, diagnostics and CSV/JSON export.

### Install

Download the **universal DMG**, open it, and drag **Activity Monitor** to **Applications**. The **universal ZIP** contains the complete `.app` bundle as an alternative. Both support Apple silicon and Intel. `SHA256SUMS` verifies the download contents; `INSTALL.md` contains installation details.

This release is **ad-hoc signed, not Apple notarized**. After trying to open a downloaded copy, macOS may require **System Settings → Privacy & Security → Open Anyway**. Only proceed if you trust this source. No administrator helper is installed.

Metrics use live macOS data. Protected counters, Apple's proprietary Energy Impact, GPU accounting and per-process packet counts are explicitly unavailable. See the repository README for measurement semantics.
