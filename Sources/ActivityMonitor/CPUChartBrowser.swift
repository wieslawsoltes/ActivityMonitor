import SwiftUI

struct CPUChartModePicker: View {
  @Binding var individual: Bool
  var threads = false
  let theme: MonitorTheme
  var body: some View {
    Menu {
      Picker("CPU chart", selection: $individual) {
        Text("One chart").tag(false)
        Text(threads ? "Individual threads" : "Logical processors").tag(true)
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: individual ? "square.grid.2x2" : "chart.xyaxis.line")
        Text(individual ? (threads ? "Threads" : "Processors") : "One chart")
      }.font(.system(size: 10, weight: .medium)).foregroundStyle(theme.secondary)
        .padding(.horizontal, 8).frame(height: 27).background(
          theme.subtle, in: RoundedRectangle(cornerRadius: 6))
    }.menuStyle(.borderlessButton).fixedSize().help("CPU chart display")
  }
}
struct CPUChartBrowser: View {
  let series: [CPUUsageSeries]
  let range: Int
  let end: Date
  let theme: MonitorTheme
  var threads = false
  var status: String? = nil
  @State private var query = ""
  @State private var page = 0
  @State private var inspected: String?
  private let pageSize = 12
  private var filtered: [CPUUsageSeries] {
    series.filter {
      query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query)
    }
  }
  private var currentPage: Int { min(page, max(0, (filtered.count - 1) / pageSize)) }
  private var visible: [CPUUsageSeries] {
    Array(filtered.dropFirst(currentPage * pageSize).prefix(pageSize))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(
          filtered.isEmpty
            ? "0 \(threads ? "threads" : "processors")"
            : "\(currentPage * pageSize + 1)–\(min((currentPage + 1) * pageSize, filtered.count)) of \(filtered.count)"
        )
        .font(.system(size: 10)).foregroundStyle(theme.secondary).monospacedDigit()
        Spacer(minLength: 0)
        TextField(threads ? "Find thread" : "Find processor", text: $query)
          .textFieldStyle(.plain).font(.system(size: 10)).padding(6).frame(width: 110)
          .background(theme.subtle, in: RoundedRectangle(cornerRadius: 5))
          .accessibilityLabel(threads ? "Find thread" : "Find processor")
        Button {
          page = max(0, currentPage - 1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(currentPage == 0).help("Previous charts")
        Button {
          page = currentPage + 1
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled((currentPage + 1) * pageSize >= filtered.count).help("Next charts")
      }.buttonStyle(.plain)
      if visible.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "cpu").font(.system(size: 24, weight: .light))
          Text(query.isEmpty ? status ?? "Waiting for processor samples" : "No matching charts")
            .font(.system(size: 11)).multilineTextAlignment(.center)
        }.foregroundStyle(theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        GeometryReader { geometry in
          let columns = min(6, max(1, Int(geometry.size.width / 190)))
          let rows = max(1, (visible.count + columns - 1) / columns)
          let chartHeight = max(
            36, min(160, (geometry.size.height - Double(rows - 1) * 10) / Double(rows) - 52))
          ScrollView {
            LazyVGrid(
              columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: columns), spacing: 10
            ) {
              ForEach(visible) { item in
                Button {
                  inspected = item.id
                } label: {
                  CPUChartTile(
                    series: item, range: range, end: end, theme: theme, threads: threads,
                    chartHeight: chartHeight)
                }.buttonStyle(.plain)
                  .help("Inspect \(item.title) · \(item.detail)")
                  .popover(
                    isPresented: Binding(
                      get: { inspected == item.id }, set: { if !$0 { inspected = nil } })
                  ) {
                    CPUChartInspection(
                      series: series.first { $0.id == item.id } ?? item,
                      range: range, end: end, theme: theme, threads: threads)
                  }
              }
            }.padding(1)
          }
        }
      }
      if threads, series.count > CPUHistoryStore.pointBudget / 901 {
        Text("History is shortened for large thread counts to limit memory use.")
          .font(.system(size: 10)).foregroundStyle(theme.secondary)
      }
      if let status, !visible.isEmpty {
        Text(status).font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(2).help(
          status)
      }
    }.onChange(of: query) { page = 0 }
      .onChange(of: series.map(\.id)) { _, ids in
        if let inspected, !ids.contains(inspected) { self.inspected = nil }
      }
  }
}
private struct CPUChartTile: View {
  let series: CPUUsageSeries
  let range: Int
  let end: Date
  let theme: MonitorTheme
  let threads: Bool
  var chartHeight: CGFloat = 36
  @State private var hovering = false
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Text(series.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        Spacer(minLength: 0)
        Text(series.latest.map { String(format: "%.1f%%", $0) } ?? "—")
          .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(theme.blue)
      }
      Text(
        series.detail.isEmpty ? (threads ? "Unnamed thread" : "Logical processor") : series.detail
      )
      .font(.system(size: 9)).foregroundStyle(theme.secondary).lineLimit(1)
      let start = end.addingTimeInterval(Double(-range * 60))
      let samples = CPUChartData.samples(series, since: start)
      let maximum = CPUChartData.maximum(series, since: start, threads: threads)
      Canvas { context, size in
        for trace in TelemetryTrace.make(samples) {
          let points = trace.coordinates(
            size: size, start: start, end: end, domain: 0...maximum, stepped: false)
          guard let first = points.first else { continue }
          var line = Path()
          line.move(to: first)
          for point in points.dropFirst() { line.addLine(to: point) }
          var area = line
          area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
          area.addLine(to: CGPoint(x: first.x, y: size.height))
          area.closeSubpath()
          let color = trace.samples.first?.series == 0 ? theme.blue : theme.coral
          context.fill(area, with: .color(color.opacity(0.12)))
          context.stroke(line, with: .color(color), lineWidth: 1)
        }
      }.frame(height: chartHeight).accessibilityHidden(true)
    }.padding(9).background(
      hovering ? theme.hover : theme.subtle, in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    .onHover { hovering = $0 }
    .accessibilityElement(children: .ignore).accessibilityLabel(series.title + ", " + series.detail)
    .accessibilityValue(
      series.latest.map { String(format: "%.1f percent", $0) } ?? "Waiting for samples"
    )
    .accessibilityHint("Open an interactive CPU history chart")
  }
}
enum CPUChartData {
  static func samples(_ series: CPUUsageSeries, since start: Date) -> [TelemetrySample] {
    var segment = 0
    var previous: Date?
    var result: [TelemetrySample] = []
    for point in series.points where point.date >= start {
      if let previous, point.date.timeIntervalSince(previous) > 15 { segment += 1 }
      previous = point.date
      guard let total = point.total, let system = point.system, total.isFinite, system.isFinite
      else {
        segment += 1
        continue
      }
      result.append(.init(date: point.date, value: total, series: 0, segment: segment))
      result.append(.init(date: point.date, value: system, series: 1, segment: segment))
    }
    return result
  }
  static func maximum(_ series: CPUUsageSeries, since start: Date, threads: Bool) -> Double {
    threads
      ? max(100, (series.points.filter { $0.date >= start }.compactMap(\.total).max() ?? 0) * 1.05)
      : 100
  }
}
private struct CPUChartInspection: View {
  let series: CPUUsageSeries
  let range: Int
  let end: Date
  let theme: MonitorTheme
  let threads: Bool
  var body: some View {
    let start = end.addingTimeInterval(Double(-range * 60))
    VStack(alignment: .leading, spacing: 12) {
      Text(series.title).font(.system(size: 17, weight: .semibold))
      Text(series.detail).font(.system(size: 11)).foregroundStyle(theme.secondary)
      HStack {
        Text(series.latest.map { String(format: "%.1f%%", $0) } ?? "—").font(
          .system(size: 28, weight: .medium)
        ).monospacedDigit()
        Spacer()
        Text("Blue: total · Pink: system").font(.system(size: 10)).foregroundStyle(theme.secondary)
      }
      TelemetryChart(
        samples: CPUChartData.samples(series, since: start), metric: .cpu, range: range,
        end: end, theme: theme, perProcess: true,
        cpuMaximum: CPUChartData.maximum(series, since: start, threads: threads), cpuLabel: "Total"
      ).frame(height: 165)
      if let point = series.points.last {
        Text(
          "User \(point.user.map { String(format: "%.1f%%", $0) } ?? "—") · System \(point.system.map { String(format: "%.1f%%", $0) } ?? "—")"
        )
        .font(.system(size: 11)).foregroundStyle(theme.secondary)
      }
      Text(
        threads
          ? "100% is one logical processor. Threads can move between cores."
          : "100% is this logical processor’s full capacity."
      )
      .font(.system(size: 10)).foregroundStyle(theme.secondary)
    }.padding(20).frame(width: 380).background(theme.window).foregroundStyle(theme.text)
      .preferredColorScheme(theme.dark ? .dark : .light)
  }
}
