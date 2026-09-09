import SwiftUI

struct GPUOverview: View {
  @EnvironmentObject var monitor: Monitor
  let range: Int
  let theme: MonitorTheme
  var device: GPUDeviceSample? { monitor.gpuDevice }
  var body: some View {
    GeometryReader { geometry in
      let unit = (geometry.size.width - 28) / 3.82
      HStack(spacing: 14) {
        DesignCard(theme: theme, padding: 19) {
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
        }.frame(width: unit * 1.82)
        DesignCard(theme: theme) {
          VStack(alignment: .leading, spacing: 0) {
            Text("Engine activity").font(.system(size: 12, weight: .medium))
            engine("Renderer", value: device?.renderer, color: theme.blue).padding(.top, 22)
            engine("Tiler", value: device?.tiler, color: theme.purple).padding(.top, 17)
            Spacer(minLength: 8)
            Text("Engines can work at the same time.").font(.system(size: 9)).foregroundStyle(
              theme.tertiary)
          }
        }.frame(width: unit)
        DesignCard(theme: theme) {
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
        }.frame(width: unit)
      }
    }.frame(height: 213)
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
  @State private var hover: CGFloat?
  var body: some View {
    GeometryReader { geometry in
      let width = max(1, geometry.size.width - 32)
      let height = max(1, geometry.size.height - 18)
      let end = points.last?.date ?? Date()
      let start = end.addingTimeInterval(Double(-range * 60))
      let visible = points.filter { $0.date >= start }
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          for step in 0...2 {
            let y = CGFloat(step) * height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: width, y: y))
            context.stroke(
              grid, with: .color(theme.border), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
          }
          for segment in gpuHistorySegments(visible, maximumGap: max(10, interval * 2.5)) {
            let positions = segment.compactMap { point -> CGPoint? in
              guard let value = point.utilization else { return nil }
              return CGPoint(
                x: point.date.timeIntervalSince(start) / Double(range * 60) * width,
                y: height * (1 - value / 100))
            }
            guard let first = positions.first, let last = positions.last else { continue }
            var line = Path()
            line.move(to: first)
            for point in positions.dropFirst() { line.addLine(to: point) }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: height))
            area.addLine(to: CGPoint(x: first.x, y: height))
            area.closeSubpath()
            context.fill(area, with: .color(theme.blue.opacity(0.13)))
            context.stroke(
              line, with: .color(theme.blue),
              style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if positions.count == 1 {
              context.fill(
                Path(ellipseIn: CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3)),
                with: .color(theme.blue))
            }
          }
          if let hover {
            let x = min(width, max(0, hover))
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: height))
            context.stroke(
              line, with: .color(theme.tertiary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          }
        }
        VStack {
          Text("100%")
          Spacer()
          Text("50%")
          Spacer()
          Text("0")
        }
        .font(.system(size: 8)).foregroundStyle(theme.tertiary)
        .frame(width: 28, height: height, alignment: .trailing).offset(x: width + 4)
        HStack {
          Text("−\(range * 60) sec")
          Spacer()
          Text("−\(range * 30) sec")
          Spacer()
          Text("Now")
        }
        .font(.system(size: 8)).foregroundStyle(theme.tertiary).frame(width: width).offset(
          y: height + 6)
        if let hover,
          let point = visible.min(by: {
            abs($0.date.timeIntervalSince(start) / Double(range * 60) * width - hover)
              < abs($1.date.timeIntervalSince(start) / Double(range * 60) * width - hover)
          })
        {
          Text(
            (point.utilization.map { String(format: "%.1f%%", $0) } ?? "Unavailable") + " · "
              + point.date.formatted(date: .omitted, time: .standard)
          )
          .font(.system(size: 10)).padding(6).background(
            theme.subtle, in: RoundedRectangle(cornerRadius: 5)
          )
          .offset(x: min(max(0, hover - 60), max(0, width - 160)), y: 3)
        }
      }.onContinuousHover { phase in
        switch phase {
        case .active(let location): hover = location.x
        case .ended: hover = nil
        }
      }
    }.accessibilityElement(children: .ignore).accessibilityLabel(
      "GPU utilization history over \(range) minutes"
    )
    .accessibilityValue(
      points.last?.utilization.map { String(format: "Latest sample %.1f percent", $0) }
        ?? "Latest sample unavailable")
  }
}
