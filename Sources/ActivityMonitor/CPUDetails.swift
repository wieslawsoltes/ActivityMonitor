import Foundation
import IOKit
import SystemBridge

struct CPUPerformanceLevel: Codable, Equatable {
  let name: String
  let physical: Int
  let logical: Int
}
struct CPUTopology: Codable, Equatable {
  var physical: Int?
  var logical: Int?
  var levels: [CPUPerformanceLevel] = []
  var coreTypes: [Int: String] = [:]
  static let current = read()
  var summary: String {
    let counts =
      "\(physical.map(String.init) ?? "—") physical · \(logical.map(String.init) ?? "—") logical"
    return levels.isEmpty
      ? counts
      : counts + " · "
        + levels.map { "\($0.physical) \($0.name.lowercased())" }.joined(separator: " · ")
  }
  static func read() -> Self {
    func integer(_ key: String) -> Int? {
      var value: Int32 = 0
      var size = MemoryLayout<Int32>.size
      guard sysctlbyname(key, &value, &size, nil, 0) == 0, value > 0 else { return nil }
      return Int(value)
    }
    func string(_ key: String) -> String? {
      var buffer = [CChar](repeating: 0, count: 128)
      var size = buffer.count
      guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
      return String(cString: buffer)
    }
    var result = Self(physical: integer("hw.physicalcpu"), logical: integer("hw.logicalcpu"))
    for index in 0..<min(16, integer("hw.nperflevels") ?? 0) {
      let prefix = "hw.perflevel\(index)"
      if let name = string(prefix + ".name"), let physical = integer(prefix + ".physicalcpu"),
        let logical = integer(prefix + ".logicalcpu")
      {
        result.levels.append(.init(name: name, physical: physical, logical: logical))
      }
    }
    // Use explicit logical IDs, never infer E/P ordering from array position or counts.
    let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
    if root != 0 {
      defer { IOObjectRelease(root) }
      var iterator: io_iterator_t = 0
      if IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == KERN_SUCCESS {
        defer { IOObjectRelease(iterator) }
        var seen = Set<Int>()
        var duplicate = Set<Int>()
        while case let entry = IOIteratorNext(iterator), entry != 0 {
          defer { IOObjectRelease(entry) }
          guard
            let id = IORegistryEntryCreateCFProperty(
              entry, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
              as? NSNumber,
            let data = IORegistryEntryCreateCFProperty(
              entry, "cluster-type" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
              as? Data
          else { continue }
          let slot = id.intValue
          guard slot >= 0, slot < 4096 else { continue }
          if !seen.insert(slot).inserted { duplicate.insert(slot) }
          let type = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
          if type == "P" { result.coreTypes[slot] = "Performance" }
          if type == "E" { result.coreTypes[slot] = "Efficiency" }
        }
        for id in duplicate { result.coreTypes[id] = nil }
      }
    }
    return result
  }
}
struct CPUUsagePoint: Codable, Equatable {
  let date: Date
  var user: Double?
  var system: Double?
  var total: Double? { user.flatMap { u in system.map { u + $0 } } }
}
struct CPUUsageSeries: Identifiable, Codable, Equatable {
  let id: String
  var title: String
  var detail: String
  var points: [CPUUsagePoint] = []
  var latest: Double? { points.last?.total }
}
struct CPUReading {
  let id: String
  let title: String
  var detail = ""
  var user: Double?
  var system: Double?
}
/// Caps both the time window and total retained points, even for thousands of threads.
struct CPUHistoryStore {
  static let pointBudget = 131_072
  var series: [CPUUsageSeries] = []
  mutating func append(_ readings: [CPUReading], at date: Date) {
    let old = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
    let cap = min(901, max(1, Self.pointBudget / max(1, readings.count)))
    var seen = Set<String>()
    series = readings.prefix(4096).filter { seen.insert($0.id).inserted }.map { reading in
      var value =
        old[reading.id]
        ?? CPUUsageSeries(id: reading.id, title: reading.title, detail: reading.detail)
      value.title = reading.title
      value.detail = reading.detail
      if let last = value.points.last, date <= last.date { value.points = [] }
      value.points.append(.init(date: date, user: reading.user, system: reading.system))
      value.points.removeAll { $0.date < date.addingTimeInterval(-900) }
      if value.points.count > cap { value.points.removeFirst(value.points.count - cap) }
      return value
    }
  }
  mutating func unavailable(at date: Date) {
    append(series.map { .init(id: $0.id, title: $0.title, detail: $0.detail) }, at: date)
  }
}
struct CPUCoreSample {
  var readings: [CPUReading] = []
  var status: String? = nil
}
struct CPUCoreTracker {
  private var previous: [Int32: AMCPUTicks] = [:]
  mutating func sample(_ ticks: [AMCPUTicks], topology: CPUTopology) -> [CPUReading] {
    var next: [Int32: AMCPUTicks] = [:]
    let result = ticks.compactMap { tick -> CPUReading? in
      guard next[tick.slot] == nil else { return nil }
      next[tick.slot] = tick
      var reading = CPUReading(
        id: "cpu-\(tick.slot)", title: "CPU \(tick.slot)",
        detail: tick.identified != 0
          ? topology.coreTypes[Int(tick.slot)] ?? "Logical processor" : "Logical processor")
      if let old = previous[tick.slot], old.identified == tick.identified {
        let user = Double(tick.user &- old.user) + Double(tick.nice &- old.nice)
        let system = Double(tick.system &- old.system)
        let total = user + system + Double(tick.idle &- old.idle)
        if total > 0 {
          reading.user = user / total * 100
          reading.system = system / total * 100
        }
      }
      return reading
    }
    previous = next
    return result
  }
  mutating func read() -> CPUCoreSample {
    var ticks = [AMCPUTicks](repeating: AMCPUTicks(), count: 4096)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_cpu_ticks(&ticks, Int32(ticks.count), &count, &truncated)
    guard error == 0 else {
      previous = [:]
      return .init(
        status: "Processor usage unavailable: \(String(cString: mach_error_string(error)))")
    }
    return .init(
      readings: sample(Array(ticks.prefix(Int(count))), topology: .current),
      status: truncated != 0 ? "Processor collection limit reached" : nil)
  }
}

struct ThreadCPUCounter: Equatable {
  let id: UInt64
  let name: String
  var user: UInt64?
  var system: UInt64?
}
struct ThreadCPUSnapshot {
  var counters: [ThreadCPUCounter] = []
  var date = Date()
  var uptime = ProcessInfo.processInfo.systemUptime
  var status: String? = nil
  var available = true
}
enum ThreadCPUReader {
  static func read(_ identity: ProcessIdentity) -> ThreadCPUSnapshot {
    guard identity.matches() else {
      return .init(status: "Process access unavailable", available: false)
    }
    var threads = [AMThread](repeating: AMThread(), count: 4096)
    var count: Int32 = 0
    var truncated: Int32 = 0
    let error = am_process_threads(identity.pid, &threads, Int32(threads.count), &count, &truncated)
    guard error == 0, identity.matches() else {
      return .init(status: "Thread activity unavailable for this process", available: false)
    }
    let counters = threads.prefix(Int(count)).filter { $0.uniqueID != 0 }.map {
      ThreadCPUCounter(
        id: $0.id, name: diagnosticString($0.name),
        user: $0.error == 0 ? $0.userNS : nil, system: $0.error == 0 ? $0.systemNS : nil)
    }
    return .init(
      counters: counters,
      status: counters.isEmpty
        ? "Unique thread IDs unavailable"
        : truncated != 0 ? "Thread collection limit reached (4096)" : nil,
      available: !counters.isEmpty)
  }
}
struct ThreadCPUTracker {
  private var previous: [UInt64: ThreadCPUCounter] = [:]
  private var uptime: TimeInterval?
  mutating func reset() {
    previous = [:]
    uptime = nil
  }
  mutating func sample(_ snapshot: ThreadCPUSnapshot) -> [CPUReading] {
    let elapsed = uptime.map { snapshot.uptime - $0 } ?? 0
    var next: [UInt64: ThreadCPUCounter] = [:]
    let result = snapshot.counters.compactMap { counter -> CPUReading? in
      guard next[counter.id] == nil else { return nil }
      next[counter.id] = counter
      var reading = CPUReading(
        id: String(counter.id), title: "Thread \(counter.id)", detail: counter.name)
      if let old = previous[counter.id], elapsed > 0, elapsed <= 30,
        let user = counter.user, let system = counter.system, let oldUser = old.user,
        let oldSystem = old.system,
        user >= oldUser, system >= oldSystem
      {
        reading.user = Double(user - oldUser) / 1e9 / elapsed * 100
        reading.system = Double(system - oldSystem) / 1e9 / elapsed * 100
      }
      return reading
    }
    previous = next
    uptime = snapshot.uptime
    return result
  }
}
