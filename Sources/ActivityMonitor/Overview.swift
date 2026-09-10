import SwiftUI

struct MonitorOverview: View {
  @EnvironmentObject var monitor: Monitor
  let metric: Metric
  let range: Int
  let theme: MonitorTheme
  var used: UInt64 { monitor.system.active + monitor.system.wired + monitor.system.compressed }
  var appCPU: Double { monitor.rows.filter(\.isApp).reduce(0) { $0 + $1.cpu } }
  var width: CGFloat = 1068
  var expanded = false
  var condensed = false
  @State var individualCPU = false
  @State private var processorDetails = false
  private var dense: Bool { condensed || width < 1068 }
  var body: some View {
    if metric == .gpu {
      GPUOverview(
        range: range, theme: theme, width: width, expanded: expanded, condensed: condensed)
    } else if metric == .cpu && individualCPU {
      VStack(spacing: dense ? 10 : 14) {
        DesignCard(theme: theme, padding: dense ? 12 : 19) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 4) {
                Text("CPU by logical processor").font(.system(size: 13, weight: .semibold))
                Text(monitor.cpuTopology.summary).font(.system(size: 10)).foregroundStyle(
                  theme.secondary)
              }
              Spacer(minLength: 4)
              CPUChartModePicker(individual: $individualCPU, theme: theme)
            }
            CPUChartBrowser(
              series: monitor.cpuCores, range: range,
              end: monitor.lastUpdate ?? Date(), theme: theme, status: monitor.cpuCoreStatus)
            Text("Each chart: 0–100% · Select a processor to inspect its history")
              .font(.system(size: 10)).foregroundStyle(theme.tertiary)
          }
        }.frame(height: dense ? 330 : 350)
        DisclosureGroup("Breakdown & device details", isExpanded: $processorDetails) {
          if width >= 668 {
            HStack(spacing: 14) {
              DesignCard(theme: theme, padding: dense ? 12 : 20) { middleCard }
              DesignCard(theme: theme, padding: dense ? 12 : 20) { lastCard }
            }.frame(height: dense ? 148 : 213)
          } else {
            DesignCard(theme: theme, padding: 12) { middleCard }.frame(height: 148)
            DesignCard(theme: theme, padding: 12) { lastCard }.frame(height: 160)
          }
        }.font(.system(size: 12)).tint(theme.blue)
      }
    } else {
      AdaptiveOverviewPanels(width: width, expanded: expanded, condensed: condensed, theme: theme) {
        chartCard
      } detail: {
        middleCard
      } context: {
        lastCard
      }
    }
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
                ? "Total CPU load" : metric == .memory ? "Memory pressure" : "Application CPU load"
            ).font(.system(size: 12)).foregroundStyle(theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text(
                metric == .cpu
                  ? String(
                    format: "%.1f",
                    CPUAccounting.executionPercent(monitor.userCPU + monitor.systemCPU))
                  : metric == .memory ? byteParts(used).0 : String(format: "%.1f", appCPU)
              ).font(.system(size: dense ? 26 : 34, weight: .medium)).tracking(-1.3)
                .foregroundStyle(theme.text)
              Text(metric == .memory ? byteParts(used).1 : "%").font(.system(size: dense ? 14 : 18))
                .foregroundStyle(theme.secondary)
              Text(
                metric == .cpu
                  ? CPUAccounting.capacityLabel
                  : metric == .memory ? "used of \(bytes(monitor.system.physical))" : "CPU workload"
              ).font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.leading, 4)
            }
          }
        }
        Spacer(minLength: 4)
        if metric == .cpu {
          VStack(alignment: .trailing, spacing: 4) {
            CPUChartModePicker(individual: $individualCPU, theme: theme)
            HStack(spacing: 8) {
              dot("Total", theme.blue)
              dot("System", theme.coral)
            }
          }
        } else if metric == .memory {
          badge(pressureName, color: pressureColor)
        } else if !dense || (metric != .disk && metric != .network) {
          HStack(spacing: 12) {
            dot(
              metric == .cpu
                ? "Total" : metric == .energy ? "CPU workload" : metric == .disk ? "Read" : "In",
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
      ).padding(.top, dense ? 6 : 10)
    }.monospacedDigit()
      .help(
        metric == .cpu
          ? CPUAccounting.systemHelp : metric == .energy ? CPUAccounting.processHelp : "")
  }
  @ViewBuilder var middleCard: some View {
    switch metric {
    case .gpu: EmptyView()
    case .cpu:
      VStack(alignment: .leading, spacing: 0) {
        title("Usage breakdown")
        stacked([
          (monitor.userCPU, theme.blue), (monitor.systemCPU, theme.coral),
          (max(0, 100 - monitor.userCPU - monitor.systemCPU), theme.recessed),
        ]).padding(.top, dense ? 8 : 25)
        VStack(spacing: dense ? 6 : 12) {
          detail(
            "User", String(format: "%.2f%%", CPUAccounting.executionPercent(monitor.userCPU)),
            theme.blue)
          detail(
            "System", String(format: "%.2f%%", CPUAccounting.executionPercent(monitor.systemCPU)),
            theme.coral)
          detail(
            "Idle",
            String(
              format: "%.2f%%",
              CPUAccounting.executionPercent(max(0, 100 - monitor.userCPU - monitor.systemCPU))),
            theme.recessed)
        }.padding(.top, dense ? 8 : 21)
      }
    case .memory:
      VStack(alignment: .leading, spacing: 0) {
        title("Memory allocation")
        stacked([
          (Double(monitor.system.active), theme.blue), (Double(monitor.system.wired), theme.purple),
          (Double(monitor.system.compressed), theme.amber),
          (Double(monitor.system.free), theme.recessed),
        ]).padding(.top, dense ? 8 : 25)
        VStack(spacing: dense ? 6 : 10) {
          detail("Active memory", bytes(monitor.system.active), theme.blue)
          detail("Wired", bytes(monitor.system.wired), theme.purple)
          detail("Compressed", bytes(monitor.system.compressed), theme.amber)
          detail("Free", bytes(monitor.system.free), theme.recessed)
        }.padding(.top, dense ? 8 : 19)
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
              .system(size: dense ? 27 : 38, weight: .medium)
            ).tracking(-1.7)
            Text(monitor.system.battery < 0 ? "" : "%").font(.system(size: dense ? 16 : 22))
              .foregroundStyle(
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
        }.padding(.top, dense ? 8 : 19)
        Label(
          monitor.system.battery < 0
            ? "No battery installed"
            : monitor.system.charging != 0
              ? "Charging" : monitor.system.battery == 100 ? "Fully charged" : "Not charging",
          systemImage: "checkmark.circle"
        ).font(.system(size: 10)).foregroundStyle(theme.green).padding(.top, 5)
        BatterySparkline(points: monitor.histories[.energy] ?? [], color: theme.green).frame(
          height: dense ? 16 : 29
        ).padding(.top, dense ? 8 : 22)
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
        ).padding(.top, dense ? 8 : 23)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, dense ? 8 : 16)
        transfer(
          metric == .disk ? "Written" : "Sent",
          metric == .disk ? monitor.rows.reduce(0) { $0 + $1.written } : monitor.system.sent,
          theme.coral)
      }
    }
  }
  @ViewBuilder var lastCard: some View {
    switch metric {
    case .gpu: EmptyView()
    case .cpu:
      VStack(alignment: .leading, spacing: dense ? 4 : 10) {
        HStack {
          title("System at a glance")
          Spacer()
          Image(systemName: "cpu").font(.system(size: 20, weight: .ultraLight)).foregroundStyle(
            theme.tertiary)
        }
        HStack {
          mini(monitor.rows.reduce(0) { $0 + Int($1.threads) }.formatted(), "Threads")
          mini(monitor.rows.count.formatted(), "Processes")
        }
        HStack {
          mini(architecture, "Architecture")
          mini(bytes(monitor.system.physical), "Physical memory")
        }
        Text(monitor.cpuTopology.summary).font(.system(size: dense ? 9 : 10))
          .foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
          .help(
            "Physical cores and logical processors are hardware counts. Threads above are software threads across readable processes."
          )
      }
    case .memory:
      VStack(alignment: .leading, spacing: dense ? 10 : 23) {
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
        Text(uptime).font(.system(size: dense ? 23 : 28, weight: .medium)).tracking(-0.8).padding(
          .top, dense ? 8 : 20)
        Text("System uptime").font(.system(size: 10)).foregroundStyle(theme.secondary).padding(
          .top, 5)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, dense ? 8 : 18)
        VStack(spacing: dense ? 6 : 12) {
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
        }.padding(.top, dense ? 8 : 25)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, dense ? 8 : 20)
        VStack(spacing: dense ? 6 : 12) {
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
        }.padding(.top, dense ? 8 : 25)
        Rectangle().fill(theme.separator).frame(height: 1).padding(.vertical, dense ? 8 : 20)
        VStack(spacing: dense ? 6 : 12) {
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
    }.font(.system(size: dense ? 11 : 12))
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
    }.frame(height: dense ? 5 : 7)
  }
  func mini(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: dense ? 3 : 5) {
      Text(value).font(.system(size: dense ? 18 : 23, weight: .medium)).tracking(-0.5)
        .foregroundStyle(
          theme.text
        ).monospacedDigit()
      Text(label).font(.system(size: 11)).foregroundStyle(theme.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func transfer(_ name: String, _ value: UInt64, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: dense ? 3 : 5) {
      dot(name, color)
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(byteParts(value).0).font(.system(size: dense ? 21 : 27, weight: .medium)).tracking(
          -0.7)
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
        Text(byteParts(UInt64(max(0, value))).0).font(
          .system(size: dense ? 23 : 28, weight: .medium)
        ).tracking(
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
  @EnvironmentObject var monitor: Monitor
  let points: [Point]
  let metric: Metric
  let range: Int
  let theme: MonitorTheme
  let physical: Double
  var body: some View {
    TelemetryChart(
      samples: TelemetryData.samples(
        points: points, metric: metric, maximumGap: max(10, monitor.interval * 2.5)),
      metric: metric, range: range, end: points.last?.date ?? Date(), theme: theme)
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
