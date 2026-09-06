import SwiftUI

struct DesignGallery: View {
  @EnvironmentObject var monitor: Monitor
  let select: (Metric, String) -> Void
  let close: () -> Void
  @State private var previewRows: [ProcessRow] = []
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Text("ACTIVITY MONITOR / DESIGN COLLECTION").font(.system(size: 9, weight: .semibold))
            .tracking(1.8).foregroundStyle(Color(hex: 0x4086f7))
          Text("Five perspectives. Two appearances.").font(.system(size: 26, weight: .semibold))
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
              HStack(spacing: 18) {
                preview(metric, false)
                preview(metric, true)
              }
            }
          }
        }.padding(28)
      }
    }.frame(width: 1080, height: 760)
      .onReceive(monitor.$rows) { rows in
        previewRows = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(3))
      }
  }
  func preview(_ metric: Metric, _ dark: Bool) -> some View {
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
          ).scaleEffect(0.365, anchor: .topLeading).frame(
            width: 460, height: 78, alignment: .topLeading)
          VStack(spacing: 0) {
            ForEach(
              Array(previewRows.enumerated()),
              id: \.element.id
            ) { index, p in
              HStack {
                Text(p.name).lineLimit(1)
                Spacer()
                Text(String(format: "%.1f%% CPU", p.cpu))
                Text(bytes(p.memory)).frame(width: 58, alignment: .trailing)
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
