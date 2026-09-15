import SwiftUI

struct ANEOverview: View {
  @EnvironmentObject var monitor: Monitor
  let range: Int
  let theme: MonitorTheme
  var width: CGFloat = 1068
  var expanded = false
  var condensed = false
  private var dense: Bool { condensed || width < 1068 }
  private var ane: ANEHardwareSnapshot { monitor.ane }

  var body: some View {
    AdaptiveOverviewPanels(width: width, expanded: expanded, condensed: condensed, theme: theme) {
      hero
    } detail: {
      connections
    } context: {
      hardware
    }
  }
  private var hero: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Direct ANE connections").font(.system(size: 12)).foregroundStyle(theme.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(ane.connectionCount.map(String.init) ?? "—")
              .font(.system(size: dense ? 26 : 34, weight: .medium))
              .foregroundStyle(theme.text)
            Text(ane.connectionsReadable ? "open now" : "not available")
              .font(.system(size: 11)).foregroundStyle(theme.secondary)
          }
        }
        Spacer(minLength: 4)
        Image(systemName: "brain").font(.system(size: 17)).foregroundStyle(theme.blue)
      }
      TelemetryChart(
        samples: TelemetryData.samples(
          points: monitor.histories[.ane] ?? [], metric: .ane,
          maximumGap: max(10, monitor.interval * 2.5)),
        metric: .ane, range: range, end: monitor.lastUpdate ?? Date(), theme: theme)
        .padding(.top, dense ? 6 : 10)
    }.monospacedDigit()
  }
  private var connections: some View {
    VStack(alignment: .leading, spacing: dense ? 8 : 15) {
      HStack {
        Text("Observed direct-path clients").font(.system(size: 12, weight: .medium))
        DiagnosticInfoButton(title: "Direct ANE connections",
          text: "These are currently open direct-path ANE driver clients visible in the IOKit registry. A connection is not proof of active computation. Indirect work through aned and other paths may not be attributed to the initiating process. Zero visible connections does not establish zero ANE activity.", theme: theme)
      }
      row("Processes with open connections", ane.processCount.map(String.init) ?? "—")
      row("Open connections", ane.connectionCount.map(String.init) ?? "—")
      Spacer(minLength: 0)
    }
  }
  private var hardware: some View {
    VStack(alignment: .leading, spacing: dense ? 8 : 15) {
      HStack {
        Text("Neural Engine hardware").font(.system(size: 12, weight: .medium))
        DiagnosticInfoButton(title: "Neural Engine hardware",
          text: "ANE device and core counts come from optional driver registry properties. They are hardware descriptors, not capacity or utilization measurements. This collector does not report ANE power, execution time, or percentage; Apple provides detailed activity through Instruments, while powermetrics requires administrator privileges.", theme: theme)
        Spacer()
        Image(systemName: "brain").foregroundStyle(theme.tertiary)
      }
      row("ANE devices", ane.engineCount.map(String.init) ?? "—")
      row("Reported ANE cores", ane.coreCount.map(String.init) ?? "—")
      Spacer(minLength: 0)
      if !ane.available {
        Text("No Neural Engine driver data found")
          .font(.system(size: 10)).foregroundStyle(theme.tertiary)
      }
    }
  }
  private func row(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(theme.secondary)
      Spacer(minLength: 8)
      Text(value).monospacedDigit()
    }.font(.system(size: 11))
  }
}
