import Charts
import SwiftUI

struct TelemetrySample: Identifiable {
  let date: Date
  let value: Double
  let series: Int
  let segment: Int
  var id: String { "\(date.timeIntervalSince1970)-\(series)" }
  var group: String { "\(series)-\(segment)" }
}
enum TelemetryData {
  static func samples(points: [Point], metric: Metric, maximumGap: TimeInterval)
    -> [TelemetrySample]
  {
    var result: [TelemetrySample] = []
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
        ? point.a + point.b : metric == .memory ? (point.b == 4 ? 3 : point.b) : point.a
      guard first.isFinite, first >= 0 else {
        segment += 1
        continue
      }
      result.append(TelemetrySample(date: point.date, value: first, series: 0, segment: segment))
      if [.cpu, .disk, .network].contains(metric), point.b.isFinite, point.b >= 0 {
        result.append(
          TelemetrySample(
            date: point.date, value: metric == .cpu ? point.b : -point.b, series: 1,
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
  static func domain(_ samples: [TelemetrySample], metric: Metric) -> ClosedRange<Double> {
    if metric == .cpu || metric == .gpu { return 0...100 }
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
  @State private var selectedDate: Date?
  @FocusState private var focused: Bool
  private var start: Date { end.addingTimeInterval(Double(-range * 60)) }
  private var visible: [TelemetrySample] { samples.filter { $0.date >= start } }
  private var domain: ClosedRange<Double> { TelemetryData.domain(visible, metric: metric) }
  private var nearest: Date? { selectedDate.flatMap { TelemetryData.nearest($0, in: visible) } }
  private var selection: [TelemetrySample] { visible.filter { $0.date == nearest } }
  private func color(_ sample: TelemetrySample) -> Color {
    metric == .memory
      ? ((visible.last?.value ?? 1) >= 3
        ? theme.coral : (visible.last?.value ?? 1) >= 2 ? theme.amber : theme.green)
      : sample.series == 0 ? theme.blue : theme.coral
  }
  private func label(_ sample: TelemetrySample) -> String {
    switch metric {
    case .cpu: return sample.series == 0 ? "Total" : "System"
    case .memory: return "Pressure"
    case .energy: return "CPU workload"
    case .gpu: return "Device"
    case .disk: return sample.series == 0 ? "Read" : "Write"
    case .network: return sample.series == 0 ? "In" : "Out"
    }
  }
  private func value(_ number: Double) -> String {
    switch metric {
    case .memory: return number >= 3 ? "High" : number >= 2 ? "Moderate" : "Normal"
    case .disk, .network: return bytes(UInt64(max(0, abs(number)))) + "/s"
    default: return String(format: "%.1f%%", number)
    }
  }
  var body: some View {
    Chart {
      ForEach(visible) { point in
        AreaMark(
          x: .value("Time", point.date), yStart: .value("Baseline", 0),
          yEnd: .value("Value", point.value), series: .value("Segment", point.group)
        )
        .foregroundStyle(color(point).opacity(0.13))
        .interpolationMethod(metric == .memory ? .stepEnd : .linear)
        LineMark(
          x: .value("Time", point.date), y: .value("Value", point.value),
          series: .value("Segment", point.group)
        )
        .foregroundStyle(color(point)).lineStyle(StrokeStyle(lineWidth: 1.5))
        .interpolationMethod(metric == .memory ? .stepEnd : .linear)
      }
      if let nearest {
        RuleMark(x: .value("Selected time", nearest))
          .foregroundStyle(theme.tertiary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        ForEach(selection) { point in
          PointMark(x: .value("Time", point.date), y: .value("Value", point.value))
            .foregroundStyle(color(point)).symbolSize(24)
        }
      }
    }
    .chartXScale(domain: start...end).chartYScale(domain: domain)
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
        values: metric == .memory
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
    .chartPlotStyle { plot in plot.clipped() }
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
    .focusable().focused($focused).focusEffectDisabled()
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? theme.blue : .clear, lineWidth: 1))
    .onKeyPress(.leftArrow) {
      step(-1)
      return .handled
    }
    .onKeyPress(.rightArrow) {
      step(1)
      return .handled
    }
    .onKeyPress(.escape) {
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
    "Hover to inspect. Focus and use left or right arrow keys to inspect samples."
      + (metric == .cpu ? " " + CPUAccounting.systemHelp : "")
  }
  private var latestValue: String {
    guard let latest = visible.last else { return "No readable samples" }
    return visible.filter { $0.date == latest.date }.map { label($0) + " " + value($0.value) }
      .joined(separator: ", ")
  }
  private func axisLabel(_ number: Double) -> String {
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
