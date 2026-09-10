# Performance work and release gates

Scope: startup and first telemetry, scrolling and process updates, all six dashboards, chart inspection, gallery, inspector, menu-bar monitor, and bounded memory. Preserve column configuration, sorting, selection, exports, telemetry semantics, accessibility and light/dark appearances.

The deterministic fixtures in `PerformanceTests.swift` use 1,000 processes and a complete 15-minute history. Benchmarks render actual SwiftUI views into offscreen AppKit bitmaps; no screenshot automation or user processes are needed. Release mode is required. Live machine measurements supplement these tests and are not interchangeable with frame timings.

## Work sequence

1. Record release-mode and live v1.4.1 baselines.
2. Remove repeated preference decoding, sorting work and chart preparation.
3. Reduce startup work and hidden-view activity; bound caches and telemetry memory.
4. Exercise rendering, refresh, resizing and scrolling in retained headless tests and native UI checks.
5. Establish measured regression budgets, wire them into CI, and retain raw results.
6. Review the complete change, merge, package, release and verify local installation.

Final budgets and measured results will be recorded here before release. Do not treat an implementation-only microbenchmark as proof of smooth scrolling or startup latency.
