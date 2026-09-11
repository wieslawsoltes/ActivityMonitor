import Charts
import SwiftUI

private enum ProcessMemoryMeasure: String, CaseIterable, Identifiable {
  case footprint
  case resident
  case privateBytes
  case sharedBytes
  case compressed
  case purgeable

  var id: String { rawValue }
  var title: String {
    switch self {
    case .footprint: return "Footprint"
    case .resident: return "Resident"
    case .privateBytes: return "Private"
    case .sharedBytes: return "Shared"
    case .compressed: return "Compressed"
    case .purgeable: return "Purgeable"
    }
  }
  var source: String {
    switch self {
    case .footprint: return "Physical footprint from proc_pid_rusage"
    case .resident: return "Resident pages from task statistics"
    case .privateBytes: return "Private resident pages from the process map"
    case .sharedBytes: return "Shared resident pages from the process map"
    case .compressed: return "Compressed resident bytes from task statistics"
    case .purgeable: return "Purgeable volatile resident bytes from task statistics"
    }
  }
  func value(_ sample: ProcessMemorySample) -> UInt64? {
    switch self {
    case .footprint: return sample.footprint
    case .resident: return sample.resident
    case .privateBytes: return sample.privateBytes
    case .sharedBytes: return sample.sharedBytes
    case .compressed: return sample.compressed
    case .purgeable: return sample.purgeable
    }
  }
  func color(_ theme: MonitorTheme) -> Color {
    switch self {
    case .footprint: return theme.blue
    case .resident: return theme.purple
    case .privateBytes: return theme.coral
    case .sharedBytes: return theme.amber
    case .compressed: return theme.green
    case .purgeable: return theme.tertiary
    }
  }
}

private struct ResourceChartPoint: Identifiable {
  let id: String
  let date: Date
  let value: Double
  let title: String
}

struct ProcessMemoryVisualization: View {
  let history: [ProcessMemorySample]
  let theme: MonitorTheme
  let range: Int
  private var visible: [ProcessMemorySample] {
    guard let end = history.last?.date else { return [] }
    let start = end.addingTimeInterval(Double(-range * 60))
    return history.filter { $0.date >= start && $0.date <= end }
  }
  private var latest: ProcessMemorySample? { visible.last ?? history.last }

  var body: some View {
    DiagnosticPanel(theme: theme) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Memory composition").font(.system(size: 13, weight: .semibold))
            Text("Physical footprint and the native accounting available for this process.")
              .font(.system(size: 10)).foregroundStyle(theme.secondary)
          }
          Spacer()
          Text(latest.flatMap { $0.footprint }.map(bytes) ?? "—")
            .font(.system(size: 15, weight: .medium)).monospacedDigit()
        }
        if visible.contains(where: { sample in
          ProcessMemoryMeasure.allCases.contains { measure in measure.value(sample) != nil }
        }) {
          chart
            .frame(height: 190)
        } else {
          unavailable("No readable memory counters in this snapshot.")
            .frame(height: 190)
        }
        memoryList
        Text(
          "Footprint is the primary physical-memory comparison. Resident, private and shared values can overlap shared pages and are therefore diagnostic breakdowns rather than additive totals."
        )
        .font(.system(size: 10)).foregroundStyle(theme.tertiary).fixedSize(
          horizontal: false, vertical: true)
      }
    }
  }

  private var chart: some View {
    let points = visiblePoints
    let maximum = max(1.0, (points.map(\.value).max() ?? 1) * 1.12)
    return Chart(points) { point in
      LineMark(
        x: .value("Time", point.date), y: .value("Bytes", point.value),
        series: .value("Memory", point.title)
      )
      .foregroundStyle(by: .value("Memory", point.title))
      .lineStyle(StrokeStyle(lineWidth: point.title == "Footprint" ? 2 : 1.2))
    }
    .chartYScale(domain: 0...maximum)
    .chartLegend(position: .bottom, spacing: 9)
    .chartForegroundStyleScale(
      domain: ProcessMemoryMeasure.allCases.map(\.title),
      range: ProcessMemoryMeasure.allCases.map { $0.color(theme) })
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(theme.border)
        AxisValueLabel {
          if let date = value.as(Date.self) {
            Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 8))
              .foregroundStyle(theme.tertiary)
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(theme.border)
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(bytes(UInt64(max(0, number)))).font(.system(size: 8)).foregroundStyle(theme.tertiary)
          }
        }
      }
    }
  }

  private var visiblePoints: [ResourceChartPoint] {
    ProcessMemoryMeasure.allCases.flatMap { measure in
      visible.compactMap { sample in
        guard let value = measure.value(sample) else { return nil }
        return ResourceChartPoint(
          id: "\(measure.rawValue)-\(sample.date.timeIntervalSinceReferenceDate)",
          date: sample.date, value: Double(value), title: measure.title)
      }
    }
  }

  private var memoryList: some View {
    let current = latest
    return VStack(spacing: 0) {
      HStack {
        Text("Counter").foregroundStyle(theme.secondary)
        Spacer()
        Text("Current").foregroundStyle(theme.secondary).frame(width: 92, alignment: .trailing)
        Text("Peak").foregroundStyle(theme.secondary).frame(width: 92, alignment: .trailing)
      }
      .font(.system(size: 10, weight: .medium)).padding(.bottom, 6)
      ForEach(ProcessMemoryMeasure.allCases) { measure in
        let values = visible.compactMap { measure.value($0) }
        HStack(spacing: 8) {
          Circle().fill(measure.color(theme)).frame(width: 6, height: 6)
          Text(measure.title).font(.system(size: 11))
            .help(measure.source)
          Spacer(minLength: 8)
          Text(current.flatMap(measure.value).map(bytes) ?? "—")
            .font(.system(size: 11)).monospacedDigit().frame(width: 92, alignment: .trailing)
          Text(values.max().map(bytes) ?? "—")
            .font(.system(size: 11)).monospacedDigit().frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
      }
    }
  }

  private func unavailable(_ message: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: "memorychip").font(.system(size: 24, weight: .light)).foregroundStyle(theme.tertiary)
      Text(message).font(.system(size: 11)).foregroundStyle(theme.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct ProcessGPUMemoryVisualization: View {
  let history: [ProcessGPUMemorySample]
  let devices: [GPUDeviceSample]
  let theme: MonitorTheme
  let range: Int
  private var visible: [ProcessGPUMemorySample] {
    guard let end = history.last?.date else { return [] }
    let start = end.addingTimeInterval(Double(-range * 60))
    return history.filter { $0.date >= start && $0.date <= end }
  }
  private var hasMemory: Bool {
    visible.contains { $0.used != nil || $0.allocated != nil }
  }

  var body: some View {
    DiagnosticPanel(theme: theme) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("GPU memory").font(.system(size: 13, weight: .semibold))
            Text("Driver-reported memory across the GPU devices visible to macOS.")
              .font(.system(size: 10)).foregroundStyle(theme.secondary)
          }
          Spacer()
          Text(visible.last?.used.map(bytes) ?? "—")
            .font(.system(size: 15, weight: .medium)).monospacedDigit()
        }
        if hasMemory {
          chart.frame(height: 170)
        } else {
          VStack(spacing: 8) {
            Image(systemName: "square.3.layers.3d").font(.system(size: 24, weight: .light))
              .foregroundStyle(theme.tertiary)
            Text("The graphics driver did not publish a memory counter.")
              .font(.system(size: 11)).foregroundStyle(theme.secondary)
          }.frame(maxWidth: .infinity).frame(height: 170)
        }
        deviceList
        Text(
          "Public Metal and IOKit APIs expose device totals, but macOS does not publish per-process GPU allocation bytes. The process GPU activity chart above remains per-process where the driver publishes execution counters."
        )
        .font(.system(size: 10)).foregroundStyle(theme.tertiary).fixedSize(
          horizontal: false, vertical: true)
      }
    }
  }

  private var chart: some View {
    let points = visible.flatMap { sample -> [ResourceChartPoint] in
      [
        sample.used.map {
          ResourceChartPoint(
            id: "used-\(sample.date.timeIntervalSinceReferenceDate)", date: sample.date,
            value: Double($0), title: "In use")
        },
        sample.allocated.map {
          ResourceChartPoint(
            id: "allocated-\(sample.date.timeIntervalSinceReferenceDate)", date: sample.date,
            value: Double($0), title: "Allocated")
        },
      ].compactMap { $0 }
    }
    let maximum = max(1.0, (points.map(\.value).max() ?? 1) * 1.12)
    return Chart(points) { point in
      LineMark(
        x: .value("Time", point.date), y: .value("Bytes", point.value),
        series: .value("Memory", point.title)
      )
      .foregroundStyle(by: .value("Memory", point.title))
      .lineStyle(StrokeStyle(lineWidth: point.title == "In use" ? 2 : 1.2))
    }
    .chartYScale(domain: 0...maximum)
    .chartLegend(position: .bottom, spacing: 9)
    .chartForegroundStyleScale(domain: ["In use", "Allocated"], range: [theme.blue, theme.purple])
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisValueLabel {
          if let date = value.as(Date.self) {
            Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 8))
              .foregroundStyle(theme.tertiary)
          }
        }
      }
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(theme.border)
        AxisValueLabel {
          if let number = value.as(Double.self) {
            Text(bytes(UInt64(max(0, number)))).font(.system(size: 8)).foregroundStyle(theme.tertiary)
          }
        }
      }
    }
  }

  private var deviceList: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Source").foregroundStyle(theme.secondary)
        Spacer()
        Text("In use").foregroundStyle(theme.secondary).frame(width: 92, alignment: .trailing)
        Text("Allocated").foregroundStyle(theme.secondary).frame(width: 92, alignment: .trailing)
      }
      .font(.system(size: 10, weight: .medium)).padding(.bottom, 6)
      HStack(spacing: 8) {
        Circle().fill(theme.blue).frame(width: 6, height: 6)
        Text("Process allocation").font(.system(size: 11))
          .help("macOS does not expose per-process GPU allocation bytes through public APIs")
        Spacer(minLength: 8)
        Text("—").font(.system(size: 11)).monospacedDigit().frame(width: 92, alignment: .trailing)
        Text("Unavailable").font(.system(size: 11)).foregroundStyle(theme.tertiary)
          .frame(width: 92, alignment: .trailing)
      }
      .padding(.vertical, 7)
      .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
      ForEach(devices) { device in
        HStack(spacing: 8) {
          Circle().fill(device.connected ? theme.purple : theme.tertiary).frame(width: 6, height: 6)
          Text(device.name).font(.system(size: 11)).lineLimit(1).help(device.name)
          Spacer(minLength: 8)
          Text(device.memoryUsed.map(bytes) ?? "—").font(.system(size: 11)).monospacedDigit()
            .frame(width: 92, alignment: .trailing)
          Text(device.memoryAllocated.map(bytes) ?? "—").font(.system(size: 11)).monospacedDigit()
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
      }
      if devices.isEmpty {
        Text("No GPU device memory counters are currently available.")
          .font(.system(size: 11)).foregroundStyle(theme.secondary).frame(maxWidth: .infinity)
          .padding(.vertical, 9)
      }
    }
  }
}
