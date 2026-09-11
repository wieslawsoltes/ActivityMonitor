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
    "All processes", "My processes", "System processes",
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
  func apply(_ rows: [ProcessRow], limit: Int? = nil) -> [ProcessRow] {
    struct Candidate {
      let index: Int
      let pid: Int32
      let value: ProcessSortValue?
    }
    func before(_ a: Candidate, _ b: Candidate) -> Bool {
      guard a.pid != b.pid else { return false }
      switch (a.value, b.value) {
      case (let av?, let bv?):
        let comparison = av.compare(bv)
        if comparison == .orderedSame { return a.pid < b.pid }
        return descending ? comparison == .orderedDescending : comparison == .orderedAscending
      case (_?, nil): return true
      case (nil, _?): return false
      case (nil, nil): return a.pid < b.pid
      }
    }
    let key = ProcessColumns.canonical(sort, metric: metric)
    var candidates: [Candidate] = []
    candidates.reserveCapacity(limit.map { min(rows.count, max(0, $0)) } ?? rows.count)
    for (index, p) in rows.enumerated() {
      guard matchesFilter(p),
        query.isEmpty || p.name.localizedCaseInsensitiveContains(query)
          || (p.executableName?.localizedCaseInsensitiveContains(query) ?? false)
          || p.user.localizedCaseInsensitiveContains(query) || String(p.id).contains(query)
      else { continue }
      let candidate = Candidate(
        index: index, pid: p.id,
        value: ProcessValues.value(p, key: key, metric: metric))
      if let limit {
        guard limit > 0 else { return [] }
        if candidates.count == limit, let last = candidates.last, !before(candidate, last) {
          continue
        }
        let insertion = candidates.firstIndex { before(candidate, $0) } ?? candidates.count
        candidates.insert(candidate, at: insertion)
        if candidates.count > limit { candidates.removeLast() }
      } else {
        candidates.append(candidate)
      }
    }
    if limit == nil { candidates.sort(by: before) }
    return candidates.map { rows[$0.index] }
  }
}
