import AppKit
import Combine
import Darwin
import SystemBridge

struct ProcessActivitySample: Codable {
  var date: Date
  var cpu: Double?
  var memory: UInt64?
  var gpu: Double?
  var read: Double?
  var written: Double?
  var received: Double?
  var sent: Double?
  var wakeups: Double?
  static func rate(_ current: UInt64?, _ previous: UInt64?, elapsed: Double) -> Double? {
    guard let current, let previous, current >= previous, elapsed > 0, elapsed <= 30 else {
      return nil
    }
    return Double(current - previous) / elapsed
  }
}
enum ProcessReportKind: String, CaseIterable, Identifiable {
  case sample = "Sample process"
  case files = "Open files & ports"
  case memory = "Virtual memory"
  case arguments = "Launch arguments"
  case environment = "Environment"
  case signature = "Code signature"
  case entitlements = "Entitlements"
  var id: String { rawValue }
  func command(pid: Int32, path: String?) -> (String, [String])? {
    switch self {
    case .sample: return ("/usr/bin/sample", [String(pid), "1", "10"])
    case .files: return ("/usr/sbin/lsof", ["-n", "-P", "-p", String(pid)])
    case .memory: return ("/usr/bin/vmmap", [String(pid)])
    case .signature: return path.map { ("/usr/bin/codesign", ["-d", "--verbose=4", $0]) }
    case .entitlements:
      return path.map { ("/usr/bin/codesign", ["-d", "--entitlements", ":-", $0]) }
    case .arguments, .environment: return nil
    }
  }
}
struct ProcessReport: Codable {
  var title: String
  var date: Date
  var text: String
  var status: String
}
enum DiagnosticCommand {
  static let outputLimit = 4 * 1024 * 1024
  static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> (
    String, String
  ) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (error.localizedDescription, "Could not start") }
    let fd = pipe.fileHandleForReading.fileDescriptor
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16384)
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var reason: String?
    while true {
      let n = read(fd, &buffer, buffer.count)
      if n > 0 {
        let allowed = min(n, outputLimit - data.count)
        data.append(contentsOf: buffer.prefix(allowed))
        if allowed < n {
          reason = "Output limited to 4 MB"
          break
        }
      } else if n == 0 && !process.isRunning {
        break
      } else if n < 0 && errno != EAGAIN && errno != EINTR {
        reason = String(cString: strerror(errno))
        break
      }
      if Task.isCancelled {
        reason = "Cancelled"
        break
      }
      if ProcessInfo.processInfo.systemUptime > deadline {
        reason = "Timed out after \(Int(timeout)) seconds"
        break
      }
      if n <= 0 { Thread.sleep(forTimeInterval: 0.01) }
    }
    if process.isRunning && reason != nil {
      process.terminate()
      Thread.sleep(forTimeInterval: 0.1)
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()
    try? pipe.fileHandleForReading.close()
    return (
      String(decoding: data, as: UTF8.self),
      reason
        ?? (process.terminationStatus == 0
          ? "Completed" : "macOS tool exited with status \(process.terminationStatus)")
    )
  }
  static func arguments(pid: Int32, environment: Bool = false) -> (String, String) {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 1024 * 1024
    var data = [UInt8](repeating: 0, count: 1024 * 1024)
    guard sysctl(&mib, 3, &data, &size, nil, 0) == 0 else {
      return (String(cString: strerror(errno)), "Unavailable")
    }
    guard let parsed = parseArgumentBuffer(Data(data.prefix(size))) else {
      return ("The argument buffer was incomplete.", "Unavailable")
    }
    if environment {
      return (
        parsed.environment.joined(separator: "\n"), "Completed · May contain sensitive values"
      )
    }
    let values = parsed.arguments
    return (
      values.enumerated().map { "argv[\($0.offset)] = \($0.element)" }.joined(separator: "\n"),
      "Completed · Environment excluded"
    )
  }
  static func parseArguments(_ data: Data) -> [String]? { parseArgumentBuffer(data)?.arguments }
  static func parseArgumentBuffer(_ data: Data) -> (arguments: [String], environment: [String])? {
    guard data.count >= 4 else { return nil }
    let count = data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard count >= 0, count <= 16384 else { return nil }
    let bytes = Array(data)
    var offset = 4
    func next() -> String? {
      guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0) else { return nil }
      defer { offset = end + 1 }
      return String(decoding: bytes[offset..<end], as: UTF8.self)
    }
    guard next() != nil else { return nil }  // executable path preceding argv
    while offset < bytes.count && bytes[offset] == 0 { offset += 1 }
    var args: [String] = []
    for _ in 0..<count {
      guard let value = next() else { return nil }
      args.append(value)
    }
    var environment: [String] = []
    while offset < bytes.count, bytes[offset] != 0 {
      guard let entry = next() else { return nil }
      environment.append(entry)
    }
    return (args, environment)
  }
}

@MainActor final class ProcessDiagnosticSession: ObservableObject, Identifiable {
  let id: ProcessIdentity
  @Published private(set) var row: ProcessRow
  @Published var tab: DiagnosticTab = .overview
  @Published var range = 1
  let threadChartPresentation = CPUChartPresentation()
  @Published var showsThreadCPU = false {
    didSet {
      if !showsThreadCPU {
        threadWorker?.cancel()
        threadTracker.reset()
        threadEpoch += 1
      } else {
        refreshThreadActivity(force: true)
      }
    }
  }
  @Published private(set) var threadCPU: [CPUUsageSeries] = []
  @Published private(set) var threadCPUStatus: String?
  @Published private(set) var collectingThreadCPU = false
  private var threadHistory = CPUHistoryStore()
  private var threadTracker = ThreadCPUTracker()
  private var threadWorker: Task<Void, Never>?
  private var lastThreadRead = Date.distantPast
  private var threadEpoch = 0
  @Published var paused = false {
    didSet {
      if paused {
        threadTracker.reset()
        threadEpoch += 1
      }
    }
  }
  @Published var sourcePaused = false {
    didSet {
      if sourcePaused {
        threadTracker.reset()
        threadEpoch += 1
      }
    }
  }
  @Published private(set) var exited = false
  @Published private(set) var histories: [ProcessActivitySample] = []
  @Published private(set) var memoryHistory: [ProcessMemorySample] = []
  @Published private(set) var gpuMemoryHistory: [ProcessGPUMemorySample] = []
  @Published private(set) var gpuMemoryDevices: [GPUDeviceSample] = []
  @Published private(set) var fields: [DiagnosticField] = []
  @Published private(set) var sections: [DiagnosticTab: DiagnosticSection] = [:]
  @Published private(set) var collecting = false
  @Published private(set) var collectionStatus: String?
  @Published private(set) var report: ProcessReport?
  @Published private(set) var reporting = false
  @Published var pinned = false
  @Published var pinMetric: Metric = .cpu
  private var previous: ProcessRow?
  private var previousDate: Date?
  private var lastCollection = Date.distantPast
  private var collectedTab: DiagnosticTab?
  private var collection: Task<Void, Never>?
  private var reportWorker: Task<(String, String), Never>?
  private let threadReader: @Sendable (ProcessIdentity) -> ThreadCPUSnapshot
  private let reader: @Sendable (ProcessIdentity, DiagnosticTab) -> DiagnosticSnapshot
  init(
    row: ProcessRow,
    reader: @escaping @Sendable (ProcessIdentity, DiagnosticTab) -> DiagnosticSnapshot = {
      DiagnosticCollector.read(identity: $0, tab: $1)
    },
    threadReader: @escaping @Sendable (ProcessIdentity) -> ThreadCPUSnapshot = {
      ThreadCPUReader.read($0)
    }
  ) {
    self.row = row
    self.id = ProcessIdentity(row)
    self.reader = reader
    self.threadReader = threadReader
  }
  deinit {
    collection?.cancel()
    reportWorker?.cancel()
    threadWorker?.cancel()
  }
  var state: String {
    exited ? "Exited · Last snapshot" : paused ? "Paused" : sourcePaused ? "Monitor paused" : "Live"
  }
  private func appendMemory(_ sample: ProcessMemorySample) {
    if let index = memoryHistory.firstIndex(where: { $0.date == sample.date }) {
      // A diagnostic refresh can fill in private/shared bytes for the process sample
      // already collected by the live monitor.
      var merged = memoryHistory[index]
      merged.footprint = sample.footprint ?? merged.footprint
      merged.resident = sample.resident ?? merged.resident
      merged.privateBytes = sample.privateBytes ?? merged.privateBytes
      merged.sharedBytes = sample.sharedBytes ?? merged.sharedBytes
      merged.compressed = sample.compressed ?? merged.compressed
      merged.purgeable = sample.purgeable ?? merged.purgeable
      memoryHistory[index] = merged
      return
    }
    if memoryHistory.last?.date ?? .distantPast <= sample.date {
      memoryHistory.append(sample)
    } else {
      let index = memoryHistory.firstIndex { $0.date > sample.date } ?? memoryHistory.endIndex
      memoryHistory.insert(sample, at: index)
    }
    let cutoff = sample.date.addingTimeInterval(-900)
    memoryHistory.removeAll { $0.date < cutoff }
    if memoryHistory.count > 901 { memoryHistory.removeFirst(memoryHistory.count - 901) }
  }
  private func appendGPUMemory(_ sample: ProcessGPUMemorySample) {
    if let index = gpuMemoryHistory.firstIndex(where: { $0.date == sample.date }) {
      gpuMemoryHistory[index] = sample
    } else if gpuMemoryHistory.last?.date ?? .distantPast <= sample.date {
      gpuMemoryHistory.append(sample)
    } else {
      let index = gpuMemoryHistory.firstIndex { $0.date > sample.date } ?? gpuMemoryHistory.endIndex
      gpuMemoryHistory.insert(sample, at: index)
    }
    let cutoff = sample.date.addingTimeInterval(-900)
    gpuMemoryHistory.removeAll { $0.date < cutoff }
    if gpuMemoryHistory.count > 901 { gpuMemoryHistory.removeFirst(gpuMemoryHistory.count - 901) }
  }
  func accept(rows: [ProcessRow], date: Date, gpuDevices: [GPUDeviceSample] = []) {
    guard !exited else { return }
    guard let current = rows.first(where: { $0.id == id.pid && $0.start == id.start }) else {
      // An incomplete global sample is not proof of exit.
      if id.status() == .exited {
        exited = true
        reportWorker?.cancel()
      }
      return
    }
    guard !paused, !sourcePaused, date != previousDate else { return }
    let elapsed = previousDate.map { date.timeIntervalSince($0) } ?? 0
    let before = previous
    histories.append(
      .init(
        date: date, cpu: current.accessible ? current.cpu : nil,
        memory: current.accessible ? current.memory : nil, gpu: current.gpuPercent,
        read: ProcessActivitySample.rate(
          current.ioAccessible ? current.read : nil,
          before?.ioAccessible == true ? before?.read : nil, elapsed: elapsed),
        written: ProcessActivitySample.rate(
          current.ioAccessible ? current.written : nil,
          before?.ioAccessible == true ? before?.written : nil, elapsed: elapsed),
        received: ProcessActivitySample.rate(
          current.networkReceived, before?.networkReceived, elapsed: elapsed),
        sent: ProcessActivitySample.rate(
          current.networkSent, before?.networkSent, elapsed: elapsed),
        wakeups: current.details.wakeups))
    histories.removeAll { $0.date < date.addingTimeInterval(-900) }
    if histories.count > 3601 { histories.removeFirst(histories.count - 3601) }
    appendMemory(
      .init(
        date: date,
        footprint: current.accessible ? current.memory : nil,
        resident: current.accessible ? current.resident : nil,
        privateBytes: current.details.privateMemory,
        sharedBytes: current.details.sharedMemory,
        compressed: current.details.compressed,
        purgeable: current.details.purgeable))
    gpuMemoryDevices = gpuDevices
    appendGPUMemory(
      .init(
        date: date,
        used: aggregateGPUBytes(gpuDevices.map(\.memoryUsed)),
        allocated: aggregateGPUBytes(gpuDevices.map(\.memoryAllocated)),
        deviceCount: gpuDevices.count))
    previous = current
    previousDate = date
    row = current
  }
  func refreshThreadActivity(force: Bool = false) {
    guard showsThreadCPU, !collectingThreadCPU, !exited, !paused, !sourcePaused,
      force || Date().timeIntervalSince(lastThreadRead) >= 2
    else { return }
    collectingThreadCPU = true
    let identity = id
    let epoch = threadEpoch
    let read = threadReader
    threadWorker = Task { [weak self] in
      let snapshot = await Task.detached(priority: .utility) { read(identity) }
        .value
      guard let self else { return }
      self.collectingThreadCPU = false
      guard !Task.isCancelled, self.showsThreadCPU, !self.paused, !self.sourcePaused,
        !self.exited, self.threadEpoch == epoch
      else { return }
      self.lastThreadRead = snapshot.date
      self.threadCPUStatus = snapshot.status
      if snapshot.available {
        self.threadHistory.append(self.threadTracker.sample(snapshot), at: snapshot.date)
      } else {
        self.threadTracker.reset()
        self.threadHistory.unavailable(at: snapshot.date)
      }
      self.threadCPU = self.threadHistory.series
    }
  }
  func refreshDetails(force: Bool = false) {
    guard !collecting, !exited, force || (!paused && !sourcePaused) else { return }
    guard force || collectedTab != tab || Date().timeIntervalSince(lastCollection) >= 5 else {
      return
    }
    collecting = true
    let identity = id
    let requested = tab
    let reader = self.reader
    collection = Task { [weak self] in
      let snapshot = await Task.detached(priority: .utility) { reader(identity, requested) }.value
      guard let self else { return }
      self.collecting = false
      guard snapshot.valid, snapshot.identity == self.id else {
        if snapshot.identityStatus == .exited { self.exited = true }
        self.collectionStatus =
          snapshot.identityStatus == .exited
          ? "Process exited" : "Details unavailable: macOS could not verify process access"
        self.lastCollection = Date()
        self.collectedTab = requested
        return
      }
      self.collectionStatus = nil
      self.fields = snapshot.fields
      if let memory = snapshot.memory { self.appendMemory(memory) }
      if let section = snapshot.section { self.sections[requested] = section }
      self.collectedTab = requested
      self.lastCollection = Date()
      if self.tab != requested { self.refreshDetails(force: true) }
    }
  }
  func collectReport(_ kind: ProcessReportKind) {
    guard !reporting, !exited, id.matches() else { return }
    reporting = true
    tab = .reports
    let identity = id
    let path = fields.first { $0.name == "Executable" }?.value
    let worker = Task.detached(priority: .utility) {
      guard identity.matches() else { return ("The process has exited.", "Unavailable") }
      let result: (String, String)
      if kind == .arguments || kind == .environment {
        result = DiagnosticCommand.arguments(pid: identity.pid, environment: kind == .environment)
      } else if let command = kind.command(pid: identity.pid, path: path),
        path != "Unavailable" || (kind != .signature && kind != .entitlements)
      {
        result = DiagnosticCommand.run(command.0, command.1)
      } else {
        result = ("The executable path is unavailable.", "Unavailable")
      }
      guard identity.matches() else {
        return (
          "The process exited during collection. Output was discarded to avoid confusing reused process IDs.",
          "Process exited"
        )
      }
      return result
    }
    reportWorker = worker
    Task { [weak self] in
      let result = await worker.value
      guard let self else { return }
      self.report = .init(title: kind.rawValue, date: Date(), text: result.0, status: result.1)
      self.reporting = false
      self.reportWorker = nil
    }
  }
  func cancelReport() { reportWorker?.cancel() }
  func export() {
    struct Export: Codable {
      var identity: ProcessIdentity
      var process: ProcessRow
      var status: String
      var fields: [DiagnosticField]
      var history: [ProcessActivitySample]
      var memoryHistory: [ProcessMemorySample]
      var gpuMemoryHistory: [ProcessGPUMemorySample]
      var gpuMemoryDevices: [GPUDeviceSample]
      var sections: [String: DiagnosticSection]
      var report: ProcessReport?
      var threadCPU: [CPUUsageSeries]
    }
    let value = Export(
      identity: id, process: row, status: state, fields: fields, history: histories,
      memoryHistory: memoryHistory, gpuMemoryHistory: gpuMemoryHistory,
      gpuMemoryDevices: gpuMemoryDevices,
      sections: Dictionary(uniqueKeysWithValues: sections.map { ($0.key.rawValue, $0.value) }),
      report: report, threadCPU: threadCPU)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      try DiagnosticExport.save(encoder.encode(value), name: "Process-\(id.pid)-diagnostics.json")
    } catch {
      report = .init(
        title: "Export", date: Date(), text: error.localizedDescription, status: "Failed")
      tab = .reports
    }
  }
}
/// Sum a device counter only when every visible device reported it. A partial sum would
/// understate the machine total and make the chart look precise when one device is unknown.
func aggregateGPUBytes(_ values: [UInt64?]) -> UInt64? {
  guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
  var total: UInt64 = 0
  for value in values.compactMap({ $0 }) {
    let (next, overflow) = total.addingReportingOverflow(value)
    guard !overflow else { return nil }
    total = next
  }
  return total
}
enum DiagnosticExport {
  @MainActor static func save(_ data: Data, name: String) throws {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
  }
}
