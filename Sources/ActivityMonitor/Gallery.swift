import SwiftUI

/// Two appearances share one sizing contract between the grid and its cards.
struct GalleryLayout {
  let width: CGFloat
  static let inset: CGFloat = 28
  static let spacing: CGFloat = 18
  static let minimumCardWidth: CGFloat = 320
  var contentWidth: CGFloat { max(0, width - Self.inset * 2) }
  var columnCount: Int { contentWidth >= Self.minimumCardWidth * 2 + Self.spacing ? 2 : 1 }
  var cardWidth: CGFloat {
    (contentWidth - CGFloat(columnCount - 1) * Self.spacing) / CGFloat(columnCount)
  }
}

struct DesignGallery: View {
  @EnvironmentObject var monitor: Monitor
  let availableSize: CGSize
  let select: (Metric, String) -> Void
  let close: () -> Void
  @State private var previewRows: [ProcessRow] = []
  @State private var gpuRows: [ProcessRow] = []
  var body: some View {
    GeometryReader { geometry in
      let layout = GalleryLayout(width: geometry.size.width)
      VStack(spacing: 0) {
        header(compact: geometry.size.width < 600).padding(GalleryLayout.inset)
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(Metric.allCases) { metric in
              VStack(alignment: .leading, spacing: 10) {
                Text(metric.rawValue).font(.system(size: 15, weight: .semibold))
                LazyVGrid(
                  columns: Array(
                    repeating: GridItem(
                      .fixed(layout.cardWidth), spacing: GalleryLayout.spacing, alignment: .top),
                    count: layout.columnCount),
                  alignment: .leading, spacing: GalleryLayout.spacing
                ) {
                  preview(metric, false, width: layout.cardWidth)
                  preview(metric, true, width: layout.cardWidth)
                }
              }
            }
          }.padding(GalleryLayout.inset)
        }
      }
    }.frame(
      width: min(1080, max(390, availableSize.width - 30)),
      height: min(760, max(430, availableSize.height - 30))
    )
    .onReceive(monitor.$rows) { rows in
      gpuRows = Array(
        ProcessQuery(
          metric: .gpu, query: "", filter: "All processes", sort: "primary", descending: true
        ).apply(rows, limit: 3))
      previewRows = ProcessQuery(
        metric: .cpu, query: "", filter: "All processes",
        sort: "primary", descending: true
      ).apply(rows, limit: 3)
    }
  }
  private var introduction: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("ACTIVITY MONITOR / DESIGN COLLECTION").font(.system(size: 9, weight: .semibold))
        .tracking(1.8).foregroundStyle(Color(hex: 0x4086f7))
      Text("Six perspectives. Two appearances.").font(.system(size: 20, weight: .semibold))
        .tracking(-0.8)
      Text("Live previews. Choose a view and appearance to open it.").font(.system(size: 12))
        .foregroundStyle(.secondary)
    }.fixedSize(horizontal: false, vertical: true)
  }
  private var backButton: some View {
    Button("Back to monitor", action: close).buttonStyle(.bordered).keyboardShortcut(.cancelAction)
  }
  @ViewBuilder private func header(compact: Bool) -> some View {
    if compact {
      VStack(alignment: .leading, spacing: 14) {
        introduction
        backButton
      }.frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack {
        introduction
        Spacer(minLength: 18)
        backButton
      }
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
          MonitorOverview(metric: metric, range: 1, theme: theme, width: 1260).environmentObject(
            monitor
          ).frame(
            width: 1260, height: 213
          ).scaleEffect((width - 28) / 1260, anchor: .topLeading).frame(
            width: width - 28, height: 213 * (width - 28) / 1260, alignment: .topLeading
          )
          .clipped().disabled(true).allowsHitTesting(false).accessibilityHidden(true)
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

      }.frame(width: width, alignment: .topLeading).foregroundStyle(theme.text).clipShape(
        RoundedRectangle(cornerRadius: 12)
      ).overlay(
        RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))
    }.buttonStyle(.plain).frame(width: width, alignment: .topLeading)
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("\(metric.rawValue), \(dark ? "Dark" : "Light") appearance")
      .accessibilityHint("Open this view in the monitor")
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
