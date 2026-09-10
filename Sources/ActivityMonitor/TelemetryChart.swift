import Charts
import SwiftUI

struct TelemetrySample: Identifiable {
  let date: Date
  let value: Double
  let series: Int
  let segment: Int
  struct ID: Hashable {
    let date: Date
    let series: Int
  }
  var id: ID { ID(date: date, series: series) }
  var group: String { "\(series)-\(segment)" }
}
enum TelemetryData {
  static func samples(
    points: [Point], metric: Metric, maximumGap: TimeInterval,
    logicalProcessors: Int = CPUAccounting.logicalProcessorCount
  )
    -> [TelemetrySample]
  {
    var result: [TelemetrySample] = []
    result.reserveCapacity(points.count * 2)
    var segment = 0
    var previous: Date?
    for point in points {
      if let previous, point.date.timeIntervalSince(previous) > maximumGap { segment += 1 }
      previous = point.date
      if metric == .memory && ![1.0, 2.0, 4.0].contains(point.b) {
        segment += 1
        continue
      }
      let first =
        metric == .cpu
        ? CPUAccounting.executionPercent(point.a + point.b, processors: logicalProcessors)
        : metric == .memory ? (point.b == 4 ? 3 : point.b) : point.a
      guard first.isFinite, first >= 0 else {
        segment += 1
        continue
      }
      result.append(TelemetrySample(date: point.date, value: first, series: 0, segment: segment))
      if [.cpu, .disk, .network].contains(metric), point.b.isFinite, point.b >= 0 {
        result.append(
          TelemetrySample(
            date: point.date,
            value: metric == .cpu
              ? CPUAccounting.executionPercent(point.b, processors: logicalProcessors) : -point.b,
            series: 1,
            segment: segment))
      }
    }
    return result
  }
  static func gpu(_ points: [GPUHistoryPoint], maximumGap: TimeInterval) -> [TelemetrySample] {
    gpuHistorySegments(points, maximumGap: maximumGap).enumerated().flatMap { segment, points in
      points.compactMap { point in
        point.utilization.map {
          TelemetrySample(date: point.date, value: $0, series: 0, segment: segment)
        }
      }
    }
  }
  static func domain(
    _ samples: [TelemetrySample], metric: Metric,
    logicalProcessors: Int = CPUAccounting.logicalProcessorCount
  ) -> ClosedRange<Double> {
    if metric == .cpu { return 0...CPUAccounting.capacity(processors: logicalProcessors) }
    if metric == .gpu { return 0...100 }
    if metric == .memory { return 0...3 }
    let maximum = max(1, (samples.map { abs($0.value) }.max() ?? 1) * 1.15)
    return (metric == .disk || metric == .network ? -maximum : 0)...maximum
  }
  static func nearest(_ date: Date, in samples: [TelemetrySample]) -> Date? {
    samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
      .date
  }
}

/// The same chart is used in every window size and the menu-bar popover.
struct TelemetryChart: View {
  let samples: [TelemetrySample]
  let metric: Metric
  let range: Int
  let end: Date
  let theme: MonitorTheme
  let perProcess: Bool
  @State private var selectedDate: Date?
  private var start: Date { end.addingTimeInterval(Double(-range * 60)) }
  private let traces: [TelemetryTrace]
  private let visible: [TelemetrySample]
  private let domain: ClosedRange<Double>
  init(
    samples: [TelemetrySample], metric: Metric, range: Int, end: Date, theme: MonitorTheme,
    perProcess: Bool = false
  ) {
    self.samples = samples
    self.metric = metric
    self.range = range
    self.end = end
    self.theme = theme
    self.perProcess = perProcess
    let start = end.addingTimeInterval(Double(-range * 60))
    let visible = samples.filter { $0.date >= start && $0.date <= end }
    self.visible = visible
    self.traces = TelemetryTrace.make(visible)
    if perProcess {
      let maximum = max(1, (visible.map { abs($0.value) }.max() ?? 1) * 1.15)
      self.domain = (metric == .disk || metric == .network ? -maximum : 0)...maximum
    } else {
      self.domain = TelemetryData.domain(visible, metric: metric)
    }
  }
  private var nearest: Date? { selectedDate.flatMap { TelemetryData.nearest($0, in: visible) } }
  private var selection: [TelemetrySample] {
    guard let date = nearest else { return [] }
    return visible.filter { $0.date == date }
  }
  private func color(_ sample: TelemetrySample) -> Color {
    metric == .memory && !perProcess
      ? ((visible.last?.value ?? 1) >= 3
        ? theme.coral : (visible.last?.value ?? 1) >= 2 ? theme.amber : theme.green)
      : sample.series == 0 ? theme.blue : theme.coral
  }
  private func label(_ sample: TelemetrySample) -> String {
    switch metric {
    case .cpu: return sample.series == 0 ? (perProcess ? "Process" : "Total") : "System"
    case .memory: return perProcess ? "Memory" : "Pressure"
    case .energy: return "CPU workload"
    case .gpu: return perProcess ? "Process" : "Device"
    case .disk: return sample.series == 0 ? "Read" : "Write"
    case .network: return sample.series == 0 ? "In" : "Out"
    }
  }
  private func value(_ number: Double) -> String {
    switch metric {
    case .memory:
      return perProcess
        ? bytes(UInt64(max(0, number))) : number >= 3 ? "High" : number >= 2 ? "Moderate" : "Normal"
    case .disk, .network: return bytes(UInt64(max(0, abs(number)))) + "/s"
    default: return String(format: "%.1f%%", number)
    }
  }
  var body: some View {
    Chart {
      // Keep native axes, inspection and keyboard interaction. The exact series
      // paths are drawn in a single Canvas instead of thousands of mark views.
      PointMark(x: .value("Time", start), y: .value("Value", domain.lowerBound))
        .opacity(0).accessibilityHidden(true)
      PointMark(x: .value("Time", end), y: .value("Value", domain.upperBound))
        .opacity(0).accessibilityHidden(true)
      if let nearest {
        RuleMark(x: .value("Selected time", nearest))
          .foregroundStyle(theme.tertiary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        ForEach(selection) { point in
          PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
            .foregroundStyle(color(point)).symbolSize(24)
        }
      }
    }
    .chartXScale(domain: start...end, range: .plotDimension(startPadding: 0, endPadding: 0))
    .chartYScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
    .chartLegend(.hidden)
    .chartXAxis {
      AxisMarks(values: [start, start.addingTimeInterval(Double(range * 30)), end]) { axis in
        AxisValueLabel {
          if let date = axis.as(Date.self) {
            Text(date == end ? "Now" : "−\(Int(end.timeIntervalSince(date))) sec")
              .font(.system(size: 8)).foregroundStyle(theme.tertiary)
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(
        position: .trailing,
        values: metric == .memory && !perProcess
          ? [1, 2, 3]
          : [domain.lowerBound, (domain.lowerBound + domain.upperBound) / 2, domain.upperBound]
      ) { axis in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(theme.border)
        AxisValueLabel {
          if let number = axis.as(Double.self) {
            Text(axisLabel(number)).font(.system(size: 8)).foregroundStyle(theme.tertiary)
          }
        }
      }
    }
    .chartXSelection(value: $selectedDate)
    .chartPlotStyle { plot in
      plot.background {
        Canvas { context, size in
          let baseline = domain.upperBound / (domain.upperBound - domain.lowerBound) * size.height
          for trace in traces {
            let points = trace.coordinates(
              size: size, start: start, end: end, domain: domain, stepped: metric == .memory)
            guard let first = points.first, let last = points.last, let sample = trace.samples.first
            else { continue }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: baseline))
            area.addLine(to: CGPoint(x: first.x, y: baseline))
            area.closeSubpath()
            context.fill(area, with: .color(color(sample).opacity(0.13)))
            context.stroke(line, with: .color(color(sample)), lineWidth: 1.5)
          }
        }.accessibilityHidden(true).allowsHitTesting(false)
      }.clipped()
    }
    .accessibilityChartDescriptor(
      TelemetryAccessibility(
        traces: traces, title: metric.rawValue,
        start: start, end: end, domain: domain, label: label, value: value)
    )
    .overlay(alignment: .topLeading) {
      if let nearest, !selection.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          Text(nearest.formatted(date: .omitted, time: .standard)).foregroundStyle(theme.secondary)
          Text(selection.map { label($0) + " " + value($0.value) }.joined(separator: " · "))
        }.font(.system(size: 10).monospacedDigit()).padding(5)
          .background(theme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 5))
          .allowsHitTesting(false)
      } else if visible.isEmpty {
        Text("Waiting for readable samples").font(.system(size: 11)).foregroundStyle(
          theme.secondary
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    // Inspection is an alternative to pointer interaction, not an always-active editor.
    // Respect macOS Keyboard navigation and let the system render intentional focus.
    .contentShape(RoundedRectangle(cornerRadius: 4))
    .focusable(interactions: .activate)
    .onKeyPress(.leftArrow) {
      step(-1)
      return .handled
    }
    .onKeyPress(.rightArrow) {
      step(1)
      return .handled
    }
    .onKeyPress(.escape) {
      guard selectedDate != nil else { return .ignored }
      selectedDate = nil
      return .handled
    }
    .accessibilityLabel("\(metric.rawValue) history over \(range) minutes")
    .accessibilityValue(
      selection.isEmpty
        ? latestValue : selection.map { label($0) + " " + value($0.value) }.joined(separator: ", ")
    )
    .accessibilityHint(inspectionHint)
  }
  private var inspectionHint: String {
    "Hover to inspect. With macOS Keyboard navigation enabled, Tab to the chart and use left or right arrow keys to inspect samples."
      + (metric == .cpu
        ? " " + (perProcess ? CPUAccounting.processHelp : CPUAccounting.systemHelp) : "")
  }
  private var latestValue: String {
    guard let latest = visible.last else { return "No readable samples" }
    return visible.filter { $0.date == latest.date }.map { label($0) + " " + value($0.value) }
      .joined(separator: ", ")
  }
  private func axisLabel(_ number: Double) -> String {
    if metric == .memory && perProcess { return bytes(UInt64(max(0, number))) }
    if metric == .memory { return number >= 3 ? "High" : number >= 2 ? "Med" : "Low" }
    if metric == .disk || metric == .network {
      let parts = byteParts(UInt64(abs(number)))
      return (number < 0 ? "−" : "") + String(format: "%.0f", Double(parts.0) ?? 0)
        + String(parts.1.prefix(1))
    }
    return String(format: "%.0f%%", number)
  }
  private func step(_ delta: Int) {
    let dates = Array(Set(visible.map(\.date))).sorted()
    guard !dates.isEmpty else { return }
    let index = nearest.flatMap { dates.firstIndex(of: $0) } ?? (delta < 0 ? dates.count : -1)
    selectedDate = dates[min(max(0, index + delta), dates.count - 1)]
  }
}
