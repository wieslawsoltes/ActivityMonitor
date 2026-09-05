import SwiftUI

struct MonitorOverview: View {
  @EnvironmentObject var monitor: Monitor
  let metric: Metric
  let range: Int
  let theme: MonitorTheme
  var used: UInt64 { monitor.system.active + monitor.system.wired + monitor.system.compressed }
  var appCPU: Double { monitor.rows.filter(\.isApp).reduce(0) { $0 + $1.cpu } }
  var body: some View {
    GeometryReader { g in
      let unit = (g.size.width - 28) / 3.82
      HStack(spacing: 14) {
        DesignCard(theme: theme, padding: 19) { chartCard }.frame(width: unit * 1.82)
        DesignCard(theme: theme) { middleCard }.frame(width: unit)
        DesignCard(theme: theme) { lastCard }.frame(width: unit)
      }
    }.frame(height: 213)
  }
  var chartCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        if metric == .disk || metric == .network {
          HStack(spacing: 30) {
            rateHero(
              metric == .disk ? "Read" : "Receiving",
              metric == .disk ? monitor.readRate : monitor.receiveRate, theme.blue, "arrow.down")
            rateHero(
              metric == .disk ? "Write" : "Sending",
              metric == .disk ? monitor.writeRate : monitor.sendRate, theme.coral, "arrow.up")
          }
        } else {
          VStack(alignment: .leading, spacing: 3) {
            Text(
              metric == .cpu
                ? "CPU load" : metric == .memory ? "Memory pressure" : "Application CPU load"
            ).font(.system(size: 12)).foregroundStyle(theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text(
                metric == .cpu
                  ? String(format: "%.1f", monitor.userCPU + monitor.systemCPU)
                  : metric == .memory ? byteParts(used).0 : String(format: "%.1f", appCPU)
              ).font(.system(size: 34, weight: .medium)).tracking(-1.3).foregroundStyle(theme.text)
              Text(metric == .memory ? byteParts(used).1 : "%").font(.system(size: 18))
                .foregroundStyle(theme.secondary)
              Text(
                metric == .cpu
                  ? "in use"
                  : metric == .memory ? "used of \(bytes(monitor.system.physical))" : "CPU workload"
              ).font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.leading, 4)
            }
          }
        }
        Spacer(minLength: 4)
        if metric == .memory {
          badge(pressureName, color: pressureColor)
        } else {
          HStack(spacing: 12) {
            dot(
              metric == .cpu
                ? "User" : metric == .energy ? "CPU workload" : metric == .disk ? "Read" : "In",
              theme.blue)
            if metric != .energy {
              dot(metric == .cpu ? "System" : metric == .disk ? "Write" : "Out", theme.coral)
            }
          }.padding(.top, 3)
        }
      }
      HistoryPlot(
        points: monitor.histories[metric] ?? [], metric: metric, range: range, theme: theme,
        physical: Double(monitor.system.physical)
      ).padding(.top, 10)
    }.monospacedDigit()
  }
  @ViewBuilder var middleCard: some View {
    switch metric {
    case .cpu:
      VStack(alignment: .leading, spacing: 0) {
        title("Usage breakdown")
        stacked([
          (monitor.userCPU, theme.blue), (monitor.systemCPU, theme.coral),
          (max(0, 100 - monitor.userCPU - monitor.systemCPU), theme.recessed),
        ]).padding(.top, 25)
        VStack(spacing: 12) {
          detail("User", String(format: "%.2f%%", monitor.userCPU), theme.blue)
          detail("System", String(format: "%.2f%%", monitor.systemCPU), theme.coral)
          detail(
            "Idle", String(format: "%.2f%%", max(0, 100 - monitor.userCPU - monitor.systemCPU)),
            theme.recessed)
        }.padding(.top, 21)
      }
    case .memory:
      VStack(alignment: .leading, spacing: 0) {
        title("Memory allocation")
        stacked([
          (Double(monitor.system.active), theme.blue), (Double(monitor.system.wired), theme.purple),
          (Double(monitor.system.compressed), theme.amber),
          (Double(monitor.system.free), theme.recessed),
        ]).padding(.top, 25)
        VStack(spacing: 10) {
          detail("Active memory", bytes(monitor.system.active), theme.blue)
          detail("Wired", bytes(monitor.system.wired), theme.purple)
          detail("Compressed", bytes(monitor.system.compressed), theme.amber)
          detail("Free", bytes(monitor.system.free), theme.recessed)
        }.padding(.top, 19)
      }
    case .energy:
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          title("Battery")
          Spacer()
          badge(monitor.system.externalPower != 0 ? "On AC" : "Battery", color: theme.green)
        }
        HStack {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(monitor.system.battery < 0 ? "—" : "\(monitor.system.battery)").font(
              .system(size: 38, weight: .medium)
            ).tracking(-1.7)
            Text(monitor.system.battery < 0 ? "" : "%").font(.system(size: 22)).foregroundStyle(
              theme.secondary)
          }
          Spacer()
          ZStack {
            RoundedRectangle(cornerRadius: 8).stroke(theme.green, lineWidth: 1.7)
            RoundedRectangle(cornerRadius: 5).fill(theme.green.opacity(0.17)).padding(4)
            Image(systemName: "bolt").foregroundStyle(theme.green)
          }.frame(width: 80, height: 37).overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 1).fill(theme.green).frame(width: 3, height: 13).offset(
              x: 5)
          }
        }.padding(.top, 19)
        Label(
          monitor.system.battery < 0
            ? "No battery installed"
            : monitor.system.charging != 0
              ? "Charging" : monitor.system.battery == 100 ? "Fully charged" : "Not charging",
          systemImage: "checkmark.circle"
        ).font(.system(size: 10)).foregroundStyle(theme.green).padding(.top, 5)
        BatterySparkline(points: monitor.histories[.energy] ?? [], color: theme.green).frame(
          height: 29
        ).padding(.top, 22)
        HStack {
          Text("This session")
          Spacer()
          Text("Now")
        }.font(.system(size: 8)).foregroundStyle(theme.tertiary).padding(.top, 5)
      }
    case .disk, .network:
      VStack(alignment: .leading, spacing: 0) {
        title(metric == .disk ? "Data transferred" : "Total transfer")
        transfer(
          metric == .disk ? "Read" : "Received",
          metric == .disk ? monitor.rows.reduce(0) { $0 + $1.read } : monitor.system.received,
          theme.blue
        ).padding(.top, 23)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, 16)
        transfer(
          metric == .disk ? "Written" : "Sent",
          metric == .disk ? monitor.rows.reduce(0) { $0 + $1.written } : monitor.system.sent,
          theme.coral)
      }
    }
  }
  @ViewBuilder var lastCard: some View {
    switch metric {
    case .cpu:
      VStack(alignment: .leading, spacing: 23) {
        HStack {
          title("System at a glance")
          Spacer()
          Image(systemName: "cpu").font(.system(size: 20, weight: .ultraLight)).foregroundStyle(
            theme.tertiary)
        }
        HStack {
          mini(monitor.rows.reduce(0) { $0 + Int($1.threads) }.formatted(), "Threads available")
          mini(monitor.rows.count.formatted(), "Processes")
        }
        HStack {
          mini(architecture, "Architecture")
          mini(bytes(monitor.system.physical), "Physical memory")
        }
      }
    case .memory:
      VStack(alignment: .leading, spacing: 23) {
        HStack {
          title("Capacity & cache")
          Spacer()
          Image(systemName: "memorychip").foregroundStyle(theme.tertiary)
        }
        HStack {
          mini(bytes(monitor.system.physical), "Physical memory")
          mini(bytes(monitor.system.swap), "Swap used")
        }
        HStack {
          mini(bytes(monitor.system.inactive), "Cached / inactive")
          mini(
            String(format: "%.1f%%", Double(used) / max(1, Double(monitor.system.physical)) * 100),
            "Memory used")
        }
      }
    case .energy:
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          title("Power & efficiency")
          Spacer()
          Image(systemName: "powerplug").foregroundStyle(theme.tertiary)
        }
        Text(uptime).font(.system(size: 28, weight: .medium)).tracking(-0.8).padding(.top, 20)
        Text("System uptime").font(.system(size: 10)).foregroundStyle(theme.secondary).padding(
          .top, 5)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, 18)
        VStack(spacing: 12) {
          detail("Low Power Mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
          detail("Thermal state", thermal)
        }
      }
    case .disk:
      VStack(alignment: .leading, spacing: 0) {
        title("I/O activity")
        HStack {
          mini(monitor.rows.filter(\.ioAccessible).count.formatted(), "Processes reporting")
          mini(monitor.rows.count.formatted(), "Total processes")
        }.padding(.top, 25)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, 20)
        VStack(spacing: 12) {
          detail("Read / sec", bytes(UInt64(monitor.readRate)), theme.blue)
          detail("Write / sec", bytes(UInt64(monitor.writeRate)), theme.coral)
        }
      }
    case .network:
      VStack(alignment: .leading, spacing: 0) {
        title("Packet activity")
        HStack {
          mini(shortCount(monitor.system.packetsIn), "Packets in")
          mini(shortCount(monitor.system.packetsOut), "Packets out")
        }.padding(.top, 25)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, 20)
        VStack(spacing: 12) {
          detail("Packets in / sec", String(Int(monitor.packetReceiveRate)), theme.blue)
          detail("Packets out / sec", String(Int(monitor.packetSendRate)), theme.coral)
        }
      }
    }
  }
  func title(_ text: String) -> some View {
    Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
  }
  func dot(_ text: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(text).font(.system(size: 9)).foregroundStyle(theme.secondary)
    }
  }
  func badge(_ text: String, color: Color) -> some View {
    Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(color).padding(
      .horizontal, 7
    ).padding(.vertical, 4).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
  }
  func detail(_ name: String, _ value: String, _ color: Color? = nil) -> some View {
    HStack(spacing: 7) {
      if let color { Circle().fill(color).frame(width: 6, height: 6) }
      Text(name).foregroundStyle(theme.secondary)
      Spacer(minLength: 4)
      Text(value).foregroundStyle(theme.text).monospacedDigit()
    }.font(.system(size: 12))
  }
  func stacked(_ pieces: [(Double, Color)]) -> some View {
    GeometryReader { g in
      let sum = max(1, pieces.reduce(0) { $0 + $1.0 })
      HStack(spacing: 3) {
        ForEach(pieces.indices, id: \.self) { i in
          RoundedRectangle(cornerRadius: 2).fill(pieces[i].1).frame(
            width: max(0, (g.size.width - CGFloat(pieces.count - 1) * 3) * pieces[i].0 / sum))
        }
      }
    }.frame(height: 7)
  }
  func mini(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(value).font(.system(size: 23, weight: .medium)).tracking(-0.5).foregroundStyle(
        theme.text
      ).monospacedDigit()
      Text(label).font(.system(size: 11)).foregroundStyle(theme.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func transfer(_ name: String, _ value: UInt64, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      dot(name, color)
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(byteParts(value).0).font(.system(size: 27, weight: .medium)).tracking(-0.7)
        Text(byteParts(value).1).font(.system(size: 12)).foregroundStyle(theme.secondary)
      }
    }
  }
  func rateHero(_ name: String, _ value: Double, _ color: Color, _ icon: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: icon).foregroundStyle(color)
        Text(name).foregroundStyle(theme.secondary)
      }.font(.system(size: 11))
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(byteParts(UInt64(max(0, value))).0).font(.system(size: 28, weight: .medium)).tracking(
          -0.7)
        Text(byteParts(UInt64(max(0, value))).1 + "/s").font(.system(size: 11)).foregroundStyle(
          theme.secondary)
      }
    }
  }
  var pressureName: String {
    monitor.system.pressure == 1
      ? "Normal"
      : monitor.system.pressure == 2
        ? "Moderate" : monitor.system.pressure == 4 ? "High" : "Unknown"
  }
  var pressureColor: Color {
    monitor.system.pressure == 1
      ? theme.green : monitor.system.pressure == 2 ? theme.amber : theme.coral
  }
  var uptime: String {
    let minutes = Int(ProcessInfo.processInfo.systemUptime / 60)
    return "\(minutes/60)h \(minutes%60)m"
  }
  var architecture: String {
    #if arch(arm64)
      return "ARM64"
    #else
      return "Intel"
    #endif
  }
  var thermal: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "Nominal"
    case .fair: return "Fair"
    case .serious: return "Serious"
    case .critical: return "Critical"
    @unknown default: return "Unknown"
    }
  }
}
func byteParts(_ value: UInt64) -> (String, String) {
  let units = ["B", "KB", "MB", "GB", "TB"]
  var v = Double(value)
  var unit = 0
  while v >= 1024 && unit < 4 {
    v /= 1024
    unit += 1
  }
  return (unit == 0 ? String(Int(v)) : String(format: v >= 100 ? "%.1f" : "%.2f", v), units[unit])
}
func shortCount(_ value: UInt64) -> String {
  value >= 1_000_000
    ? String(format: "%.2fM", Double(value) / 1_000_000)
    : value >= 1000 ? String(format: "%.1fK", Double(value) / 1000) : String(value)
}

struct HistoryPlot: View {
  let points: [Point]
  let metric: Metric
  let range: Int
  let theme: MonitorTheme
  let physical: Double
  @State private var hover: CGFloat?
  var body: some View {
    GeometryReader { g in
      let width = max(1, g.size.width - 32)
      let height = max(1, g.size.height - 18)
      let end = points.last?.date ?? Date()
      let start = end.addingTimeInterval(Double(-range * 60))
      let visible = points.filter { $0.date >= start }
      let mirrored = metric == .disk || metric == .network
      let maxValue =
        metric == .cpu
        ? 100
        : metric == .memory
          ? 1
          : max(1, (visible.map { metric == .energy ? $0.a : max($0.a, $0.b) }.max() ?? 1) * 1.15)
      ZStack(alignment: .topLeading) {
        Canvas { ctx, size in
          for i in 0...2 {
            let y = CGFloat(i) * height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
            ctx.stroke(
              path, with: .color(theme.border), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
          }
          let baseline = mirrored ? height / 2 : height
          func coords(_ second: Bool) -> [CGPoint] {
            visible.map { p in
              let value: Double
              if metric == .memory {
                value = p.b == 4 ? 0.85 : p.b == 2 ? 0.5 : p.b == 1 ? 0.3 : 0
              } else if metric == .cpu {
                value = second ? p.b : p.a + p.b
              } else {
                value = second ? p.b : p.a
              }
              let x = p.date.timeIntervalSince(start) / Double(range * 60) * width
              let y =
                mirrored
                ? baseline + (second ? 1 : -1) * CGFloat(value / maxValue) * height / 2
                : height - CGFloat(value / maxValue) * height
              return CGPoint(x: x, y: y)
            }
          }
          func draw(_ values: [CGPoint], _ color: Color) {
            guard let first = values.first, let last = values.last else { return }
            var line = Path()
            line.move(to: first)
            for point in values.dropFirst() { line.addLine(to: point) }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: baseline))
            area.addLine(to: CGPoint(x: first.x, y: baseline))
            area.closeSubpath()
            ctx.fill(area, with: .color(color.opacity(0.16)))
            ctx.stroke(
              line, with: .color(color),
              style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
          }
          draw(
            coords(false),
            metric == .memory
              ? (visible.last?.b == 2
                ? theme.amber : visible.last?.b == 4 ? theme.coral : theme.green) : theme.blue)
          if metric == .cpu || mirrored { draw(coords(true), theme.coral) }
          if let hover {
            var line = Path()
            line.move(to: CGPoint(x: min(width, hover), y: 0))
            line.addLine(to: CGPoint(x: min(width, hover), y: height))
            ctx.stroke(
              line, with: .color(theme.tertiary.opacity(0.5)),
              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
          }
        }
        VStack {
          Text(metric == .memory ? "High" : metric == .cpu ? "100%" : shortAxis(maxValue))
          Spacer()
          Text(
            metric == .memory
              ? "Med" : mirrored ? "0" : metric == .cpu ? "50%" : shortAxis(maxValue / 2))
          Spacer()
          Text(metric == .memory ? "Low" : mirrored ? "−" + shortAxis(maxValue) : "0")
        }.font(.system(size: 8)).foregroundStyle(theme.tertiary).frame(
          width: 28, height: height, alignment: .trailing
        ).offset(x: width + 4)
        HStack {
          Text("−\(range*60) sec")
          Spacer()
          Text("−\(range*30) sec")
          Spacer()
          Text("Now")
        }.font(.system(size: 8)).foregroundStyle(theme.tertiary).frame(width: width).offset(
          y: height + 6)
        if let hover,
          let point = visible.min(by: {
            abs($0.date.timeIntervalSince(start) / Double(range * 60) * width - hover)
              < abs($1.date.timeIntervalSince(start) / Double(range * 60) * width - hover)
          })
        {
          Text(
            metric == .memory
              ? (point.b == 1 ? "Normal" : point.b == 2 ? "Moderate" : "High")
              : metric == .cpu || metric == .energy
                ? String(format: "%.1f%%", metric == .cpu ? point.a + point.b : point.a)
                : bytes(UInt64(max(0, point.a))) + "/s"
          ).font(.system(size: 10)).padding(6).background(
            theme.subtle, in: RoundedRectangle(cornerRadius: 5)
          ).offset(x: min(max(0, hover - 30), max(0, width - 85)), y: 3)
        }
      }.onContinuousHover { phase in
        switch phase {
        case .active(let location): hover = location.x
        case .ended: hover = nil
        }
      }
    }.accessibilityElement(children: .ignore).accessibilityLabel(
      "\(metric.rawValue) history over \(range) minutes")
  }
  func shortAxis(_ value: Double) -> String {
    if metric == .energy { return String(Int(value)) }
    let part = byteParts(UInt64(max(0, value)))
    return String(format: "%.0f", Double(part.0) ?? 0) + String(part.1.prefix(1))
  }
}
struct BatterySparkline: View {
  let points: [Point]
  let color: Color
  var body: some View {
    Canvas { ctx, size in
      let valid = points.filter { $0.b >= 0 }
      guard let first = valid.first else { return }
      let span = max(1, (valid.last?.date.timeIntervalSince(first.date) ?? 0))
      var line = Path()
      for (i, p) in valid.enumerated() {
        let pos = CGPoint(
          x: p.date.timeIntervalSince(first.date) / span * size.width,
          y: size.height * (1 - p.b / 110))
        if i == 0 { line.move(to: pos) } else { line.addLine(to: pos) }
      }
      var area = line
      area.addLine(to: CGPoint(x: size.width, y: size.height))
      area.addLine(to: CGPoint(x: 0, y: size.height))
      area.closeSubpath()
      ctx.fill(area, with: .color(color.opacity(0.15)))
      ctx.stroke(line, with: .color(color), lineWidth: 1)
    }
  }
}
