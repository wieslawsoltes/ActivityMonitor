import SwiftUI

struct DesignGallery: View {
  @EnvironmentObject var monitor: Monitor
  let select: (Metric, String) -> Void
  let close: () -> Void
  @State private var previewRows: [ProcessRow] = []
  @State private var gpuRows: [ProcessRow] = []
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 7) {
            Text("ACTIVITY MONITOR / DESIGN COLLECTION").font(.system(size: 9, weight: .semibold))
              .tracking(1.8).foregroundStyle(Color(hex: 0x4086f7))
            Text("Six perspectives. Two appearances.").font(.system(size: 20, weight: .semibold))
              .tracking(-0.8)
            Text("Live previews. Choose a view and appearance to open it.").font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Back to monitor", action: close).buttonStyle(.bordered)
        }.padding(28)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            ForEach(Metric.allCases) { metric in
              VStack(alignment: .leading, spacing: 10) {
                Text(metric.rawValue).font(.system(size: 15, weight: .semibold))
                LazyVGrid(
                  columns: [
                    GridItem(.adaptive(minimum: min(320, max(280, geometry.size.width - 56))))
                  ], spacing: 18
                ) {
                  preview(
                    metric, false,
                    width: geometry.size.width < 740
                      ? geometry.size.width - 56 : (geometry.size.width - 74) / 2)
                  preview(
                    metric, true,
                    width: geometry.size.width < 740
                      ? geometry.size.width - 56 : (geometry.size.width - 74) / 2)
                }
              }
            }
          }.padding(28)
        }
      }
    }.frame(
      width: min(1080, max(390, (NSApp.mainWindow?.frame.width ?? 1130) - 30)),
      height: min(760, max(430, (NSApp.mainWindow?.frame.height ?? 800) - 30))
    )
    .onReceive(monitor.$rows) { rows in
      gpuRows = Array(
        ProcessQuery(
          metric: .gpu, query: "", filter: "All processes", sort: "primary", descending: true
        ).apply(rows).prefix(3))
      previewRows = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(3))
    }
  }
  func preview(_ metric: Metric, _ dark: Bool, width: CGFloat) -> some View {
    let theme = MonitorTheme(dark: dark)
    return Button {
      select(metric, dark ? "Dark" : "Light")
    } label: {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            BrandMark(size: 16)
            Text("Activity Monitor").font(.system(size: 8, weight: .semibold))
            Spacer()
            Text(metric.rawValue).font(.system(size: 8)).padding(4).background(
              theme.card, in: RoundedRectangle(cornerRadius: 4))
          }
          MonitorOverview(metric: metric, range: 1, theme: theme).environmentObject(monitor).frame(
            width: 1260, height: 213
          ).scaleEffect((width - 28) / 1260, anchor: .topLeading).frame(
            width: width - 28, height: 213 * (width - 28) / 1260, alignment: .topLeading)
          VStack(spacing: 0) {
            ForEach(
              Array((metric == .gpu ? gpuRows : previewRows).enumerated()),
              id: \.element.id
            ) { index, p in
              HStack {
                Text(p.name).lineLimit(1)
                Spacer()
                Text(
                  metric == .gpu
                    ? gpuPercent(p.gpuPercent) + "% GPU" : String(format: "%.1f%% CPU", p.cpu))
                Text(p.accessible ? bytes(p.memory) : "—").frame(width: 58, alignment: .trailing)
              }.font(.system(size: 8)).foregroundStyle(theme.secondary).padding(7).background(
                index % 2 == 0 ? theme.card : theme.subtle)
            }
          }.clipShape(RoundedRectangle(cornerRadius: 5))
        }.padding(14).background(theme.window)
        GalleryFooter(metric: metric, dark: dark, theme: theme)

      }.foregroundStyle(theme.text).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(
        RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }.buttonStyle(.plain)
  }
}

private struct GalleryFooter: View {
  let metric: Metric
  let dark: Bool
  let theme: MonitorTheme
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack {
      Label(
        metric.rawValue + " / " + (dark ? "Dark" : "Light"), systemImage: dark ? "moon" : "sun.max")
      Spacer()
      Image(systemName: "arrow.right")
    }.font(.system(size: 11)).foregroundStyle(theme.secondary).padding(12)
      .background(hovering ? theme.hover : theme.card)
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
  }
}
