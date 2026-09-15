# ANE validation

September 15, 2026 · Apple M3 Pro · macOS 26.6.

`ioreg` showed `H11ANEIn` with `ANEDevicePropertyNumANECores = 16` and
`H1xANELoadBalancer` with `ANEDevicePropertyNumANEs = 1`. Two
`H1xANELoadBalancerDirectPathClient` descendants exposed `IOUserClientCreator`
PIDs. A separate load-balancer client belonged to `aned`; it was excluded from
the per-process count. The read-only collector reported **one device, 16 cores,
two direct connections, two processes** on the same machine.

Reproduce without administrator rights:

```sh
swiftc Sources/ActivityMonitor/ANECollector.swift scripts/ane-probe.swift \
  -framework IOKit -o /tmp/activity-monitor-ane-probe
/tmp/activity-monitor-ane-probe
```

Connections reflect driver contexts, not currently running inference. Neither
`H11ANEIn` nor the load-balancer properties observed here exposed execution time
or utilization. `powermetrics -s ane_power` required superuser access. The
Core ML/Neural Engine Instruments are Apple’s supported way to profile model
activity. No physical validation on another Apple silicon generation has been
performed; class names and property availability can differ.

## On-demand activity profile

The ANE overview can now record a five-second, all-processes **Core ML**
Instruments trace when Xcode's `xctrace` is installed. It exports the Neural
Engine hardware intervals, then removes the trace. The app reports the union
of active interval wall time as a share of recording duration, the count of
hardware `Prediction` intervals, and their mean duration. These are measured
intervals, not ANE compute-capacity utilization; the intervals carry no stable
process attribution. Recording is explicitly requested by the user because
the Core ML template also collects other system profiling data and can take
time and temporary disk space to finish.
The end-to-end five-second recording path took about 43 seconds and used
roughly 138 MB of temporary disk space on this machine; the temporary directory
was removed after export.

On this M3 Pro, a targeted 1.904-second Instruments recording of 100 Vision
image-classification requests produced 100 Neural Engine `Prediction` intervals
and one `Load` interval. The exported `ane-hw-intervals-internal` table uses
repeated XML `ref` identifiers, which the parser resolves. A five-second idle
all-processes recording exported the same schema with no rows, which the UI
reports as no observed activity during that recording. The parser's supported
schema is specific to the installed Instruments version; if it changes, the
feature shows an explicit unavailable error instead of a fabricated number.

Validate a recorded export with:

```sh
AM_ANE_PROFILE_TOC=/absolute/path/toc.xml \
AM_ANE_PROFILE_INTERVALS=/absolute/path/intervals.xml \
swift test --filter ANEProfilerTests/testLocalInstrumentsExportWhenSupplied
```

This local capture does not establish availability on Macs without Xcode or
other Xcode/Instruments versions. No supported live ANE-utilization or
arbitrary-process inference-time counter was found in the OS interfaces
investigated here.
