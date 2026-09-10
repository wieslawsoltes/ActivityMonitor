import AppKit
import Darwin
import IOKit.pwr_mgt
import SystemBridge

enum ProcessDisplayName {
  static func resolve(executable: String, application: String?) -> String {
    guard let application, !application.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return executable
    }
    return application
  }
}

struct ProcessDetails: Codable, Equatable {
  var ports: UInt64?
  var privateMemory: UInt64?
  var sharedMemory: UInt64?
  var purgeable: UInt64?
  var compressed: UInt64?
  var wakeups: Double?
  var packetsIn: UInt64?
  var packetsOut: UInt64?
  var sandbox: Bool?
  var restricted: Bool?
  var preventingSleep: Bool?

  static func wakeupRate(current: AMProcess, previous: AMProcess?, elapsed: Double) -> Double? {
    guard let previous, current.start == previous.start, current.ioAccessible != 0,
      previous.ioAccessible != 0, current.wakeups >= previous.wakeups,
      elapsed.isFinite, elapsed > 0
    else { return nil }
    return Double(current.wakeups - previous.wakeups) / elapsed
  }
}

/// Slow-changing details are sampled off the main thread and keyed by PID AND start time.
final class ProcessDetailsCollector: @unchecked Sendable {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "ActivityMonitor.process-details", qos: .utility)
  private var cache: [Int32: (UInt64, ProcessDetails)] = [:]
  private var sampled = Date.distantPast
  private var sampledRegions = false
  private var sampling = false
  func collect(_ processes: [AMProcess], now: Date) -> [Int32: ProcessDetails] {
    let preferences = ProcessColumnPreferences(
      UserDefaults.standard.string(forKey: "processColumnVisibility.v1") ?? "{}")
    let regions = preferences.overrides.values.contains {
      $0["privateMemory"] == true || $0["sharedMemory"] == true
    }
    let shouldSample = lock.withLock {
      guard !sampling, now.timeIntervalSince(sampled) >= 5 || regions != sampledRegions else {
        return false
      }
      sampling = true
      return true
    }
    if shouldSample {
      queue.async { [self] in
        let next = sample(processes, regions: regions)
        lock.withLock {
          cache = next
          sampled = Date()
          sampledRegions = regions
          sampling = false
        }
      }
    }
    let snapshot = lock.withLock { cache }
    return Dictionary(
      uniqueKeysWithValues: processes.compactMap { p in
        guard let cached = snapshot[p.pid], cached.0 == p.start else { return nil }
        return (p.pid, cached.1)
      })
  }
  private func sample(_ processes: [AMProcess], regions: Bool) -> [Int32: (UInt64, ProcessDetails)]
  {
    let ports = readProcessPorts()
    let sleep = readSleepAssertions()
    var next: [Int32: (UInt64, ProcessDetails)] = [:]
    for process in processes {
      var result = ProcessDetails()
      result.ports = ports[process.pid]
      result.preventingSleep = sleep.map { $0.contains(process.pid) }
      var memory = AMMemoryDetails()
      am_memory_details(process.pid, &memory)
      if memory.vmAccessible != 0 {
        result.purgeable = memory.purgeable
        result.compressed = memory.compressed
      }
      if regions,
        let usage = ProcessMemoryRegions.read(pid: process.pid, translated: process.translated != 0)
      {
        result.privateMemory = usage.privateBytes
        result.sharedMemory = usage.sharedBytes
      }
      result.sandbox = ProcessSecurity.sandboxed(process.pid)
      result.restricted = ProcessSecurity.restricted(process.pid)
      var identity = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.size)
      if proc_pidinfo(process.pid, PROC_PIDTBSDINFO, 0, &identity, size) == size,
        identity.pbi_start_tvsec * 1_000_000 + identity.pbi_start_tvusec == process.start
      {
        next[process.pid] = (process.start, result)
      }
    }
    return next
  }
}

func readProcessPorts() -> [Int32: UInt64] {
  // top has Apple's task-inspection entitlement; task-name rights cannot enumerate Mach ports.
  guard let output = readProcessTool("/usr/bin/top", ["-l", "1", "-stats", "pid,ports"]) else {
    return [:]
  }
  return parseProcessPorts(output)
}
func parseProcessPorts(_ text: String) -> [Int32: UInt64] {
  var result: [Int32: UInt64] = [:]
  for line in text.split(separator: "\n") {
    let fields = line.split(whereSeparator: \.isWhitespace)
    guard fields.count == 2, let pid = Int32(fields[0]), let ports = UInt64(fields[1]) else {
      continue
    }
    result[pid] = ports
  }
  return result
}
func readProcessTool(_ executable: String, _ arguments: [String]) -> String? {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do {
    try process.run()
    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3, execute: timeout)
    defer { timeout.cancel() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
  } catch { return nil }
}
func readSleepAssertions() -> Set<Int32>? {
  var assertions: Unmanaged<CFDictionary>?
  guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
    let values = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
  else { return nil }
  var result: Set<Int32> = []
  for (pid, entries) in values where entries.contains(where: assertionPreventsSleep) {
    result.insert(pid.int32Value)
  }
  return result
}
func assertionPreventsSleep(_ entry: [String: Any]) -> Bool {
  guard let level = entry[kIOPMAssertionLevelKey] as? NSNumber, level.intValue != 0,
    let type = entry[kIOPMAssertionTypeKey] as? String
  else { return false }
  return [
    "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
    "NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep",
  ].contains(type)
}

/// Read-only system queries. These symbols are optional; unavailable/denied is never reported as No.
enum ProcessSecurity {
  typealias SandboxCheck = @convention(c) (Int32, UnsafePointer<CChar>?, Int32) -> Int32
  typealias CodeStatus = @convention(c) (Int32, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
  private static let library = dlopen("/usr/lib/libsandbox.dylib", RTLD_LAZY | RTLD_LOCAL)
  private static let check: SandboxCheck? = library.flatMap { dlsym($0, "sandbox_check") }.map {
    unsafeBitCast($0, to: SandboxCheck.self)
  }
  private static let status: CodeStatus? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops")
    .map { unsafeBitCast($0, to: CodeStatus.self) }
  static func sandboxed(_ pid: Int32) -> Bool? {
    guard let check else { return nil }
    let value = check(pid, nil, 0)
    return value < 0 ? nil : value != 0
  }
  static func restricted(_ pid: Int32) -> Bool? {
    var flags: UInt32 = 0
    guard let status, status(pid, 0, &flags, MemoryLayout<UInt32>.size) == 0 else { return nil }
    return flags & 0x800 != 0  // CS_RESTRICT in Apple's xnu/bsd/sys/codesign.h
  }
}

/// Region accounting uses resident pages, with shared objects counted once per process.
enum ProcessMemoryRegions {
  struct Region {
    var object: UInt32
    var mode: UInt32
    var references: UInt32
    var privatePages: UInt64
    var sharedPages: UInt64
  }
  static func totals(_ regions: [Region], pageSize: UInt64) -> (
    privateBytes: UInt64, sharedBytes: UInt64
  ) {
    var privatePages: UInt64 = 0
    var objects: [UInt32: (pages: UInt64, references: UInt32, mappings: UInt32, mode: UInt32)] = [:]
    for r in regions {
      if r.mode == SM_PRIVATE || r.mode == SM_LARGE_PAGE || (r.mode == SM_COW && r.references == 1)
      {
        privatePages += r.privatePages + r.sharedPages
      } else if r.mode == SM_SHARED || r.mode == SM_COW || r.mode == SM_SHARED_ALIASED {
        if r.mode == SM_COW { privatePages += r.privatePages }
        let prior = objects[r.object]
        objects[r.object] = (
          max(prior?.pages ?? 0, r.sharedPages), r.references, (prior?.mappings ?? 0) + 1, r.mode
        )
      } else if r.mode == SM_PRIVATE_ALIASED {
        privatePages += r.privatePages + r.sharedPages
      }
    }
    var sharedPages: UInt64 = 0
    for object in objects.values {
      if object.mode == SM_SHARED && object.references == object.mappings {
        privatePages += object.pages
      } else {
        sharedPages += object.pages
      }
    }
    return (privatePages * pageSize, sharedPages * pageSize)
  }
  static func read(pid: Int32, translated: Bool) -> (privateBytes: UInt64, sharedBytes: UInt64)? {
    var regions: [Region] = []
    var address: UInt64 = 0
    let size = Int32(MemoryLayout<proc_regioninfo>.size)
    // Bound traversal so a changing or pathological map cannot stall all sampling.
    for _ in 0..<20_000 {
      var r = proc_regioninfo()
      errno = 0
      guard proc_pidinfo(pid, PROC_PIDREGIONINFO, address, &r, size) == size else {
        guard !regions.isEmpty, errno == EINVAL else { return nil }
        return totals(regions, pageSize: UInt64(vm_kernel_page_size))
      }
      guard r.pri_size > 0, r.pri_address >= address,
        r.pri_address <= UInt64.max - r.pri_size
      else { return nil }
      address = r.pri_address + r.pri_size
      #if arch(arm64)
        let sharedBase: UInt64 = translated ? 0x7FF8_0000_0000 : 0x1_8000_0000
        let sharedSize: UInt64 = translated ? 0x7_FE00_0000 : 0x1_8000_0000
      #else
        let sharedBase: UInt64 = 0x7FF8_0000_0000
        let sharedSize: UInt64 = 0x7_FE00_0000
      #endif
      // Match top's exclusion of the globally mapped dyld shared cache.
      if r.pri_address >= sharedBase && r.pri_address < sharedBase + sharedSize
        && r.pri_share_mode != SM_PRIVATE
      {
        continue
      }
      regions.append(
        Region(
          object: r.pri_obj_id, mode: r.pri_share_mode,
          references: r.pri_ref_count, privatePages: UInt64(r.pri_private_pages_resident),
          sharedPages: UInt64(r.pri_shared_pages_resident)))
    }
    return nil
  }
}
