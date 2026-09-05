import AppKit
import Darwin
import Foundation
import SystemBridge

enum Metric: String, CaseIterable, Identifiable {
  case cpu = "CPU"
  case memory = "Memory"
  case energy = "Energy"
  case disk = "Disk"
  case network = "Network"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .energy: return "bolt"
    case .disk: return "internaldrive"
    case .network: return "wifi"
    }
  }
  var subtitle: String {
    switch self {
    case .cpu: return "A little clarity. A lot of processing power."
    case .memory: return "Space for everything you’re working on."
    case .energy: return "A closer look at power and efficiency."
    case .disk: return "Every read. Every write. In sight."
    case .network: return "Keep a pulse on what’s flowing."
    }
  }
}
struct ProcessRow: Identifiable, Codable {
  var id: Int32
  var parent: Int32
  var uid: UInt32
  var start: UInt64
  var name: String
  var user: String
  var cpu: Double
  var cpuTime: Double
  var memory: UInt64
  var resident: UInt64
  var threads: UInt32
  var read: UInt64
  var written: UInt64
  var isApp: Bool
  var accessible: Bool
  var kind: String
  var networkReceived: UInt64? = nil
  var networkSent: UInt64? = nil
  var ioAccessible: Bool
}
struct Point: Identifiable {
  let id = UUID()
  let date: Date
  let a: Double
  let b: Double
}
struct Snapshot {
  var processes: [ProcessRow]
  var system: AMSystem
}
func bytes(_ value: UInt64) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
}
func duration(_ seconds: Double) -> String {
  let s = Int(max(0, seconds))
  return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}
func csvCell(_ value: String) -> String {
  "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
final class Collector: @unchecked Sendable {
  var old: [Int32: AMProcess] = [:]
  var network: [Int32: (UInt64, ProcessNetworkCounters)] = [:]
  var networkDate = Date.distantPast
  var time = Date()
  func collect() -> Snapshot {
    let now = Date()
    let elapsed = max(now.timeIntervalSince(time), 0.001)
    var buffer = [AMProcess](repeating: AMProcess(), count: max(256, Int(am_processes(nil, 0))))
    let count = am_processes(&buffer, Int32(buffer.count))
    if now.timeIntervalSince(networkDate) >= 5 {
      let counters = readProcessNetwork()
      network = Dictionary(
        uniqueKeysWithValues: buffer.prefix(Int(count)).compactMap {
          p -> (Int32, (UInt64, ProcessNetworkCounters))? in
          guard let counter = counters[p.pid] else { return nil }
          return (p.pid, (p.start, counter))
        })
      networkDate = now
    }
    var next: [Int32: AMProcess] = [:]
    let rows = buffer.prefix(Int(count)).map { p -> ProcessRow in
      next[p.pid] = p
      let previous = old[p.pid]
      let cpu: Double
      if let previous, previous.start == p.start, p.cpu >= previous.cpu {
        cpu = Double(p.cpu - previous.cpu) / 1e9 / elapsed * 100
      } else {
        cpu = 0
      }
      var n = p.name
      let name = withUnsafePointer(to: &n) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
      }
      let user = getpwuid(p.uid).map { String(cString: $0.pointee.pw_name) } ?? String(p.uid)
      let networkCounters = network[p.pid].flatMap { $0.0 == p.start ? $0.1 : nil }
      return ProcessRow(
        id: p.pid, parent: p.ppid, uid: p.uid, start: p.start, name: name, user: user, cpu: cpu,
        cpuTime: Double(p.cpu) / 1e9, memory: p.footprint > 0 ? p.footprint : p.resident,
        resident: p.resident, threads: p.threads, read: p.read, written: p.written, isApp: false,
        accessible: p.accessible != 0, kind: p.translated != 0 ? "Intel" : nativeKind,
        networkReceived: networkCounters?.received, networkSent: networkCounters?.sent,
        ioAccessible: p.ioAccessible != 0)
    }
    old = next
    time = now
    var system = AMSystem()
    am_system(&system)
    return Snapshot(processes: rows, system: system)
  }
}
@MainActor final class Monitor: ObservableObject {
  @Published var rows: [ProcessRow] = []
  @Published var system = AMSystem()
  @Published var histories: [Metric: [Point]] = [:]
  @Published var paused = false
  @Published var interval = 2.0
  @Published var lastUpdate: Date?
  @Published var userCPU = 0.0
  @Published var systemCPU = 0.0
  @Published var readRate = 0.0
  @Published var writeRate = 0.0
  @Published var receiveRate = 0.0
  @Published var sendRate = 0.0
  @Published var packetReceiveRate = 0.0
  @Published var packetSendRate = 0.0
  @Published var error: String?
  private let collector = Collector()
  private var task: Task<Void, Never>?
  private var previous: AMSystem?
  private var previousDate: Date?
  private var diskPrevious: [Int32: ProcessRow] = [:]
  init(startAutomatically: Bool = true) {
    system.battery = -1
    guard startAutomatically else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if !self.paused { await self.refresh() }
        try? await Task.sleep(for: .seconds(self.interval))
      }
    }
  }
  func refresh() async {
    let collector = self.collector
    let snapshot = await Task.detached(priority: .utility) { collector.collect() }.value
    let now = Date()
    let dt = max(now.timeIntervalSince(previousDate ?? now), 0.001)
    if let prev = previous {
      let u = Double(
        UInt32(truncatingIfNeeded: snapshot.system.user) &- UInt32(truncatingIfNeeded: prev.user))
      let s = Double(
        UInt32(truncatingIfNeeded: snapshot.system.system)
          &- UInt32(truncatingIfNeeded: prev.system))
      let i = Double(
        UInt32(truncatingIfNeeded: snapshot.system.idle) &- UInt32(truncatingIfNeeded: prev.idle))
      let total = max(1, u + s + i)
      userCPU = u / total * 100
      systemCPU = s / total * 100
      receiveRate =
        Double(
          snapshot.system.received >= prev.received ? snapshot.system.received - prev.received : 0)
        / dt
      sendRate =
        Double(snapshot.system.sent >= prev.sent ? snapshot.system.sent - prev.sent : 0) / dt
    }
    if let prev = previous {
      packetReceiveRate =
        Double(
          snapshot.system.packetsIn >= prev.packetsIn
            ? snapshot.system.packetsIn - prev.packetsIn : 0) / dt
      packetSendRate =
        Double(
          snapshot.system.packetsOut >= prev.packetsOut
            ? snapshot.system.packetsOut - prev.packetsOut : 0) / dt
    }
    var dr: UInt64 = 0
    var dw: UInt64 = 0
    for p in snapshot.processes {
      if let old = diskPrevious[p.id], old.start == p.start {
        dr += p.read >= old.read ? p.read - old.read : 0
        dw += p.written >= old.written ? p.written - old.written : 0
      }
    }
    readRate = Double(dr) / dt
    writeRate = Double(dw) / dt
    let apps = Set(
      NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(
        \.processIdentifier))
    rows = snapshot.processes.map {
      var p = $0
      p.isApp = apps.contains(p.id)
      return p
    }
    system = snapshot.system
    let used = Double(system.active + system.wired + system.compressed)
    let values: [(Metric, Double, Double)] = [
      (.cpu, userCPU, systemCPU), (.memory, used, Double(system.pressure)),
      (.energy, rows.filter(\.isApp).reduce(0) { $0 + $1.cpu }, Double(system.battery)),
      (.disk, readRate, writeRate),
      (.network, receiveRate, sendRate),
    ]
    for (metric, a, b) in values {
      histories[metric, default: []].append(Point(date: now, a: a, b: b))
      histories[metric]?.removeAll { $0.date < now.addingTimeInterval(-900) }
    }
    previous = system
    previousDate = now
    lastUpdate = now
    diskPrevious = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
  }
  func terminate(_ row: ProcessRow, force: Bool) {
    guard row.id > 1, row.id != getpid(), row.uid == getuid() else {
      error = "Only other processes owned by your account can be stopped."
      return
    }
    guard processStillMatches(row) else {
      error = "This process has exited or its PID has been reused."
      return
    }
    if kill(row.id, force ? SIGKILL : SIGTERM) != 0 { error = String(cString: strerror(errno)) }
  }
  func exportJSON(_ rows: [ProcessRow]) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Activity-Monitor.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: url, options: .atomic)
      } catch { self.error = error.localizedDescription }
    }
  }

  func export(_ rows: [ProcessRow]) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Activity-Monitor.csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    if panel.runModal() == .OK, let url = panel.url {
      let csv = processCSV(rows)
      do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

func processStillMatches(_ row: ProcessRow) -> Bool {
  var check = proc_bsdinfo()
  let size = Int32(MemoryLayout<proc_bsdinfo>.size)
  return proc_pidinfo(row.id, PROC_PIDTBSDINFO, 0, &check, size) == size
    && check.pbi_start_tvsec * 1_000_000 + check.pbi_start_tvusec == row.start
    && check.pbi_uid == row.uid
}

func processCSV(_ rows: [ProcessRow]) -> String {
  let header =
    "Name,PID,User,CPU %,CPU seconds,Memory bytes,Threads,Bytes read,Bytes written,Network bytes received,Network bytes sent\n"
  return header
    + rows.map { p in
      [
        csvCell(p.name), String(p.id), csvCell(p.user),
        p.accessible ? String(format: "%.2f", p.cpu) : "", p.accessible ? String(p.cpuTime) : "",
        p.accessible ? String(p.memory) : "", p.accessible ? String(p.threads) : "",
        p.ioAccessible ? String(p.read) : "", p.ioAccessible ? String(p.written) : "",
        p.networkReceived.map(String.init) ?? "", p.networkSent.map(String.init) ?? "",
      ].joined(separator: ",")
    }.joined(separator: "\n")
}

var nativeKind: String {
  #if arch(arm64)
    return "Apple"
  #else
    return "Intel"
  #endif
}
