# Version 1.5.0 measurements

Measured September 10, 2026 on macOS 26.6, Apple M3 Pro, release builds. The same retained fixture was run sequentially against v1.4.1 and the optimized source. The baseline uses only an initializer compatibility flag; production code is unchanged. Raw samples are in [1.4.1](v1.4.1-comparison.json) and [1.5.0](v1.5.0-results.json).

| Benchmark | 1.4.1 median | 1.5.0 median | Change |
| --- | ---: | ---: | ---: |
| chart.CPU.15min | 54.11 ms | 5.38 ms | -90.1% |
| chart.Memory.15min | 141.18 ms | 3.39 ms | -97.6% |
| chart.Energy.15min | 28.49 ms | 3.29 ms | -88.4% |
| chart.Disk.15min | 57.52 ms | 3.25 ms | -94.3% |
| chart.Network.15min | 54.11 ms | 3.13 ms | -94.2% |
| chart.GPU.15min | 29.09 ms | 2.81 ms | -90.3% |
| workspace.1000 | 709.23 ms | 355.86 ms | -49.8% |
| gallery.1000 | 347.66 ms | 106.99 ms | -69.2% |
| query.all_views.1000 | 9.32 ms | 0.65 ms | -93.1% |
| format.all_columns.1000 | 23.53 ms | 23.31 ms | -0.9% |
| table.scroll.layout.1000 | 5.72 ms | 4.70 ms | -17.8% |
| table.refresh.layout.1000 | 35.52 ms | 15.07 ms | -57.6% |
| startup.models | 0.11 ms | 0.01 ms | -89.4% |
| inspector | 18.57 ms | 15.96 ms | -14.1% |
| popover | 76.00 ms | 40.72 ms | -46.4% |

These are local observations on a busy development Mac, not cross-hardware guarantees. Offscreen chart/workspace/gallery/inspector/popover rendering includes software rasterization; it does not measure display FPS. Model construction excludes launching the process or displaying its first window. The live first-populated-snapshot correctness gate also passed in 0.031 seconds in a separate run; that is warm system telemetry collection, not whole-app cold launch.

Scroll layout p95 changed from 15.69 to 7.15 ms. Refresh median changed from 35.52 to 15.07 ms and p95 from 97.38 to 20.44 ms. The new viewport bounds the number of materialized rows, including after large jumps, instead of relying on an unconstrained lazy stack. Earlier candidate runs varied from 6–10 ms median scroll layout and 19–23 ms refresh layout; the final pair is not a guarantee that every frame will be faster. Formatting remains broadly similar. The table retains every measurement, including regressions if present.

The warmed scroll/refresh physical footprint changed from 232.2 to 254.8 MiB in the baseline and from 305.0 to 326.3 MiB in the optimized run. Both passed the 64 MiB growth ceiling. This is evidence of bounded growth in this scenario, not proof of a lower steady-state footprint. Allocator state, system pressure and previous raster benchmarks influence absolute values. Separate tests enforce bounded caches, icon representations, monitor lifetime and closed-popover content release.

See [performance gates](OPTIMIZATION.md) for reproducible commands, budgets, correctness contracts and interpretation limits. Intel timing and native Intel UI performance have not been measured locally.
