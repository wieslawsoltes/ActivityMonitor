import SwiftUI

/// Width is measured in points, independent of display scale. Default geometry stays unchanged.
struct MonitorLayout: Equatable {
  let width: CGFloat
  let height: CGFloat
  var compact: Bool { width < 720 }
  var standard: Bool { width >= 1120 }
  var expanded: Bool { width >= 1600 }
  var scrollsWorkspace: Bool { !standard || height < 700 }
  var gutter: CGFloat { compact ? 14 : 26 }
  var overviewHeight: CGFloat { expanded ? 280 : 213 }
  var inspectorWidth: CGFloat { expanded ? 340 : 298 }
  var inlineInspector: Bool { width >= 1120 && height >= 700 }
}

/// A three-panel layout shared by every metric. Its geometry is also independently testable.
struct OverviewGrid: Layout {
  var expanded = false
  static func frames(width: CGFloat, expanded: Bool) -> [CGRect] {
    let width = max(0, width)
    let gap: CGFloat = 14
    let height: CGFloat = expanded ? 280 : 213
    if width >= 1068 {
      let unit = max(0, width - 2 * gap) / 3.82
      return [
        CGRect(x: 0, y: 0, width: unit * 1.82, height: height),
        CGRect(x: unit * 1.82 + gap, y: 0, width: unit, height: height),
        CGRect(x: unit * 2.82 + gap * 2, y: 0, width: unit, height: height),
      ]
    }
    if width >= 668 {
      let half = max(0, width - gap) / 2
      return [
        CGRect(x: 0, y: 0, width: width, height: height),
        CGRect(x: 0, y: height + gap, width: half, height: 213),
        CGRect(x: half + gap, y: height + gap, width: half, height: 213),
      ]
    }
    return (0..<3).map {
      CGRect(x: 0, y: CGFloat($0) * (height + gap), width: width, height: height)
    }
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 1068
    let frames = Self.frames(width: width, expanded: expanded)
    return CGSize(width: width, height: frames.last?.maxY ?? 0)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (view, frame) in zip(subviews, Self.frames(width: bounds.width, expanded: expanded)) {
      view.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
  }
}

struct AdaptiveOverviewPanels<Hero: View, Detail: View, Context: View>: View {
  let width: CGFloat
  let expanded: Bool
  let theme: MonitorTheme
  @ViewBuilder let hero: Hero
  @ViewBuilder let detail: Detail
  @ViewBuilder let context: Context
  @State private var details = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    if width < 668 {
      VStack(spacing: 10) {
        DesignCard(theme: theme, padding: 19) { hero }.frame(height: 213)
        DisclosureGroup("Breakdown & device details", isExpanded: $details) {
          VStack(spacing: 14) {
            DesignCard(theme: theme) { detail }.frame(height: 213)
            DesignCard(theme: theme) { context }.frame(height: 213)
          }.padding(.top, 12)
        }.font(.system(size: 12, weight: .medium)).tint(theme.blue)
          .padding(.horizontal, 4)
          .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: details)
      }
    } else {
      OverviewGrid(expanded: expanded) {
        DesignCard(theme: theme, padding: 19) { hero }
        DesignCard(theme: theme) { detail }
        DesignCard(theme: theme) { context }
      }
    }
  }
}

struct MetricSwitcher: View {
  @Binding var metric: Metric
  let theme: MonitorTheme
  var compact = false
  var body: some View {
    HStack(spacing: 3) {
      ForEach(Metric.allCases) { item in
        Button {
          metric = item
        } label: {
          HStack(spacing: 7) {
            Image(systemName: item.icon).font(.system(size: 13))
              .foregroundStyle(item == metric ? theme.blue : theme.secondary)
            if !compact { Text(item.rawValue).font(.system(size: 13, weight: .medium)) }
          }.frame(maxWidth: compact ? .infinity : nil).padding(.horizontal, compact ? 0 : 10)
            .frame(height: 34)
        }.buttonStyle(MonitorSegmentButton(theme: theme, active: item == metric))
          .accessibilityLabel(item.rawValue).accessibilityAddTraits(
            item == metric ? .isSelected : []
          )
          .help("\(item.rawValue) · ⌘\(Metric.allCases.firstIndex(of: item)! + 1)")
      }
    }.padding(4).background(theme.recessed, in: RoundedRectangle(cornerRadius: 11))
      .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.separator, lineWidth: 1))
  }
}
struct HistoryRangePicker: View {
  @Binding var range: Int
  let theme: MonitorTheme
  var body: some View {
    HStack(spacing: 2) {
      ForEach([1, 5, 15], id: \.self) { value in
        Button {
          range = value
        } label: {
          Text("\(value) min").font(.system(size: 10)).frame(width: 44, height: 24)
        }.buttonStyle(MonitorSegmentButton(theme: theme, active: range == value, radius: 5))
          .accessibilityAddTraits(range == value ? .isSelected : [])
      }
    }.padding(3).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
  }
}
struct GPUDevicePicker: View {
  @EnvironmentObject var monitor: Monitor
  let theme: MonitorTheme
  var body: some View {
    Menu {
      if monitor.gpuDevices.isEmpty { Text("No GPU detected") }
      ForEach(monitor.gpuDevices) { device in
        Button {
          monitor.selectedGPU = device.id
        } label: {
          if monitor.gpuDevice?.id == device.id {
            Label(
              device.name + (device.connected ? "" : " · disconnected"), systemImage: "checkmark")
          } else {
            Text(device.name + (device.connected ? "" : " · disconnected"))
          }
        }
      }
    } label: {
      Label(monitor.gpuDevice?.name ?? "No GPU detected", systemImage: "square.3.layers.3d")
        .font(.system(size: 11)).lineLimit(1).foregroundStyle(theme.secondary)
    }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
      .help("Choose GPU for the overview; process counters include all reporting devices")
  }
}
