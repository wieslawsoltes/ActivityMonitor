import AppKit
import SwiftUI

struct MonitorDestination {
  var metric: Metric
  var range: Int
  var pid: Int32?
}
@MainActor final class MonitorNavigation: ObservableObject {
  @Published var request: MonitorDestination?
}

@MainActor final class MenuBarPresentation: ObservableObject {
  @Published var metric: Metric = .cpu
  @Published var range = 1
  let cpuCharts = CPUChartPresentation()
}
struct MenuBarMonitor: View {
  @EnvironmentObject var monitor: Monitor
  @EnvironmentObject var navigation: MonitorNavigation
  var openMonitor: () -> Void
  var closePopover: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @AppStorage("appearance") private var appearance = "System"
  @ObservedObject var presentation: MenuBarPresentation
  private var metric: Metric { presentation.metric }
  private var range: Int { presentation.range }
  @State private var top: [ProcessRow] = []
  private var theme: MonitorTheme {
    MonitorTheme(dark: appearance == "Dark" || appearance == "System" && colorScheme == .dark)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        BrandMark(size: 26)
        VStack(alignment: .leading, spacing: 2) {
          Text("Activity Monitor").font(.system(size: 13, weight: .semibold))
          Text(monitor.paused ? "Monitoring paused" : "Live system data")
            .font(.system(size: 10)).foregroundStyle(theme.secondary)
        }
        Spacer()
        Button {
          monitor.paused.toggle()
        } label: {
          Image(systemName: monitor.paused ? "play" : "pause")
        }
        .buttonStyle(MonitorIconButton(theme: theme)).help(
          monitor.paused ? "Resume monitoring" : "Pause monitoring")
        SettingsMenuButton(
          size: 28, accessibilityLabel: "Monitor settings", toolTip: "Monitor settings"
        ) {
          let menu = NSMenu()
          menu.addAppearance($appearance)
          menu.addUpdateInterval($monitor.interval)
          menu.addItem(.separator())
          menu.addSettingsAction("Quit Activity Monitor") { NSApp.terminate(nil) }
          return menu
        }
        .frame(width: 28, height: 28)
      }.padding(16)
      MetricSwitcher(metric: $presentation.metric, theme: theme, compact: true).padding(
        .horizontal, 14)
      ScrollView {
        VStack(spacing: 10) {
          HStack {
            if metric == .gpu {
              GPUDevicePicker(theme: theme)
            } else {
              Label(metric.rawValue, systemImage: metric.icon).font(
                .system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 4)
            HistoryRangePicker(range: $presentation.range, theme: theme)
          }
          MonitorOverview(
            metric: metric, range: range, theme: theme, width: 392,
            cpuPresentation: presentation.cpuCharts)
          VStack(spacing: 0) {
            HStack {
              Text(metric == .energy ? "Top applications" : "Top processes").font(
                .system(size: 12, weight: .semibold))
              Spacer()
              Text(primaryTitle).font(.system(size: 10)).foregroundStyle(theme.secondary)
            }.padding(.bottom, 8)
            ForEach(top) { process in
              Button {
                show(process.id)
              } label: {
                HStack(spacing: 9) {
                  ProcessIcon(pid: process.id, isApp: process.isApp, start: process.start, size: 22)
                  Text(process.name).lineLimit(1).truncationMode(.middle)
                  Spacer(minLength: 4)
                  Text(primaryValue(process)).foregroundStyle(theme.blue).monospacedDigit()
                }.font(.system(size: 11)).padding(.vertical, 9).contentShape(Rectangle())
              }.buttonStyle(MonitorSegmentButton(theme: theme, radius: 5))
                .help("Inspect \(process.name) in Activity Monitor")
              Rectangle().fill(theme.separator).frame(height: 1)
            }
            if top.isEmpty {
              Text("Waiting for processes").foregroundStyle(theme.secondary).padding()
            }
            if metric == .gpu {
              Text("Process counters cover all reporting GPUs.").font(.system(size: 10))
                .foregroundStyle(theme.secondary).padding(.top, 8)
            }
          }.padding(.horizontal, 4)
        }.padding(14)
      }
      HStack {
        Button {
          show(nil)
        } label: {
          Label("Open Activity Monitor", systemImage: "arrow.up.forward.app")
            .frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).tint(theme.blue).controlSize(.large)
      }.padding(14).background(theme.toolbar)
    }.frame(
      width: 420, height: max(400, min(690, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
    )
    .background(theme.window).foregroundStyle(theme.text)
    .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
    .onReceive(monitor.$rows) { updateTop($0) }
    .onChange(of: metric) { updateTop(monitor.rows) }
  }
  private var primaryTitle: String {
    switch metric {
    case .cpu: return "% CPU"
    case .memory: return "Memory"
    case .gpu: return "% GPU"
    case .energy: return "CPU workload"
    case .disk: return "Bytes written"
    case .network: return "Bytes received"
    }
  }
  private func primaryValue(_ p: ProcessRow) -> String {
    switch metric {
    case .cpu, .energy: return p.accessible ? String(format: "%.1f%%", p.cpu) : "—"
    case .memory: return p.accessible ? bytes(p.memory) : "—"
    case .gpu: return p.gpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    case .disk: return p.ioAccessible ? bytes(p.written) : "—"
    case .network: return p.networkReceived.map(bytes) ?? "—"
    }
  }
  private func updateTop(_ rows: [ProcessRow]) {
    top = Array(
      ProcessQuery(
        metric: metric, query: "", filter: metric == .energy ? "Applications" : "All processes",
        sort: metric == .network ? "received" : "primary", descending: true
      ).apply(rows, limit: 5))
  }
  private func show(_ pid: Int32?) {
    navigation.request = MonitorDestination(metric: metric, range: range, pid: pid)
    closePopover()
    openMonitor()
  }
}

/// Template image stays legible against either system menu-bar appearance.
enum MenuBarGlyph {
  static func image(_ points: [Point], paused: Bool) -> NSImage {
    let values = Array(points.suffix(18)).map { min(100, max(0, $0.a + $0.b)) }
    let image = NSImage(size: NSSize(width: 28, height: 18), flipped: false) { bounds in
      NSColor.labelColor.setStroke()
      let path = NSBezierPath()
      path.lineWidth = 1.5
      path.lineJoinStyle = .round
      for (index, value) in values.enumerated() {
        let point = NSPoint(
          x: 1 + CGFloat(index) / CGFloat(max(1, values.count - 1)) * 25,
          y: 2 + CGFloat(value) / 100 * 13)
        if index == 0 { path.move(to: point) } else { path.line(to: point) }
      }
      if values.count < 2 {
        path.move(to: NSPoint(x: 1, y: 3))
        path.line(to: NSPoint(x: 26, y: 3))
      }
      path.stroke()
      if paused {
        NSColor.labelColor.setFill()
        NSRect(x: 21, y: 11, width: 2, height: 5).fill()
        NSRect(x: 25, y: 11, width: 2, height: 5).fill()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
