import SwiftUI

/// Keep the familiar tab appearance while fitting the compact native title bar.
struct ToolbarMetricPicker: View {
  @Binding var metric: Metric
  let theme: MonitorTheme
  var compact = false

  var body: some View {
    MetricSwitcher(metric: $metric, theme: theme, compact: compact, controlHeight: 26)
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
