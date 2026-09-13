import SwiftUI

/// Let the system own segment geometry, selection, focus and toolbar material.
struct ToolbarMetricPicker: View {
  @Binding var metric: Metric
  var compact = false

  var body: some View {
    Picker("Metric", selection: $metric) {
      ForEach(Metric.allCases) { item in
        Group {
          if compact {
            Image(systemName: item.icon).accessibilityLabel(item.rawValue)
          } else {
            Text(item.rawValue)
          }
        }
        .tag(item)
        .accessibilityLabel(item.rawValue)
        .help("\(item.rawValue) · ⌘\(Metric.allCases.firstIndex(of: item)! + 1)")
        .accessibilityIdentifier("monitor-metric-\(item.rawValue)")
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.regular)
    .labelsHidden()
    // Reserve a compact toolbar width and refresh the native picker's intrinsic
    // size when switching between text and icons during a window resize.
    .frame(width: compact ? 210 : nil)
    .fixedSize()
    .id(compact)
    .accessibilityIdentifier("monitor-metric-picker")
  }
}

/// A single surface extends behind native toolbar controls and the workspace.
struct MonitorWindowBackground: ViewModifier {
  let theme: MonitorTheme

  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      content
        .containerBackground(theme.window, for: .window)
        .toolbarBackground(.hidden, for: .windowToolbar)
    } else {
      content
        .toolbarBackground(theme.window, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }
  }
}
