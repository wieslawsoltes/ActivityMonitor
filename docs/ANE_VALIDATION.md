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
