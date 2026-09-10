import Accessibility
import SwiftUI

/// Exact paths, with no decimation: every sample and every missing-data gap survives.
struct TelemetryTrace {
  let samples: [TelemetrySample]
  static func make(_ samples: [TelemetrySample]) -> [TelemetryTrace] {
    struct Key: Hashable {
      let series: Int
      let segment: Int
    }
    var groups: [Key: [TelemetrySample]] = [:]
    var order: [Key] = []
    for sample in samples {
      let key = Key(series: sample.series, segment: sample.segment)
      if groups[key] == nil { order.append(key) }
      groups[key, default: []].append(sample)
    }
    return order.map { TelemetryTrace(samples: groups[$0]!) }
  }
  func coordinates(size: CGSize, start: Date, end: Date, domain: ClosedRange<Double>, stepped: Bool)
    -> [CGPoint]
  {
    let span = max(0.001, end.timeIntervalSince(start))
    let scale = max(0.001, domain.upperBound - domain.lowerBound)
    var points: [CGPoint] = []
    points.reserveCapacity(samples.count * (stepped ? 2 : 1))
    for sample in samples {
      let point = CGPoint(
        x: sample.date.timeIntervalSince(start) / span * size.width,
        y: (domain.upperBound - sample.value) / scale * size.height)
      if stepped, let previous = points.last {
        points.append(CGPoint(x: point.x, y: previous.y))
      }
      points.append(point)
    }
    return points
  }
}

/// Audio Graphs keep all raw samples even though the visual traces use one Canvas.
struct TelemetryAccessibility: AXChartDescriptorRepresentable {
  let traces: [TelemetryTrace]
  let title: String
  let start: Date
  let end: Date
  let domain: ClosedRange<Double>
  let label: (TelemetrySample) -> String
  let value: (Double) -> String
  func makeChartDescriptor() -> AXChartDescriptor {
    let x = AXNumericDataAxisDescriptor(
      title: "Time", range: start.timeIntervalSince1970...end.timeIntervalSince1970,
      gridlinePositions: []
    ) { Date(timeIntervalSince1970: $0).formatted(date: .omitted, time: .standard) }
    let y = AXNumericDataAxisDescriptor(
      title: title, range: domain, gridlinePositions: [], valueDescriptionProvider: value)
    let series = traces.compactMap { trace -> AXDataSeriesDescriptor? in
      guard let first = trace.samples.first else { return nil }
      return AXDataSeriesDescriptor(
        name: label(first), isContinuous: true,
        dataPoints: trace.samples.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value) }
      )
    }
    return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, series: series)
  }
}
