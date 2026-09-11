import AppKit
import Darwin
import IOKit.pwr_mgt
import SystemBridge

enum ProcessIdentityStatus: String, Codable { case matching, exited, unavailable }
struct ProcessIdentity: Hashable, Codable {
  let pid: Int32
  let start: UInt64
  init(_ row: ProcessRow) {
    pid = row.id
    start = row.start
  }
  func status() -> ProcessIdentityStatus {
    var current: UInt64 = 0
    let error = am_process_identity(pid, &current)
    if error == ESRCH { return .exited }
    if error != 0 { return .unavailable }
    return current == start ? .matching : .exited
  }
  func matches() -> Bool { status() == .matching }
}
enum DiagnosticTab: String, CaseIterable, Identifiable, Codable {
  case overview = "Overview"
  case cpu = "CPU"
  case memory = "Memory"
  case energy = "Energy"
  case disk = "Disk"
  case network = "Network"
  case gpu = "GPU"
  case threads = "Threads"
  case files = "Open files"
  case connections = "Connections"
  case ports = "Mach ports"
  case fileports = "Fileports"
  case maps = "Memory map"
  case images = "Mapped images"
  case reports = "Reports"
  var id: String { rawValue }
  var metric: Metric? { Metric(rawValue: rawValue) }
  var icon: String {
    if let metric { return metric.icon }
    switch self {
    case .overview: return "info.circle"
    case .threads: return "line.3.horizontal.decrease"
    case .files: return "folder"
    case .connections: return "network"
    case .ports, .fileports: return "point.3.connected.trianglepath.dotted"
    case .maps, .images: return "square.3.layers.3d"
    default: return "doc.text.magnifyingglass"
    }
  }
}
struct DiagnosticField: Codable, Equatable, Identifiable {
  var name: String
  var value: String
  var id: String { name }
  init(_ name: String, _ value: String) {
    self.name = name
    self.value = value
  }
}
struct DiagnosticRecord: Codable, Equatable, Identifiable {
  var id: String
  var cells: [String: String]
  var numbers: [String: Double] = [:]
  var path: String? = nil
}
/// A point-in-time process memory breakdown. Values are optional because task and
/// region inspection can be denied independently by macOS.
struct ProcessMemorySample: Codable, Equatable, Identifiable {
  var id: Date { date }
  var date: Date
  var footprint: UInt64?
  var resident: UInt64?
  var privateBytes: UInt64?
  var sharedBytes: UInt64?
  var compressed: UInt64?
  var purgeable: UInt64?
}
/// macOS exposes GPU allocation totals per device, while public APIs do not expose
/// an allocation total attributable to an individual process.
struct ProcessGPUMemorySample: Codable, Equatable, Identifiable {
  var id: Date { date }
  var date: Date
  var used: UInt64?
  var allocated: UInt64?
  var deviceCount: Int
}
struct DiagnosticSection: Codable, Equatable {
  var columns: [String] = []
  var records: [DiagnosticRecord] = []
  var status = "Waiting for collection"
  var date: Date? = nil
}
struct DiagnosticSnapshot: Codable {
  var identity: ProcessIdentity
  var date = Date()
  var fields: [DiagnosticField] = []
  var section: DiagnosticSection?
  var memory: ProcessMemorySample? = nil
  var tab: DiagnosticTab
  var valid = true
  var identityStatus: ProcessIdentityStatus = .matching
}
func diagnosticString<T>(_ value: T) -> String {
  var value = value
  return withUnsafeBytes(of: &value) { raw in
    let prefix = raw.prefix { $0 != 0 }
    return String(decoding: prefix, as: UTF8.self)
  }
}
private func permissionStatus(_ error: Int32, count: Int, truncated: Int32, mach: Bool = false)
  -> String
{
  if error != 0 {
    let reason = mach ? String(cString: mach_error_string(error)) : String(cString: strerror(error))
    return "\(count > 0 ? "Partial results. " : "Unavailable. ")macOS: \(reason)"
  }
  return "\(count) entries"
    + (truncated != 0 ? " · Collection limit reached; partial snapshot" : "")
}
private func protection(_ flags: UInt32) -> String {
  "\(flags & 1 != 0 ? "r" : "−")\(flags & 2 != 0 ? "w" : "−")\(flags & 4 != 0 ? "x" : "−")"
}
/// Runs only on a utility worker. No task-control rights, elevation, or environment collection.
enum DiagnosticCollector {
  static func read(identity: ProcessIdentity, tab: DiagnosticTab) -> DiagnosticSnapshot {
    var snapshot = DiagnosticSnapshot(identity: identity, tab: tab)
    snapshot.identityStatus = identity.status()
    guard snapshot.identityStatus == .matching else {
      snapshot.valid = false
      return snapshot
    }
    var info = AMProcessInfo()
    let error = am_process_info(identity.pid, &info)
    if error == 0 {
      func field(_ name: String, _ value: Any) {
        snapshot.fields.append(.init(name, String(describing: value)))
      }
      field("Executable", diagnosticString(info.executable))
      field("Working directory", diagnosticString(info.cwd).nonempty ?? "Unavailable")
      field("Root directory", diagnosticString(info.root).nonempty ?? "Unavailable")
      field("Started", Date(timeIntervalSince1970: Double(info.start) / 1e6).formatted())
      field("Parent PID", info.parent)
      field("Process group", info.group)
      field("Effective UID / GID", "\(info.uid) / \(info.gid)")
      field("Real UID / GID", "\(info.realUID) / \(info.realGID)")
      field("Saved UID / GID", "\(info.savedUID) / \(info.savedGID)")
      field(
        "State",
        [1: "Idle", 2: "Running", 3: "Sleeping", 4: "Stopped", 5: "Zombie"][Int(info.status)]
          ?? "\(info.status)")
      field("Nice", info.nice)
      field("Process flags", String(format: "0x%08X", info.flags))
      field("Open descriptors", info.fileCount)
      if info.taskError == 0 {
        field("User CPU time", duration(Double(info.userNS) / 1e9))
        field("System CPU time", duration(Double(info.systemNS) / 1e9))
        field("Virtual memory", bytes(info.virtualBytes))
        field("Resident memory", bytes(info.residentBytes))
        field("Priority", info.priority)
        field("Running threads", info.runningThreads)
        field("Scheduling policy", info.policy)
        field("Page faults", info.faults)
        field("Page-ins", info.pageins)
        field("Copy-on-write faults", info.cowFaults)
        field("Mach messages sent", info.messagesSent)
        field("Mach messages received", info.messagesReceived)
        field("Mach syscalls", info.machCalls)
        field("Unix syscalls", info.unixCalls)
        field("Context switches", info.switches)
      } else {
        field("Task counters", permissionStatus(info.taskError, count: 0, truncated: 0))
      }
      if info.pathError != 0 { field("Executable", "Unavailable") }
    } else {
      snapshot.fields = [.init("Process metadata", permissionStatus(error, count: 0, truncated: 0))]
    }
    var counters = [AMResourceCounter](repeating: AMResourceCounter(), count: 32)
    var counterCount: Int32 = 0
    if am_process_resources(identity.pid, &counters, 32, &counterCount) == 0 {
      for counter in counters.prefix(Int(counterCount)) {
        let unit = diagnosticString(counter.unit)
        let value =
          unit == "bytes"
          ? bytes(counter.value) : "\(counter.value)" + (unit == "count" ? "" : " \(unit)")
        snapshot.fields.append(.init(diagnosticString(counter.name), value))
      }
    }
    if tab == .memory {
      var details = AMMemoryDetails()
      am_memory_details(identity.pid, &details)
      var memory = ProcessMemorySample(
        date: snapshot.date,
        footprint: nil,
        resident: error == 0 && info.taskError == 0 ? info.residentBytes : nil,
        privateBytes: nil,
        sharedBytes: nil,
        compressed: details.vmAccessible != 0 ? details.compressed : nil,
        purgeable: details.vmAccessible != 0 ? details.purgeable : nil)
      var usageInfo = rusage_info_v4()
      let usageStatus = withUnsafeMutablePointer(to: &usageInfo) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(identity.pid, RUSAGE_INFO_V4, $0)
        }
      }
      if usageStatus == 0 {
        memory.footprint = usageInfo.ri_phys_footprint
      }
      if let usage = ProcessMemoryRegions.read(
        pid: identity.pid, translated: info.flags & 0x0200_0000 != 0)
      {
        memory.privateBytes = usage.privateBytes
        memory.sharedBytes = usage.sharedBytes
      }
      if let value = memory.purgeable { snapshot.fields.append(.init("Purgeable memory", bytes(value))) }
      if let value = memory.compressed { snapshot.fields.append(.init("Compressed memory", bytes(value))) }
      if let value = memory.privateBytes { snapshot.fields.append(.init("Real private memory", bytes(value))) }
      if let value = memory.sharedBytes { snapshot.fields.append(.init("Real shared memory", bytes(value))) }
      snapshot.memory = memory
    }
    if tab == .energy {
      var assertions: Unmanaged<CFDictionary>?
      if IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
        let entries = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
      {
        let active = entries[NSNumber(value: identity.pid)] ?? []
        snapshot.fields.append(.init("Power assertions", String(active.count)))
        for (index, entry) in active.enumerated() {
          let name = entry[kIOPMAssertionNameKey] as? String ?? "Unnamed"
          let type = entry[kIOPMAssertionTypeKey] as? String ?? "Unknown"
          let level = (entry[kIOPMAssertionLevelKey] as? NSNumber)?.stringValue ?? "—"
          snapshot.fields.append(
            .init("Assertion \(index+1)", "\(name) · \(type) · Level \(level)"))
        }
      } else {
        snapshot.fields.append(.init("Power assertions", "Unavailable"))
      }
    }
    switch tab {
    case .threads: snapshot.section = threads(identity.pid)
    case .files, .connections:
      snapshot.section = files(identity.pid, socketsOnly: tab == .connections)
    case .maps: snapshot.section = regions(identity.pid)
    case .images: snapshot.section = images(identity.pid)
    case .ports: snapshot.section = ports(identity.pid)
    case .fileports: snapshot.section = fileports(identity.pid)
    default: break
    }
    snapshot.identityStatus = identity.status()
    snapshot.valid = snapshot.identityStatus == .matching
    return snapshot
  }
  static func threads(_ pid: Int32) -> DiagnosticSection {
    let capacity = 4096
    var buffer = [AMThread](repeating: AMThread(), count: capacity)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_threads(pid, &buffer, Int32(capacity), &count, &truncated)
    let records = buffer.prefix(Int(count)).enumerated().map { index, t in
      let state =
        [1: "Running", 2: "Stopped", 3: "Waiting", 4: "Uninterruptible", 5: "Halted"][Int(t.state)]
        ?? "\(t.state)"
      var record = DiagnosticRecord(
        id: t.uniqueID != 0 ? String(t.id) : "\(t.id)-\(index)",
        cells: [
          "Thread ID": t.uniqueID != 0 ? String(t.id) : "—",
          "Thread handle": t.uniqueID == 0 ? String(format: "0x%llX", t.id) : "—",
          "Name": diagnosticString(t.name),
          "CPU %": t.error == 0 ? String(format: "%.1f", Double(t.cpuScaled) / 10) : "—",
          "User time": t.error == 0 ? duration(Double(t.userNS) / 1e9) : "—",
          "System time": t.error == 0 ? duration(Double(t.systemNS) / 1e9) : "—",
          "State": t.error == 0 ? state : String(cString: strerror(t.error)),
          "Priority": String(t.priority), "Base priority": String(t.basePriority),
          "Max priority": String(t.maxPriority),
          "Policy": String(t.policy), "Sleep seconds": String(t.sleepSeconds),
          "Flags": String(format: "0x%X", t.flags),
        ],
        numbers: [
          "Thread ID": Double(t.id), "CPU %": Double(t.cpuScaled), "User time": Double(t.userNS),
          "System time": Double(t.systemNS),
        ])
      if t.error != 0 {
        for key in record.cells.keys where key != "Thread ID" && key != "State" {
          record.cells[key] = "—"
        }
        record.numbers = ["Thread ID": Double(t.id)]
      }
      return record
    }
    return .init(
      columns: [
        "Thread ID", "Name", "CPU %", "User time", "System time", "State", "Priority",
        "Base priority", "Max priority", "Policy", "Sleep seconds", "Flags", "Thread handle",
      ], records: records, status: permissionStatus(error, count: Int(count), truncated: truncated),
      date: Date())
  }
  static func files(_ pid: Int32, socketsOnly: Bool) -> DiagnosticSection {
    let capacity = 8192
    var buffer = [AMFile](repeating: AMFile(), count: capacity)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_files(pid, &buffer, Int32(capacity), &count, &truncated)
    let records = buffer.prefix(Int(count)).filter { !socketsOnly || $0.type == PROX_FDTYPE_SOCKET }
      .map { f in
        let path = diagnosticString(f.path)
        let types: [Int32: String] = [
          PROX_FDTYPE_VNODE: "File", PROX_FDTYPE_SOCKET: "Socket", PROX_FDTYPE_PIPE: "Pipe",
          PROX_FDTYPE_KQUEUE: "Kqueue", PROX_FDTYPE_PSEM: "Semaphore",
          PROX_FDTYPE_PSHM: "Shared memory",
        ]
        let states = [
          "Closed", "Listen", "SYN sent", "SYN received", "Established", "Close wait", "FIN wait 1",
          "Closing", "Last ACK", "FIN wait 2", "Time wait", "Reserved",
        ]
        var record = DiagnosticRecord(
          id: String(f.fd),
          cells: [
            "FD": String(f.fd), "Type": types[f.type] ?? "Type \(f.type)", "Path": path,
            "Size": f.error == 0 ? bytes(f.size) : "—", "Offset": String(f.offset),
            "Inode": String(f.inode), "Device": String(f.device),
            "Flags": String(format: "0x%X", f.flags), "Mode": String(format: "%o", f.mode),
            "Protocol": f.protocol == IPPROTO_TCP
              ? "TCP"
              : f.protocol == IPPROTO_UDP ? "UDP" : f.family == AF_UNIX ? "Unix" : "\(f.protocol)",
            "Family": f.family == AF_INET
              ? "IPv4"
              : f.family == AF_INET6 ? "IPv6" : f.family == AF_UNIX ? "Unix" : "\(f.family)",
            "Local endpoint": diagnosticString(f.local),
            "Remote endpoint": diagnosticString(f.remote),
            "State": states.indices.contains(Int(f.tcpState)) ? states[Int(f.tcpState)] : "—",
            "Receive queue": bytes(f.receiveQueue), "Send queue": bytes(f.sendQueue),
            "Access": f.error == 0 ? "Available" : String(cString: strerror(f.error)),
          ],
          numbers: [
            "FD": Double(f.fd), "Size": Double(f.size), "Offset": Double(f.offset),
            "Inode": Double(f.inode), "Receive queue": Double(f.receiveQueue),
            "Send queue": Double(f.sendQueue),
          ], path: path.hasPrefix("/") ? path : nil)
        if f.error != 0 {
          for key in record.cells.keys where !["FD", "Type", "Access"].contains(key) {
            record.cells[key] = "—"
          }
          record.numbers = ["FD": Double(f.fd)]
        }
        return record
      }
    return .init(
      columns: socketsOnly
        ? [
          "FD", "Protocol", "Family", "Local endpoint", "Remote endpoint", "State", "Receive queue",
          "Send queue", "Access",
        ] : ["FD", "Type", "Path", "Size", "Offset", "Inode", "Device", "Flags", "Mode", "Access"],
      records: records, status: permissionStatus(error, count: records.count, truncated: truncated),
      date: Date())
  }
  static func regions(_ pid: Int32) -> DiagnosticSection {
    let capacity = 16384
    var buffer = [AMRegion](repeating: AMRegion(), count: capacity)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_regions(pid, &buffer, Int32(capacity), &count, &truncated)
    let records = buffer.prefix(Int(count)).map { r in
      let address = String(format: "0x%016llX", r.address)
      let path = diagnosticString(r.path)
      return DiagnosticRecord(
        id: address,
        cells: [
          "Address": address, "Size": bytes(r.size), "Resident": bytes(r.resident),
          "Private resident": bytes(r.privateResident), "Shared resident": bytes(r.sharedResident),
          "Swapped": bytes(r.swapped), "Dirty": bytes(r.dirty),
          "Protection": protection(r.protection), "Maximum": protection(r.maxProtection),
          "Share mode": String(r.shareMode),
          "Tag": String(r.tag), "References": String(r.references), "Object": String(r.object),
          "Offset": String(r.offset), "Path": path,
        ],
        numbers: [
          "Address": Double(r.address), "Size": Double(r.size), "Resident": Double(r.resident),
          "Private resident": Double(r.privateResident),
          "Shared resident": Double(r.sharedResident), "Swapped": Double(r.swapped),
          "Dirty": Double(r.dirty),
        ], path: path.hasPrefix("/") ? path : nil)
    }
    return .init(
      columns: [
        "Address", "Size", "Resident", "Protection", "Path", "Private resident", "Shared resident",
        "Swapped", "Dirty", "Maximum", "Share mode", "Tag", "References", "Object", "Offset",
      ], records: records, status: permissionStatus(error, count: Int(count), truncated: truncated),
      date: Date())
  }
  static func fileports(_ pid: Int32) -> DiagnosticSection {
    var buffer = [AMFilePort](repeating: AMFilePort(), count: 8192)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_fileports(pid, &buffer, 8192, &count, &truncated)
    let records = buffer.prefix(Int(count)).map { port in
      DiagnosticRecord(
        id: String(port.name),
        cells: [
          "Port name": String(format: "0x%X", port.name), "Descriptor type": String(port.type),
        ], numbers: ["Port name": Double(port.name), "Descriptor type": Double(port.type)])
    }
    return .init(
      columns: ["Port name", "Descriptor type"], records: records,
      status: permissionStatus(error, count: Int(count), truncated: truncated), date: Date())
  }
  static func images(_ pid: Int32) -> DiagnosticSection {
    images(in: regions(pid))
  }
  static func images(in maps: DiagnosticSection) -> DiagnosticSection {
    let images = maps.records.filter { record in
      guard record.path != nil, record.cells["Protection"]?.contains("x") == true else {
        return false
      }
      return true
    }
    return .init(
      columns: ["Path", "Address", "Size", "Resident", "Protection"], records: images,
      status:
        "\(images.count) executable mappings · Shared-cache libraries may not appear individually. \(maps.status)",
      date: maps.date)
  }
  static func ports(_ pid: Int32) -> DiagnosticSection {
    let capacity = 16384
    var buffer = [AMPort](repeating: AMPort(), count: capacity)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_ports(pid, &buffer, Int32(capacity), &count, &truncated)
    let records = buffer.prefix(Int(count)).map { p in
      var rights: [String] = []
      for (flag, name) in [
        ((UInt32(1) << (UInt32(MACH_PORT_RIGHT_SEND) + 16)), "Send"),
        ((UInt32(1) << (UInt32(MACH_PORT_RIGHT_RECEIVE) + 16)), "Receive"),
        ((UInt32(1) << (UInt32(MACH_PORT_RIGHT_SEND_ONCE) + 16)), "Send once"),
        ((UInt32(1) << (UInt32(MACH_PORT_RIGHT_PORT_SET) + 16)), "Port set"),
        ((UInt32(1) << (UInt32(MACH_PORT_RIGHT_DEAD_NAME) + 16)), "Dead name"),
      ] where p.rights & UInt32(flag) != 0 { rights.append(name) }
      return DiagnosticRecord(
        id: String(p.name),
        cells: [
          "Name": String(format: "0x%X", p.name), "Rights": rights.joined(separator: ", "),
          "Mask": String(format: "0x%X", p.rights),
        ], numbers: ["Name": Double(p.name)])
    }
    return .init(
      columns: ["Name", "Rights", "Mask"], records: records,
      status: permissionStatus(error, count: Int(count), truncated: truncated, mach: true),
      date: Date())
  }
}
extension String { var nonempty: String? { isEmpty ? nil : self } }
