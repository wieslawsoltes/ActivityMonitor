import Foundation
import IOKit
import Metal

struct GPUDeviceSample: Identifiable, Codable, Equatable {
  var id: UInt64
  var name: String
  var unifiedMemory: Bool?
  var connected = true
  var utilization: Double?
  var renderer: Double?
  var tiler: Double?
  var memoryUsed: UInt64?
  var memoryAllocated: UInt64?
}
struct GPUClientKey: Hashable {
  var device: UInt64
  var client: UInt64
}
struct GPUClientSample {
  var key: GPUClientKey
  var pid: Int32
  var nanoseconds: UInt64
  var counterCount: Int
  var counters: [UInt64] = []
}
struct GPUHardwareSnapshot {
  var devices: [GPUDeviceSample]
  var clients: [GPUClientSample]
  var uptime: TimeInterval
}
struct GPUProcessSample: Equatable {
  var percent: Double?
  var seconds: Double?
  var waiting = false
}
struct GPUHistoryPoint: Identifiable, Codable {
  var id = UUID()
  var date: Date
  var utilization: Double?
}

/// Driver properties are optional. Absence is distinct from a measured zero.
enum GPURegistryParser {
  static func metalID(accelerator: UInt64, ancestors: [UInt64], metalIDs: Set<UInt64>) -> UInt64? {
    ([accelerator] + ancestors).first { metalIDs.contains($0) }
  }
  static func number(_ value: Any?) -> NSNumber? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
      n.doubleValue.isFinite
    else { return nil }
    return n
  }
  static func unsigned(_ value: Any?) -> UInt64? {
    guard let n = number(value) else { return nil }
    // String conversion preserves all 64 bits and rejects negatives and fractions.
    return UInt64(n.stringValue)
  }
  static func percent(_ value: Any?) -> Double? {
    guard let n = number(value)?.doubleValue, (0...100).contains(n) else { return nil }
    return n
  }
  static func device(id: UInt64, name: String, unified: Bool?, properties: [String: Any])
    -> GPUDeviceSample
  {
    let stats = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
    return GPUDeviceSample(
      id: id, name: name, unifiedMemory: unified,
      utilization: percent(stats["Device Utilization %"]) ?? percent(stats["GPU Activity(%)"]),
      renderer: percent(stats["Renderer Utilization %"]),
      tiler: percent(stats["Tiler Utilization %"]),
      memoryUsed: unsigned(stats["In use system memory"]),
      memoryAllocated: unsigned(stats["Alloc system memory"]))
  }
  static func client(device: UInt64, id: UInt64, properties: [String: Any]) -> GPUClientSample? {
    guard let creator = properties["IOUserClientCreator"] as? String, creator.hasPrefix("pid "),
      let pidText = creator.dropFirst(4).split(separator: ",", maxSplits: 1).first,
      let pid = Int32(pidText), pid > 0,
      let usage = properties["AppUsage"] as? [[String: Any]], !usage.isEmpty
    else { return nil }
    var total: UInt64 = 0
    var counters: [UInt64] = []
    for entry in usage {
      guard let value = unsigned(entry["accumulatedGPUTime"]) else { return nil }
      let sum = total.addingReportingOverflow(value)
      guard !sum.overflow else { return nil }
      total = sum.partialValue
      counters.append(value)
    }
    return GPUClientSample(
      key: GPUClientKey(device: device, client: id), pid: pid,
      nanoseconds: total, counterCount: usage.count, counters: counters)
  }
}

/// Public IOKit access only; no subprocess or privileged helper in the sampling path.
final class GPUHardwareReader {
  func read() -> GPUHardwareSnapshot {
    let metal = MTLCopyAllDevices()
    var devices: [GPUDeviceSample] = []
    var clients: [GPUClientSample] = []
    var iterator: io_iterator_t = 0
    if IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    {
      defer { IOObjectRelease(iterator) }
      while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer { IOObjectRelease(entry) }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS else { continue }
        let properties = Self.properties(entry)
        let ancestorIDs = Self.ancestors(entry)
        let matchedID = GPURegistryParser.metalID(
          accelerator: id, ancestors: ancestorIDs, metalIDs: Set(metal.map(\.registryID)))
        let device = metal.first { $0.registryID == matchedID }
        if let matchedID { id = matchedID }
        let name = device?.name ?? properties["IOClass"] as? String ?? "GPU \(id)"
        devices.append(
          GPURegistryParser.device(
            id: id, name: name, unified: device?.hasUnifiedMemory, properties: properties))
        var children: io_iterator_t = 0
        if IORegistryEntryCreateIterator(
          entry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children)
          == KERN_SUCCESS
        {
          defer { IOObjectRelease(children) }
          while case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            var clientID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(child, &clientID) == KERN_SUCCESS else {
              continue
            }
            if let client = GPURegistryParser.client(
              device: id, id: clientID, properties: Self.properties(child))
            {
              clients.append(client)
            }
          }
        }
      }
    }
    // Metal can enumerate hardware whose driver publishes no performance counters.
    for device in metal where !devices.contains(where: { $0.id == device.registryID }) {
      devices.append(
        GPUDeviceSample(
          id: device.registryID, name: device.name, unifiedMemory: device.hasUnifiedMemory))
    }
    return GPUHardwareSnapshot(
      devices: devices.sorted { $0.id < $1.id }, clients: clients,
      uptime: ProcessInfo.processInfo.systemUptime)
  }
  private static func ancestors(_ entry: io_registry_entry_t) -> [UInt64] {
    var result: [UInt64] = []
    var current = entry
    IOObjectRetain(current)
    defer { IOObjectRelease(current) }
    for _ in 0..<16 {
      var parent: io_registry_entry_t = 0
      guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
        break
      }
      IOObjectRelease(current)
      current = parent
      var id: UInt64 = 0
      if IORegistryEntryGetRegistryEntryID(current, &id) == KERN_SUCCESS { result.append(id) }
    }
    return result
  }
  private static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS
    else { return [:] }
    return properties?.takeRetainedValue() as? [String: Any] ?? [:]
  }
}

/// Rates use monotonic time. Never attribute a client's pre-observation work to this session.
struct GPUProcessTracker {
  private struct Baseline {
    var sample: GPUClientSample
    var start: UInt64
  }
  private var previous: [GPUClientKey: Baseline] = [:]
  private var previousTime: TimeInterval?
  private var observed: [Int32: (start: UInt64, seconds: Double)] = [:]
  mutating func update(_ snapshot: GPUHardwareSnapshot, identities: [Int32: UInt64]) -> [Int32:
    GPUProcessSample]
  {
    let elapsed = previousTime.map { snapshot.uptime - $0 }
    var next: [GPUClientKey: Baseline] = [:]
    var deltas: [Int32: Double] = [:]
    var present: Set<Int32> = []
    observed = observed.filter { identities[$0.key] == $0.value.start }
    for client in snapshot.clients {
      guard let start = identities[client.pid], next[client.key] == nil else { continue }
      present.insert(client.pid)
      next[client.key] = Baseline(sample: client, start: start)
      if let elapsed, elapsed.isFinite, elapsed > 0,
        let old = previous[client.key], old.start == start, old.sample.pid == client.pid,
        old.sample.counterCount == client.counterCount,
        client.nanoseconds >= old.sample.nanoseconds,
        old.sample.counters.count == client.counters.count,
        zip(old.sample.counters, client.counters).allSatisfy({ $1 >= $0 })
      {
        deltas[client.pid, default: 0] += Double(client.nanoseconds - old.sample.nanoseconds) / 1e9
      }
    }
    var result: [Int32: GPUProcessSample] = [:]
    for (pid, value) in observed { result[pid] = GPUProcessSample(seconds: value.seconds) }
    for pid in present {
      if let delta = deltas[pid], let elapsed {
        let seconds = (observed[pid]?.seconds ?? 0) + delta
        observed[pid] = (identities[pid]!, seconds)
        result[pid] = GPUProcessSample(percent: delta / elapsed * 100, seconds: seconds)
      } else {
        result[pid] = GPUProcessSample(seconds: observed[pid]?.seconds, waiting: true)
      }
    }
    previous = next
    previousTime = snapshot.uptime
    return result
  }
}

func gpuPercent(_ value: Double?) -> String {
  value.map { String(format: "%.1f", $0) } ?? "—"
}
func gpuDuration(_ value: Double?) -> String {
  guard let value, value.isFinite, value >= 0, value < Double(Int.max) else { return "—" }
  let rounded = (value * 100).rounded() / 100
  guard rounded < Double(Int.max) else { return "—" }
  let minutes = Int(rounded) / 60
  return String(
    format: "%d:%02d:%05.2f", minutes / 60, minutes % 60,
    rounded.truncatingRemainder(dividingBy: 60))
}
