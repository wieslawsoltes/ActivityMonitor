import Foundation

enum ProcessSortValue {
  case integer(UInt64)
  case number(Double)
  case text(String)
  func compare(_ other: ProcessSortValue) -> ComparisonResult {
    switch (self, other) {
    case (.integer(let a), .integer(let b)):
      return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    case (.number(let a), .number(let b)):
      return a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    case (.text(let a), .text(let b)): return a.localizedStandardCompare(b)
    default: return .orderedSame
    }
  }
}

enum ProcessValues {
  static func value(_ p: ProcessRow, key: String, metric: Metric) -> ProcessSortValue? {
    let key = ProcessColumns.canonical(key, metric: metric)
    switch key {
    case "name": return .text(p.name)
    case "kind": return .text(p.kind)
    case "user": return .text(p.user)
    case "pid": return .integer(UInt64(max(0, p.id)))
    case "cpu": return p.accessible ? .number(p.cpu) : nil
    case "time": return p.accessible ? .number(p.cpuTime) : nil
    case "threads": return p.accessible ? .integer(UInt64(p.threads)) : nil
    case "memory": return p.accessible ? .integer(p.memory) : nil
    case "resident": return p.accessible ? .integer(p.resident) : nil
    case "read": return p.ioAccessible ? .integer(p.read) : nil
    case "written": return p.ioAccessible ? .integer(p.written) : nil
    case "gpu": return p.gpuPercent.map(ProcessSortValue.number)
    case "gpuTime": return p.gpuTime.map(ProcessSortValue.number)
    case "received": return p.networkReceived.map(ProcessSortValue.integer)
    case "sent": return p.networkSent.map(ProcessSortValue.integer)
    case "packetsIn": return p.details.packetsIn.map(ProcessSortValue.integer)
    case "packetsOut": return p.details.packetsOut.map(ProcessSortValue.integer)
    case "ports": return p.details.ports.map(ProcessSortValue.integer)
    case "privateMemory": return p.details.privateMemory.map(ProcessSortValue.integer)
    case "sharedMemory": return p.details.sharedMemory.map(ProcessSortValue.integer)
    case "purgeable": return p.details.purgeable.map(ProcessSortValue.integer)
    case "compressed": return p.details.compressed.map(ProcessSortValue.integer)
    case "wakeups": return p.details.wakeups.map(ProcessSortValue.number)
    case "sandbox": return p.details.sandbox.map { .integer($0 ? 1 : 0) }
    case "restricted": return p.details.restricted.map { .integer($0 ? 1 : 0) }
    case "sleep": return p.details.preventingSleep.map { .integer($0 ? 1 : 0) }
    default: return nil
    }
  }
  static func text(_ p: ProcessRow, key: String, metric: Metric) -> String {
    let key = ProcessColumns.canonical(key, metric: metric)
    guard let value = value(p, key: key, metric: metric) else { return "—" }
    switch value {
    case .text(let text): return text
    case .integer(let count):
      if [
        "memory", "resident", "privateMemory", "sharedMemory", "purgeable", "compressed",
        "received", "sent", "read", "written",
      ].contains(key) {
        return bytes(count)
      }
      if ["sandbox", "restricted", "sleep"].contains(key) { return count == 0 ? "No" : "Yes" }
      return String(count)
    case .number(let number):
      if key == "gpuTime" { return gpuDuration(number) }
      if key == "time" { return duration(number) }
      return String(format: "%.1f", number)
    }
  }
}
