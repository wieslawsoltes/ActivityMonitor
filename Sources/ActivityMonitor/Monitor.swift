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
  case gpu = "GPU"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .energy: return "bolt"
    case .disk: return "internaldrive"
    case .network: return "wifi"
    case .gpu: return "square.3.layers.3d"
    }
  }
  var subtitle: String {
    switch self {
    case .cpu: return "A little clarity. A lot of processing power."
    case .memory: return "Space for everything you’re working on."
    case .energy: return "A closer look at power and efficiency."
    case .disk: return "Every read. Every write. In sight."
    case .network: return "Keep a pulse on what’s flowing."
    case .gpu: return "Graphics and compute, across your Mac."
    }
  }
}
struct ProcessRow: Identifiable, Codable, Equatable {
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
  var gpuPercent: Double? = nil
  var gpuTime: Double? = nil
  var details = ProcessDetails()
  var executableName: String? = nil
  var gpuWaiting = false
  // Optional for compatibility with older saved snapshots and supplied process rows.
  var cpuSampleAvailable: Bool? = nil
  var memoryUsesResidentFallback: Bool? = nil
  var gpuAvailability: String {
    gpuPercent != nil
      ? "GPU counters across all reporting devices"
      : gpuWaiting
        ? "Waiting for a second GPU sample" : "GPU counters unavailable for this process"
  }
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
  var gpuDevices: [GPUDeviceSample] = []
  var cpuCores = CPUCoreSample()
}
func bytes(_ value: UInt64) -> String {
  if value > UInt64(Int64.max) {
    return String(format: "%.1f EiB", Double(value) / 1_152_921_504_606_846_976)
  }
  // Formatters are expensive to construct and must not be shared across threads.
  let key = "ActivityMonitor.byteFormatter"
  let formatter: ByteCountFormatter
  if let cached = Thread.current.threadDictionary[key] as? ByteCountFormatter {
    formatter = cached
  } else {
    formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    Thread.current.threadDictionary[key] = formatter
  }
  return formatter.string(fromByteCount: Int64(clamping: value))
}
func duration(_ seconds: Double) -> String {
  guard seconds.isFinite else { return "—" }
  guard seconds < Double(Int.max) else { return String(format: "%.0f s", seconds) }
  let s = Int(max(0, seconds))
  return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}
func csvCell(_ value: String) -> String {
  "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
final class Collector: @unchecked Sendable {
  var old: [Int32: AMProcess] = [:]
  private let networkSampler = ProcessNetworkSampler()
  var time = Date()
  private var users: [UInt32: String] = [:]
  private let gpuReader = GPUHardwareReader()
  private var gpuTracker = GPUProcessTracker()
  private var cpuTracker = CPUCoreTracker()
  private let detailsCollector = ProcessDetailsCollector()
  func collect(details: Bool = false) -> Snapshot {
    let now = Date()
    let elapsed = max(now.timeIntervalSince(time), 0.001)
    var buffer = [AMProcess](repeating: AMProcess(), count: max(256, Int(am_processes(nil, 0))))
    let count = am_processes(&buffer, Int32(buffer.count))
    let identities = Dictionary(
      uniqueKeysWithValues: buffer.prefix(Int(count)).map { ($0.pid, $0.start) })
    let network = networkSampler.collect(identities: identities, now: now)
    let gpu = gpuReader.read()
    let gpuProcesses = gpuTracker.update(
      gpu,
      identities: identities)
    let detailsByPID =
      details ? detailsCollector.collect(Array(buffer.prefix(Int(count))), now: now) : [:]
    var next: [Int32: AMProcess] = [:]
    let rows = buffer.prefix(Int(count)).map { p -> ProcessRow in
      next[p.pid] = p
      let previous = old[p.pid]
      let cpu = CPUAccounting.sampledProcessPercent(
        current: p, previous: previous, elapsed: elapsed)
      var n = p.name
      let name = withUnsafePointer(to: &n) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
      }
      let user: String
      if let cached = users[p.uid] {
        user = cached
      } else {
        user = getpwuid(p.uid).map { String(cString: $0.pointee.pw_name) } ?? String(p.uid)
        users[p.uid] = user
      }
      let networkCounters = network[p.pid]
      var row = ProcessRow(
        id: p.pid, parent: p.ppid, uid: p.uid, start: p.start, name: name, user: user,
        cpu: cpu ?? 0,
        cpuTime: Double(p.cpu) / 1e9, memory: p.ioAccessible != 0 ? p.footprint : p.resident,
        resident: p.resident, threads: p.threads, read: p.read, written: p.written, isApp: false,
        accessible: p.accessible != 0, kind: p.translated != 0 ? "Intel" : nativeKind,
        networkReceived: networkCounters?.received, networkSent: networkCounters?.sent,
        ioAccessible: p.ioAccessible != 0, gpuPercent: gpuProcesses[p.pid]?.percent,
        gpuTime: gpuProcesses[p.pid]?.seconds, gpuWaiting: gpuProcesses[p.pid]?.waiting ?? false)
      row.executableName = name
      row.cpuSampleAvailable = cpu != nil
      row.memoryUsesResidentFallback = p.ioAccessible == 0 && p.accessible != 0
      row.details = detailsByPID[p.pid] ?? ProcessDetails()
      row.details.packetsIn = networkCounters?.packetsIn
      row.details.packetsOut = networkCounters?.packetsOut
      row.details.wakeups = ProcessDetails.wakeupRate(
        current: p, previous: previous, elapsed: elapsed)
      return row
    }
    old = next
    time = now
    var system = AMSystem()
    am_system(&system)
    return Snapshot(
      processes: rows, system: system, gpuDevices: gpu.devices, cpuCores: cpuTracker.read())
  }
}
@MainActor final class Monitor: ObservableObject {
  lazy var diagnostics = ProcessDiagnosticsCenter(monitor: self)
  @Published var rows: [ProcessRow] = []
  @Published var system = AMSystem()
  @Published var histories: [Metric: [Point]] = [:]
  @Published var gpuDevices: [GPUDeviceSample] = []
  @Published var gpuHistories: [UInt64: [GPUHistoryPoint]] = [:]
  @Published var selectedGPU: UInt64?
  var gpuDevice: GPUDeviceSample? { gpuDevices.first { $0.id == selectedGPU } ?? gpuDevices.first }
  @Published var paused = false
  @Published var interval = 1.0
  @Published var lastUpdate: Date?
  let cpuTopology = CPUTopology.current
  @Published private(set) var cpuCores: [CPUUsageSeries] = []
  @Published private(set) var cpuCoreStatus: String?
  private var cpuCoreHistory = CPUHistoryStore()
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
  private lazy var applications = ApplicationInventory()
  private var task: Task<Void, Never>?
  private var previous: AMSystem?
  private var previousDate: Date?
  private var refreshing = false
  private struct DiskCounters {
    let start: UInt64
    let read: UInt64
    let written: UInt64
  }
  private var diskPrevious: [Int32: DiskCounters] = [:]
  init(startAutomatically: Bool = true) {
    system.battery = -1
    guard startAutomatically else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        guard let interval = self?.interval else { return }
        if self?.paused == false { await self?.refresh() }
        try? await Task.sleep(for: .seconds(interval))
      }
    }
  }
  deinit { task?.cancel() }
  func refresh() async {
    guard !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    let collector = self.collector
    let snapshot = await Task.detached(priority: .utility) { collector.collect(details: true) }
      .value
    let now = Date()
    let dt = max(now.timeIntervalSince(previousDate ?? now), 0.001)
    if let prev = previous {
      let cpu = CPUAccounting.systemPercent(current: snapshot.system, previous: prev)
      userCPU = cpu.user
      systemCPU = cpu.system
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
    applications.refreshIfNeeded()
    let apps = applications.regularProcesses
    rows = snapshot.processes.map {
      var p = $0
      p.isApp = apps.contains(p.id)
      p.name = ProcessDisplayName.resolve(
        executable: p.name,
        application: applications.processStarts[p.id] == p.start ? applications.names[p.id] : nil)
      return p
    }
    ProcessIconCache.retain(
      identities: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.start) }))
    system = snapshot.system
    cpuCoreStatus = snapshot.cpuCores.status
    if snapshot.cpuCores.readings.isEmpty {
      cpuCoreHistory.unavailable(at: now)
    } else {
      cpuCoreHistory.append(snapshot.cpuCores.readings, at: now)
    }
    cpuCores = cpuCoreHistory.series
    updateGPU(snapshot.gpuDevices, date: now)
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
    diskPrevious = Dictionary(
      uniqueKeysWithValues: rows.map {
        ($0.id, DiskCounters(start: $0.start, read: $0.read, written: $0.written))
      })
  }
  func updateGPU(_ devices: [GPUDeviceSample], date: Date) {
    let connected = Set(devices.map(\.id))
    let missing = gpuDevices.filter { !connected.contains($0.id) }.map { device in
      var disconnected = device
      disconnected.connected = false
      disconnected.utilization = nil
      disconnected.renderer = nil
      disconnected.tiler = nil
      disconnected.memoryUsed = nil
      disconnected.memoryAllocated = nil
      return disconnected
    }
    gpuDevices = devices + missing
    if selectedGPU == nil { selectedGPU = gpuDevices.first?.id }
    for device in gpuDevices {
      gpuHistories[device.id, default: []].append(
        GPUHistoryPoint(date: date, utilization: device.utilization))
      gpuHistories[device.id]?.removeAll { $0.date < date.addingTimeInterval(-900) }
    }
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
  func exportGPU(_ rows: [ProcessRow], usage: [Int32: ProcessSubtreeUsage]? = nil) {
    // Freeze every field together before the save panel can run another sampling turn.
    var snapshot = GPUExportSnapshot(
      capturedAt: lastUpdate, selectedDevice: gpuDevice?.id,
      devices: gpuDevices,
      history: Dictionary(
        uniqueKeysWithValues: gpuHistories.map { (String($0.key), $0.value) }), processes: rows)
    if let usage {
      snapshot.subtreeUsage = Dictionary(
        uniqueKeysWithValues: rows.compactMap { row in
          usage[row.id].map { (String(row.id), ProcessUsageExport($0)) }
        })
      snapshot.subtreeScope = ProcessSubtreeUsage.scopeHelp
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Activity-Monitor-GPU.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
      } catch { self.error = error.localizedDescription }
    }
  }
  func exportJSON(_ rows: [ProcessRow], usage: [Int32: ProcessSubtreeUsage]? = nil) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Activity-Monitor.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try processJSON(rows, usage: usage).write(to: url, options: .atomic)
      } catch { self.error = error.localizedDescription }
    }
  }

  func export(
    _ rows: [ProcessRow], includeHierarchy: Bool = false,
    usage: [Int32: ProcessSubtreeUsage]? = nil
  ) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Activity-Monitor.csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    if panel.runModal() == .OK, let url = panel.url {
      let csv = processCSV(rows, includeHierarchy: includeHierarchy, usage: usage)
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

func processCSV(
  _ rows: [ProcessRow], includeHierarchy: Bool = false,
  usage: [Int32: ProcessSubtreeUsage]? = nil
) -> String {
  var header =
    "Name,PID,User,CPU %,CPU seconds,Memory bytes,Threads,Bytes read,Bytes written,Network bytes received,Network bytes sent,GPU %,Observed GPU seconds"
  if includeHierarchy || usage != nil { header += ",Parent PID" }
  if usage != nil {
    header += ",Subtree processes,Subtree resident fallback processes"
    for metric in ProcessUsageMetric.allCases {
      let title = "Subtree " + metric.exportTitle
      header += ",\(title),\(title) reporting processes,\(title) status"
    }
  }
  let lines: [String] = rows.map { p in
    var cells: [String] = [
      csvCell(p.name), String(p.id), csvCell(p.user),
      p.accessible && p.cpuSampleAvailable != false ? String(format: "%.2f", p.cpu) : "",
      p.accessible ? String(p.cpuTime) : "",
      p.accessible ? String(p.memory) : "", p.accessible ? String(p.threads) : "",
      p.ioAccessible ? String(p.read) : "", p.ioAccessible ? String(p.written) : "",
      p.networkReceived.map(String.init) ?? "", p.networkSent.map(String.init) ?? "",
      p.gpuPercent.map { String(format: "%.4f", $0) } ?? "", p.gpuTime.map { String($0) } ?? "",
    ]
    if includeHierarchy || usage != nil { cells.append(String(p.parent)) }
    if let usage {
      let total = usage[p.id]
      cells.append(total.map { String($0.processCount) } ?? "")
      cells.append(total.map { String($0.residentFallbackCount) } ?? "")
      for metric in ProcessUsageMetric.allCases {
        let counter = total.map {
          ProcessUsageExportCounter($0[metric], processCount: $0.processCount, metric: metric)
        }
        cells.append(counter?.value?.csvValue ?? "")
        cells.append(counter.map { String($0.reportedProcesses) } ?? "")
        cells.append(counter?.status ?? "unavailable")
      }
    }
    return cells.joined(separator: ",")
  }
  return header + "\n" + lines.joined(separator: "\n")
}

var nativeKind: String {
  #if arch(arm64)
    return "Apple"
  #else
    return "Intel"
  #endif
}

/// Application membership changes on workspace events, not on every metric sample.
@MainActor private final class ApplicationInventory {
  private(set) var regularProcesses: Set<Int32> = []
  private(set) var names: [Int32: String] = [:]
  private(set) var processStarts: [Int32: UInt64] = [:]
  private var refreshed = Date.distantPast
  func refreshIfNeeded() {
    if Date().timeIntervalSince(refreshed) >= 5 { refresh() }
  }
  private var observers: [NSObjectProtocol] = []
  init() {
    refresh()
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didActivateApplicationNotification,
    ] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor [weak self] in self?.refresh() }
        })
    }
  }
  private func refresh() {
    let apps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
    regularProcesses = Set(apps.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
    names = Dictionary(
      uniqueKeysWithValues: apps.compactMap { app in
        app.localizedName.map { (app.processIdentifier, $0) }
      })
    processStarts = Dictionary(
      uniqueKeysWithValues: apps.compactMap { app in
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size else {
          return nil
        }
        return (app.processIdentifier, info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
      })
    refreshed = Date()
  }
  deinit {
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
}

struct GPUExportSnapshot: Codable {
  var capturedAt: Date?
  var selectedDevice: UInt64?
  var devices: [GPUDeviceSample]
  var history: [String: [GPUHistoryPoint]]
  var processes: [ProcessRow]
  var processScope = "All reporting GPU devices; filtered process list"
  var processRateUnit = "Driver-reported GPU seconds per elapsed second, multiplied by 100"
  var processTimeScope = "Valid sampled driver-time deltas observed during this session"
  var subtreeUsage: [String: ProcessUsageExport]? = nil
  var subtreeScope: String? = nil
}
