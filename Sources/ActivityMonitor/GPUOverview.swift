import SwiftUI

struct GPUOverview: View {
  @EnvironmentObject var monitor: Monitor
  let range: Int
  let theme: MonitorTheme
  var device: GPUDeviceSample? { monitor.gpuDevice }
  var width: CGFloat = 1068
  var expanded = false
  var body: some View {
    AdaptiveOverviewPanels(width: width, expanded: expanded, theme: theme) {
      hero
    } detail: {
      breakdown
    } context: {
      hardware
    }
  }
  var hero: some View {

    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text("GPU utilization").font(.system(size: 12)).foregroundStyle(theme.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(gpuPercent(device?.utilization)).font(.system(size: 34, weight: .medium))
              .tracking(-1.3)
            Text(device?.utilization == nil ? "" : "%").font(.system(size: 18))
              .foregroundStyle(theme.secondary)
            Text(
              device?.utilization == nil
                ? device?.connected == false ? "Device disconnected" : "Counter unavailable"
                : "in use"
            )
            .font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.leading, 4)
          }
        }
        Spacer(minLength: 4)
        Label("Device", systemImage: "circle.fill").font(.system(size: 9)).foregroundStyle(
          theme.blue
        ).padding(.top, 3)
      }
      GPUHistoryPlot(
        points: monitor.gpuHistories[device?.id ?? 0] ?? [], range: range,
        interval: monitor.interval, theme: theme
      ).padding(.top, 10)
    }.monospacedDigit()
  }
  var breakdown: some View {

    VStack(alignment: .leading, spacing: 0) {
      Text("Engine activity").font(.system(size: 12, weight: .medium))
      engine("Renderer", value: device?.renderer, color: theme.blue).padding(.top, 22)
      engine("Tiler", value: device?.tiler, color: theme.purple).padding(.top, 17)
      Spacer(minLength: 8)
      Text("Engines can work at the same time.").font(.system(size: 9)).foregroundStyle(
        theme.tertiary)
    }
  }
  var hardware: some View {

    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Graphics at a glance").font(.system(size: 12, weight: .medium))
        Spacer()
        Image(systemName: "square.3.layers.3d").font(.system(size: 18, weight: .light))
          .foregroundStyle(theme.tertiary)
      }
      Text(device?.name ?? "No GPU detected").font(.system(size: 19, weight: .medium))
        .tracking(-0.4)
        .lineLimit(1).minimumScaleFactor(0.7).help(device?.name ?? "No GPU detected").padding(
          .top, 19)
      Text(
        device?.unifiedMemory.map { $0 ? "Unified memory" : "Discrete memory" }
          ?? "Memory architecture unavailable"
      )
      .font(.system(size: 10)).foregroundStyle(theme.secondary).padding(.top, 4)
      Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, 15)
      detail("GPU memory in use", device?.memoryUsed.map(bytes) ?? "—")
      detail("Driver allocation", device?.memoryAllocated.map(bytes) ?? "—").padding(.top, 11)
    }.help(
      "Driver-reported system memory. Allocation is not VRAM capacity and may overlap process memory."
    )
  }
  func engine(_ title: String, value: Double?, color: Color) -> some View {
    VStack(spacing: 9) {
      HStack {
        Circle().fill(color).frame(width: 6, height: 6)
        Text(title).foregroundStyle(theme.secondary)
        Spacer()
        Text(gpuPercent(value) + (value == nil ? "" : "%")).monospacedDigit()
      }.font(.system(size: 11))
      GeometryReader { g in
        Capsule().fill(theme.recessed)
        if let value { Capsule().fill(color).frame(width: g.size.width * CGFloat(value / 100)) }
      }.frame(height: 6)
    }.accessibilityElement(children: .combine)
  }
  func detail(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).foregroundStyle(theme.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }.font(.system(size: 11))
  }
}

/// Split at missing samples and long observation gaps rather than drawing invented continuity.
func gpuHistorySegments(_ points: [GPUHistoryPoint], maximumGap: TimeInterval)
  -> [[GPUHistoryPoint]]
{
  var result: [[GPUHistoryPoint]] = []
  var segment: [GPUHistoryPoint] = []
  for point in points {
    if point.utilization == nil
      || segment.last.map({ point.date.timeIntervalSince($0.date) > maximumGap }) == true
    {
      if !segment.isEmpty {
        result.append(segment)
        segment = []
      }
    }
    if point.utilization != nil { segment.append(point) }
  }
  if !segment.isEmpty { result.append(segment) }
  return result
}

struct GPUHistoryPlot: View {
  let points: [GPUHistoryPoint]
  let range: Int
  let interval: Double
  let theme: MonitorTheme
  var body: some View {
    TelemetryChart(
      samples: TelemetryData.gpu(points, maximumGap: max(10, interval * 2.5)),
      metric: .gpu, range: range, end: points.last?.date ?? Date(), theme: theme)
  }
}
