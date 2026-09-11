import AppKit
import SwiftUI

enum ProcessViewMode: String, CaseIterable, Identifiable {
  case list, tree
  var id: String { rawValue }
  var title: String { self == .list ? "List" : "Tree" }
  var icon: String { self == .list ? "list.bullet" : "list.bullet.indent" }
}

struct ProcessTreeEntry: Identifiable, Equatable {
  var row: ProcessRow
  var depth: Int
  var hasChildren: Bool
  var parentID: Int32? = nil
  var parentName: String? = nil
  var isContext = false
  var expanded = true
  var id: Int32 { row.id }
  var identity: ProcessIdentity { ProcessIdentity(row) }
}

/// An immutable, sorted forest built before filtering or collapsing branches.
struct ProcessTreeSnapshot {
  var entries: [ProcessTreeEntry] = []
  var parents: [Int32: Int32] = [:]
  var rowsByID: [Int32: ProcessRow] = [:]
  var matchingIDs: Set<Int32> = []
  var filtered = false

  init() {}

  init(sortedRows: [ProcessRow], matchingIDs: Set<Int32>? = nil, filtered: Bool = false) {
    // Snapshot races must not create duplicate row identities.
    var rows: [ProcessRow] = []
    for row in sortedRows where rowsByID[row.id] == nil {
      rowsByID[row.id] = row
      rows.append(row)
    }
    self.matchingIDs = (matchingIDs ?? Set(rowsByID.keys)).intersection(rowsByID.keys)
    self.filtered = filtered
    for row in rows {
      guard row.parent != row.id, let parent = rowsByID[row.parent],
        parent.start == 0 || row.start == 0 || parent.start <= row.start
      else { continue }
      parents[row.id] = parent.id
    }

    // Break each cycle at its smallest PID, independent of the selected sort.
    // Each edge is visited once, even for a very deep process chain.
    var checked = Set<Int32>()
    for row in rows where !checked.contains(row.id) {
      var path: [Int32] = []
      var positions: [Int32: Int] = [:]
      var cursor: Int32? = row.id
      while let id = cursor, !checked.contains(id) {
        if let cycle = positions[id] {
          if let root = path[cycle...].min() { parents[root] = nil }
          break
        }
        positions[id] = path.count
        path.append(id)
        cursor = parents[id]
      }
      checked.formUnion(path)
    }

    var included = Set<Int32>()
    for id in self.matchingIDs where rowsByID[id] != nil {
      var cursor: Int32? = id
      while let next = cursor, included.insert(next).inserted { cursor = parents[next] }
    }
    let includedRows = rows.filter { included.contains($0.id) }
    var children: [Int32: [ProcessRow]] = [:]
    var roots: [ProcessRow] = []
    for row in includedRows {
      if let parent = parents[row.id] {
        children[parent, default: []].append(row)
      } else {
        roots.append(row)
      }
    }
    var pending = roots.reversed().map { ($0, 0) }
    while let (row, depth) = pending.popLast() {
      let descendants = children[row.id] ?? []
      entries.append(
        ProcessTreeEntry(
          row: row, depth: depth, hasChildren: !descendants.isEmpty,
          parentID: parents[row.id], parentName: parents[row.id].flatMap { rowsByID[$0]?.name },
          isContext: !self.matchingIDs.contains(row.id)))
      for child in descendants.reversed() { pending.append((child, depth + 1)) }
    }
  }

  static func build(
    _ rows: [ProcessRow], query: ProcessQuery, matches: [ProcessRow]? = nil
  ) -> Self {
    let matching = matches ?? query.apply(rows)
    let filtered =
      !query.query.isEmpty
      || !["All processes", "All processes, hierarchically"].contains(query.filter)
    var ordering = query
    ordering.query = ""
    ordering.filter = "All processes"
    return Self(
      sortedRows: filtered ? ordering.apply(rows) : matching,
      matchingIDs: Set(matching.map(\.id)), filtered: filtered)
  }

  func visible(collapsed: Set<ProcessIdentity>) -> [ProcessTreeEntry] {
    var result: [ProcessTreeEntry] = []
    var hiddenBelow: Int?
    for var entry in entries {
      if let depth = hiddenBelow, entry.depth > depth { continue }
      hiddenBelow = nil
      entry.expanded = entry.hasChildren && !collapsed.contains(entry.identity)
      result.append(entry)
      if entry.hasChildren && !entry.expanded { hiddenBelow = entry.depth }
    }
    return result
  }

  func branch(_ id: Int32) -> ArraySlice<ProcessTreeEntry> {
    guard let start = entries.firstIndex(where: { $0.id == id }) else { return [] }
    let end =
      entries[(start + 1)...].firstIndex { $0.depth <= entries[start].depth }
      ?? entries.endIndex
    return entries[start..<end]
  }
}

/// Window-owned state, never recreated by adaptive layout branches. Only the
/// display mode is persisted by the owner; process identities live for this session.
final class ProcessTreePresentation: ObservableObject {
  @Published private(set) var entries: [ProcessTreeEntry] = []
  @Published private(set) var revealRevision = 0
  private(set) var snapshot = ProcessTreeSnapshot()
  private(set) var collapsed: Set<ProcessIdentity> = []
  private var filteredCollapsed: Set<ProcessIdentity> = []
  private var filterScope: FilterScope?
  var selectionAnchor: Int32?
  var selectedStarts: [Int32: UInt64] = [:]

  private struct FilterScope: Equatable {
    let query: String
    let filter: String
    let selected: Set<Int32>
  }
  private var activeCollapsed: Set<ProcessIdentity> {
    get { snapshot.filtered ? filteredCollapsed : collapsed }
    set {
      if snapshot.filtered { filteredCollapsed = newValue } else { collapsed = newValue }
    }
  }
  var hasBranches: Bool { snapshot.entries.contains(where: \.hasChildren) }
  var contextCount: Int { snapshot.entries.count - snapshot.matchingIDs.count }

  func retainIdentities(_ rows: [ProcessRow]) {
    guard !collapsed.isEmpty || !filteredCollapsed.isEmpty else { return }
    let identities = Set(rows.map(ProcessIdentity.init))
    collapsed.formIntersection(identities)
    filteredCollapsed.formIntersection(identities)
  }
  func update(_ rows: [ProcessRow], query: ProcessQuery, matches: [ProcessRow]? = nil) {
    retainIdentities(rows)
    let scope = FilterScope(
      query: query.query, filter: query.filter,
      selected: query.filter == "Selected processes" ? query.selected : [])
    if filterScope != scope {
      filteredCollapsed = []
      filterScope = scope
    }
    snapshot = .build(rows, query: query, matches: matches)
    refresh()
  }
  private func refresh(reveal: Bool = false) {
    entries = snapshot.visible(collapsed: activeCollapsed)
    if reveal { revealRevision &+= 1 }
  }
  func setExpanded(_ id: Int32, _ expanded: Bool, recursive: Bool = false) {
    let branch = snapshot.branch(id)
    let targets = recursive ? branch.filter(\.hasChildren) : branch.prefix(1).filter(\.hasChildren)
    let identities = targets.map(\.identity)
    if expanded {
      activeCollapsed.subtract(identities)
    } else {
      activeCollapsed.formUnion(identities)
    }
    refresh(reveal: true)
  }
  func toggle(_ id: Int32, recursive: Bool = false) {
    guard let entry = entries.first(where: { $0.id == id }), entry.hasChildren else { return }
    setExpanded(id, !entry.expanded, recursive: recursive)
  }
  func expandAll() {
    activeCollapsed = []
    refresh(reveal: true)
  }
  func collapseAll() {
    activeCollapsed = Set(snapshot.entries.filter(\.hasChildren).map(\.identity))
    refresh(reveal: true)
  }
  func reveal(_ id: Int32) {
    var cursor = snapshot.parents[id]
    while let parent = cursor, let row = snapshot.rowsByID[parent] {
      activeCollapsed.remove(ProcessIdentity(row))
      cursor = snapshot.parents[parent]
    }
    refresh(reveal: true)
  }
  /// Native outline navigation: a leaf never jumps to an unrelated next row.
  func navigate(_ id: Int32, right: Bool, recursive: Bool = false) -> Int32 {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return id }
    let entry = entries[index]
    if right {
      guard entry.hasChildren else { return id }
      if !entry.expanded || recursive {
        setExpanded(id, true, recursive: recursive)
        return id
      }
      return index + 1 < entries.count ? entries[index + 1].id : id
    }
    if entry.hasChildren && entry.expanded {
      setExpanded(id, false, recursive: recursive)
      return id
    }
    return entry.parentID ?? id
  }

  func reconcile(
    _ selection: ProcessListSelection, visible: [ProcessTreeEntry], source: [ProcessRow],
    hierarchical: Bool = true
  ) -> ProcessListSelection {
    let starts = Dictionary(
      source.map { ($0.id, $0.start) }, uniquingKeysWith: { first, _ in first })
    let alive = selection.ids.filter {
      starts[$0] != nil && (selectedStarts[$0] == nil || starts[$0] == selectedStarts[$0])
    }
    let visibleIDs = Set(visible.map(\.id))
    var result = selection
    result.ids = alive.intersection(visibleIDs)
    // Only a collapsed descendant moves to an ancestor. Filtering out a process
    // must not silently select a root belonging to a different search result.
    if hierarchical, let lead = selection.lead, alive.contains(lead), !visibleIDs.contains(lead),
      snapshot.entries.contains(where: { $0.id == lead })
    {
      var cursor = snapshot.parents[lead]
      while let parent = cursor, !visibleIDs.contains(parent) { cursor = snapshot.parents[parent] }
      if let parent = cursor {
        result.ids.insert(parent)
        result.lead = parent
      }
    }
    if result.lead == nil || !result.ids.contains(result.lead!) {
      result.lead = visible.first { result.ids.contains($0.id) }?.id
    }
    if result.anchor == nil || !visibleIDs.contains(result.anchor!) { result.anchor = result.lead }
    return result
  }
}

enum ProcessTreeGeometry {
  static func indentation(depth: Int, width: CGFloat) -> CGFloat {
    min(CGFloat(max(0, depth)) * 14, max(0, width - 120), max(12, width - 150))
  }
  static func fittedNameWidth(_ entries: [ProcessTreeEntry]) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 12)
    let widest = entries.reduce(CGFloat(0)) { width, entry in
      let text = (entry.row.name as NSString).size(withAttributes: [.font: font]).width
      return max(width, text + 90 + CGFloat(entry.depth) * 14 + (entry.isContext ? 44 : 0))
    }
    return ProcessColumnWidths.clamp(ceil(widest), key: "name")
  }
}
