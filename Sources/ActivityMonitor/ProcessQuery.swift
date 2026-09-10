import Darwin
import Foundation

struct ProcessQuery: Equatable {
  var metric: Metric
  var query: String
  var filter: String
  var sort: String
  var descending: Bool
  var selected: Set<Int32> = []
  static let filters = [
    "All processes", "All processes, hierarchically", "My processes", "System processes",
    "Other users’ processes", "Active processes", "Inactive processes", "GPU processes",
    "Windowed processes", "Selected processes", "Applications",
  ]
  func matchesFilter(_ p: ProcessRow) -> Bool {
    switch filter {
    case "All processes", "All processes, hierarchically": return true
    case "My processes": return p.uid == getuid()
    case "System processes": return p.uid == 0
    case "Other users’ processes": return p.uid != getuid()
    case "Active processes": return p.accessible && p.cpu > 0
    case "Inactive processes": return p.accessible && p.cpu == 0
    case "GPU processes": return (p.gpuPercent ?? 0) > 0
    case "Windowed processes", "Applications": return p.isApp
    case "Selected processes": return selected.contains(p.id)
    default: return true
    }
  }
  func apply(_ rows: [ProcessRow]) -> [ProcessRow] {
    rows.filter { p in
      (query.isEmpty || p.name.localizedCaseInsensitiveContains(query)
        || (p.executableName?.localizedCaseInsensitiveContains(query) ?? false)
        || p.user.localizedCaseInsensitiveContains(query) || String(p.id).contains(query))
        && matchesFilter(p)
    }.sorted { a, b in
      guard a.id != b.id else { return false }
      let av = ProcessValues.value(a, key: sort, metric: metric)
      let bv = ProcessValues.value(b, key: sort, metric: metric)
      switch (av, bv) {
      case (let av?, let bv?):
        let comparison = av.compare(bv)
        if comparison == .orderedSame { return a.id < b.id }
        return descending ? comparison == .orderedDescending : comparison == .orderedAscending
      case (_?, nil): return true
      case (nil, _?): return false
      case (nil, nil): return a.id < b.id
      }
    }
  }
}
