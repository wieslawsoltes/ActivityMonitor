import Darwin
import Foundation

struct ProcessQuery: Equatable {
  var metric: Metric
  var query: String
  var filter: String
  var sort: String
  var descending: Bool
  func apply(_ rows: [ProcessRow]) -> [ProcessRow] {
    rows.filter { p in
      (query.isEmpty || p.name.localizedCaseInsensitiveContains(query)
        || p.user.localizedCaseInsensitiveContains(query) || String(p.id).contains(query))
        && (filter == "All processes" || filter == "My processes" && p.uid == getuid()
          || filter == "System processes" && p.uid == 0 || filter == "Applications" && p.isApp)
    }.sorted { a, b in
      if a.id == b.id { return false }
      let result: Bool
      switch sort {
      case "name":
        let comparison = a.name.localizedStandardCompare(b.name)
        result = comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
      case "received":
        result =
          (a.networkReceived ?? 0) == (b.networkReceived ?? 0)
          ? a.id < b.id : (a.networkReceived ?? 0) < (b.networkReceived ?? 0)
      case "sent":
        result =
          (a.networkSent ?? 0) == (b.networkSent ?? 0)
          ? a.id < b.id : (a.networkSent ?? 0) < (b.networkSent ?? 0)
      case "kind": result = a.kind == b.kind ? a.id < b.id : a.kind < b.kind
      case "pid": result = a.id < b.id
      case "user": result = a.user == b.user ? a.id < b.id : a.user < b.user
      case "threads": result = a.threads == b.threads ? a.id < b.id : a.threads < b.threads
      case "cpu": result = a.cpu == b.cpu ? a.id < b.id : a.cpu < b.cpu
      case "resident": result = a.resident == b.resident ? a.id < b.id : a.resident < b.resident
      case "memory": result = a.memory == b.memory ? a.id < b.id : a.memory < b.memory
      case "time": result = a.cpuTime == b.cpuTime ? a.id < b.id : a.cpuTime < b.cpuTime
      case "secondary": result = a.read == b.read ? a.id < b.id : a.read < b.read
      default:
        let av = value(a)
        let bv = value(b)
        result = av == bv ? a.id < b.id : av < bv
      }
      return descending ? !result : result
    }
  }
  func value(_ p: ProcessRow) -> Double {
    switch metric {
    case .memory: return Double(p.memory)
    case .disk: return Double(p.written)
    default: return p.cpu
    }
  }
}
