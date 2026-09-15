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
    ANEProfileSummary(profiler: monitor.aneProfiler, theme: theme, dense: dense)
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
          text: "ANE device and core counts come from optional driver registry properties. They are hardware descriptors, not capacity or utilization measurements. A short Instruments profile can measure system-wide ANE activity intervals, but no live per-process or per-core ANE utilization API is available here. powermetrics requires administrator privileges.", theme: theme)
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

private struct ANEProfileSummary: View {
  @ObservedObject var profiler: ANEProfileController
  let theme: MonitorTheme
  let dense: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: dense ? 7 : 11) {
      HStack(spacing: 5) {
        Text("Neural Engine activity").font(.system(size: 12, weight: .medium))
          .foregroundStyle(theme.secondary)
        DiagnosticInfoButton(title: "Measured ANE activity",
          text: "Capture records five seconds of system-wide Neural Engine activity using Xcode Instruments. The percentage is the share of recording time covered by ANE active intervals, not hardware utilization or core occupancy. Prediction timing is measured from ANE hardware intervals; events cannot be attributed to individual processes. This capture runs only when requested and removes its temporary trace afterward. Xcode is required and its export format may vary by version.", theme: theme)
        Spacer(minLength: 4)
        Button {
          profiler.capture()
        } label: {
          Label("Capture 5 s", systemImage: "record.circle")
            .font(.system(size: 11, weight: .medium))
        }.buttonStyle(.bordered).controlSize(.small)
          .disabled(profiler.isCapturing)
          .accessibilityIdentifier("ane-capture-profile")
      }
      if profiler.isCapturing {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Recording and analyzing…")
            .font(.system(size: 12)).foregroundStyle(theme.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      } else if let result = profiler.result {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(String(format: "%.1f", result.observedActivityPercent))
            .font(.system(size: dense ? 26 : 34, weight: .medium))
            .foregroundStyle(theme.text)
          Text("% observed activity")
            .font(.system(size: 11)).foregroundStyle(theme.secondary)
        }.monospacedDigit()
        HStack(spacing: dense ? 14 : 24) {
          statistic("ANE predictions", "\(result.predictionCount)")
          statistic("Mean interval", result.averagePredictionMilliseconds.map {
            String(format: "%.2f ms", $0)
          } ?? "—")
          statistic("Recorded", String(format: "%.1f s", result.durationSeconds))
        }
        Text("System-wide sample · \(result.recordedAt.formatted(date: .omitted, time: .shortened))")
          .font(.system(size: 10)).foregroundStyle(theme.tertiary)
      } else {
        Text("Capture a short ANE activity profile")
          .font(.system(size: 13)).foregroundStyle(theme.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
      if let error = profiler.error {
        Text(error).font(.system(size: 10)).foregroundStyle(theme.coral).lineLimit(2)
      }
    }
  }
  private func statistic(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text)
      Text(label).font(.system(size: 10)).foregroundStyle(theme.tertiary)
    }.monospacedDigit()
  }
}
