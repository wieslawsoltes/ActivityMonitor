import XCTest

@testable import ActivityMonitor

enum ProcessTreeFixture {
  static func row(_ id: Int32, parent: Int32 = -1, name: String? = nil, start: UInt64 = 100)
    -> ProcessRow
  {
    var row = PerformanceFixture.rows(1)[0]
    row.id = id
    row.parent = parent
    row.name = name ?? "Process \(id)"
    row.start = start
    row.uid = 501
    row.user = "example"
    row.accessible = true
    row.isApp = false
    return row
  }
  static var rows: [ProcessRow] {
    [
      row(10, name: "Workspace"), row(20, parent: 10, name: "Build service"),
      row(30, parent: 20, name: "Compiler worker"), row(40, parent: 20, name: "Index worker"),
      row(50, parent: 10, name: "Preview service"), row(60, name: "Media player"),
    ]
  }
  static func query(_ text: String = "", filter: String = "All processes", metric: Metric = .cpu)
    -> ProcessQuery
  {
    ProcessQuery(metric: metric, query: text, filter: filter, sort: "pid", descending: false)
  }
}

final class ProcessTreeTests: XCTestCase {
  func testForestKeepsEveryProcessExactlyOnceAndPreservesSiblingSortInAllViews() {
    var rows = ProcessTreeFixture.rows
    for i in rows.indices {
      rows[i].cpu = Double(100 - i * 10)
      rows[i].memory = UInt64(i * 1000)
      rows[i].written = UInt64(i * 300)
      rows[i].read = UInt64(1000 - i * 10)
      rows[i].gpuPercent = Double(i * 5)
      rows[i].networkReceived = UInt64(i * 500)
    }
    for metric in Metric.allCases {
      for descending in [false, true] {
        let query = ProcessQuery(
          metric: metric, query: "", filter: "All processes", sort: "primary",
          descending: descending)
        let sorted = query.apply(rows)
        let snapshot = ProcessTreeSnapshot.build(rows, query: query)
        XCTAssertEqual(Set(snapshot.entries.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(snapshot.entries.count, rows.count)
        for parent in [Int32(10), 20] {
          XCTAssertEqual(
            snapshot.entries.filter { $0.parentID == parent }.map(\.id),
            sorted.filter { $0.parent == parent }.map(\.id))
        }
        XCTAssertEqual(
          snapshot.entries.filter { $0.depth == 0 }.map(\.id),
          sorted.filter { $0.parent == -1 }.map(\.id))
        for entry in snapshot.entries where entry.parentID != nil {
          XCTAssertLessThan(
            snapshot.entries.firstIndex { $0.id == entry.parentID }!,
            snapshot.entries.firstIndex { $0.id == entry.id }!)
        }
      }
    }
  }

  func testSearchRetainsAncestorsAndOmitsUnrelatedDescendantsAndSiblings() {
    let tree = ProcessTreeSnapshot.build(
      ProcessTreeFixture.rows, query: ProcessTreeFixture.query("Compiler"))
    XCTAssertEqual(tree.entries.map(\.id), [10, 20, 30])
    XCTAssertEqual(tree.entries.map(\.isContext), [true, true, false])
    XCTAssertEqual(tree.entries.map(\.depth), [0, 1, 2])
    XCTAssertEqual(tree.entries.last?.parentName, "Build service")
    XCTAssertEqual(tree.matchingIDs, [30])
    XCTAssertTrue(tree.filtered)
    let parent = ProcessTreeSnapshot.build(
      ProcessTreeFixture.rows, query: ProcessTreeFixture.query("Workspace"))
    XCTAssertEqual(parent.entries.map(\.id), [10])
    XCTAssertFalse(parent.entries[0].hasChildren)
    XCTAssertTrue(
      ProcessTreeSnapshot.build(ProcessTreeFixture.rows, query: ProcessTreeFixture.query("absent"))
        .entries.isEmpty)
  }

  func testProcessFilterAndSearchKeepOnlyMatchesPlusTheirAncestry() {
    var rows = ProcessTreeFixture.rows
    rows[0].uid = 0
    rows[2].isApp = true
    rows[2].accessible = false
    let tree = ProcessTreeSnapshot.build(
      rows, query: ProcessTreeFixture.query(filter: "Applications"))
    XCTAssertEqual(tree.entries.map(\.id), [10, 20, 30])
    XCTAssertFalse(tree.entries[2].row.accessible)
    var selected = ProcessTreeFixture.query(filter: "Selected processes")
    selected.selected = [40, 60]
    XCTAssertEqual(
      ProcessTreeSnapshot.build(rows, query: selected).entries.map(\.id), [10, 20, 40, 60])
    selected.query = "Index"
    XCTAssertEqual(
      ProcessTreeSnapshot.build(rows, query: selected).entries.map(\.id), [10, 20, 40])
  }

  func testMissingSelfAndRecycledParentsRemainRootsAndCyclesAreDeterministic() {
    let row = ProcessTreeFixture.row
    let rows = [
      row(1, 1, nil, 100), row(2, 99, nil, 100),
      row(3, 4, nil, 100), row(4, -1, nil, 200),
      row(5, 6, nil, 100), row(6, 7, nil, 100), row(7, 5, nil, 100),
    ]
    let first = ProcessTreeSnapshot(sortedRows: rows)
    let reversed = ProcessTreeSnapshot(sortedRows: rows.reversed())
    XCTAssertEqual(first.parents, reversed.parents)
    XCTAssertEqual(first.entries.map(\.id), [1, 2, 3, 4, 5, 7, 6])
    XCTAssertEqual(Set(first.entries.filter { $0.depth == 0 }.map(\.id)), [1, 2, 3, 4, 5])
    XCTAssertEqual(first.entries.count, 7)
    XCTAssertEqual(ProcessTreeSnapshot(sortedRows: rows + rows).entries.count, 7)
  }

  func testDeepChainsUseIterativeTraversalAndCollapseWithoutLosingDescendants() {
    let rows = (1...12_000).map { ProcessTreeFixture.row(Int32($0), parent: Int32($0 - 1)) }
    let snapshot = ProcessTreeSnapshot(
      sortedRows: rows.reversed(), matchingIDs: [12_000], filtered: true)
    XCTAssertEqual(snapshot.entries.count, 12_000)
    XCTAssertEqual(snapshot.entries.last?.depth, 11_999)
    XCTAssertEqual(snapshot.visible(collapsed: [ProcessIdentity(rows[0])]).map(\.id), [1])
    XCTAssertEqual(snapshot.branch(6000).count, 6001)
    XCTAssertEqual(snapshot.visible(collapsed: []).count, rows.count)
  }

  func testCollapseIsIdentityBasedAndReparentingUsesTheCurrentSnapshot() {
    let state = ProcessTreePresentation()
    var rows = ProcessTreeFixture.rows
    state.update(rows, query: ProcessTreeFixture.query())
    state.setExpanded(20, false)
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 50, 60])
    rows[2].parent = 50
    state.update(rows, query: ProcessTreeFixture.query())
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 50, 30, 60])
    rows[1].start = 200
    rows[3].start = 210
    state.update(rows, query: ProcessTreeFixture.query())
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 40, 50, 30, 60])
    XCTAssertTrue(state.collapsed.isEmpty)
    state.collapseAll()
    state.update([], query: ProcessTreeFixture.query())
    XCTAssertTrue(state.collapsed.isEmpty)
    XCTAssertTrue(state.entries.isEmpty)
  }

  func testSearchTemporarilyRevealsMatchesAndRestoresNormalExpansion() {
    let state = ProcessTreePresentation()
    let rows = ProcessTreeFixture.rows
    state.update(rows, query: ProcessTreeFixture.query())
    state.setExpanded(10, false)
    state.update(rows, query: ProcessTreeFixture.query("worker"))
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 30, 40])
    state.setExpanded(20, false)
    XCTAssertEqual(state.entries.map(\.id), [10, 20])
    var sorted = ProcessTreeFixture.query("worker")
    sorted.descending = true
    state.update(rows, query: sorted)
    XCTAssertEqual(state.entries.map(\.id), [10, 20])
    state.update(rows, query: ProcessTreeFixture.query("Compiler"))
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 30])
    state.update(rows, query: ProcessTreeFixture.query())
    XCTAssertEqual(state.entries.map(\.id), [10, 60])
    state.expandAll()
    XCTAssertEqual(state.entries.count, 6)
  }

  func testRecursiveExpansionAndKeyboardNavigationFollowNativeOutlineBehavior() {
    let state = ProcessTreePresentation()
    state.update(ProcessTreeFixture.rows, query: ProcessTreeFixture.query())
    XCTAssertEqual(state.navigate(10, right: false), 10)
    XCTAssertEqual(state.entries.map(\.id), [10, 60])
    XCTAssertEqual(state.navigate(10, right: true), 10)
    XCTAssertEqual(state.navigate(10, right: true), 20)
    XCTAssertEqual(state.navigate(30, right: true), 30)
    XCTAssertEqual(state.navigate(30, right: false), 20)
    state.setExpanded(10, false, recursive: true)
    state.setExpanded(10, true)
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 50, 60])
    _ = state.navigate(10, right: true, recursive: true)
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 30, 40, 50, 60])
    state.collapseAll()
    state.reveal(30)
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 30, 40, 50, 60])
  }

  func testCollapseMovesHiddenSelectionToVisibleAncestorAndClearsReusedIdentities() {
    let state = ProcessTreePresentation()
    var rows = ProcessTreeFixture.rows
    state.update(rows, query: ProcessTreeFixture.query())
    state.selectedStarts = [30: 100, 60: 100]
    let selected = ProcessListSelection(ids: [30, 60], anchor: 30, lead: 30)
    state.setExpanded(10, false)
    let collapsed = state.reconcile(selected, visible: state.entries, source: rows)
    XCTAssertEqual(collapsed.ids, [10, 60])
    XCTAssertEqual(collapsed.lead, 10)
    XCTAssertEqual(collapsed.anchor, 10)
    rows[2].start = 200
    state.update(rows, query: ProcessTreeFixture.query())
    let reused = state.reconcile(selected, visible: state.entries, source: rows)
    XCTAssertEqual(reused.ids, [60])
    XCTAssertEqual(reused.lead, 60)
    let empty = state.reconcile(selected, visible: [], source: [])
    XCTAssertTrue(empty.ids.isEmpty)
    XCTAssertNil(empty.lead)
  }

  func testContextCanBeSelectedAndCopiedInDisplayedTreeOrder() {
    let rows = ProcessTreeFixture.rows
    let state = ProcessTreePresentation()
    state.update(rows, query: ProcessTreeFixture.query("Compiler"))
    let selection = ProcessListSelection(ids: [10, 20, 30], anchor: 10, lead: 30)
    let reconciled = state.reconcile(selection, visible: state.entries, source: rows)
    XCTAssertEqual(reconciled.ids, selection.ids)
    let text = processClipboard(state.entries.map(\.row), keys: ["name", "pid"], metric: .cpu)
    XCTAssertEqual(
      text.components(separatedBy: "\n").dropFirst(),
      ["Workspace\t10", "Build service\t20", "Compiler worker\t30"])
  }

  func testFilteringOutSelectionDoesNotSelectAnUnrelatedAncestor() {
    let state = ProcessTreePresentation()
    let rows = ProcessTreeFixture.rows
    state.update(rows, query: ProcessTreeFixture.query())
    state.selectedStarts = [30: 100]
    let selection = ProcessListSelection(ids: [30], anchor: 30, lead: 30)
    state.update(rows, query: ProcessTreeFixture.query("Preview"))
    XCTAssertEqual(state.entries.map(\.id), [10, 50])
    let filtered = state.reconcile(selection, visible: state.entries, source: rows)
    XCTAssertTrue(filtered.ids.isEmpty)
    XCTAssertNil(filtered.lead)
    state.update(rows, query: ProcessTreeFixture.query())
    let list = state.reconcile(
      selection, visible: Array(state.entries.prefix(1)), source: rows, hierarchical: false)
    XCTAssertTrue(list.ids.isEmpty)
    XCTAssertNil(list.lead)
  }
  func testTreeCSVKeepsVisibleOrderAndParentIDsWithoutChangingListSchema() {
    let tree = ProcessTreeSnapshot.build(
      ProcessTreeFixture.rows, query: ProcessTreeFixture.query("Compiler"))
    let rows = tree.visible(collapsed: []).map(\.row)
    let csv = processCSV(rows, includeHierarchy: true).components(separatedBy: "\n")
    XCTAssertTrue(csv[0].hasSuffix(",Parent PID"))
    XCTAssertEqual(
      csv.dropFirst().map { $0.components(separatedBy: ",").last! }, ["-1", "10", "20"])
    XCTAssertTrue(csv[1].hasPrefix("\"Workspace\",10,"))
    XCTAssertFalse(processCSV(rows).components(separatedBy: "\n")[0].contains("Parent PID"))
  }

  func testNameColumnReservesReadableSpaceAtAnyDepthAndFitsIndentation() {
    for width: CGFloat in [140, 180, 240, 600, 1200] {
      XCTAssertLessThanOrEqual(
        ProcessTreeGeometry.indentation(depth: 100_000, width: width), max(12, width - 150))
      XCTAssertEqual(ProcessTreeGeometry.indentation(depth: 0, width: width), 0)
    }
    let shallow = ProcessTreeEntry(row: ProcessTreeFixture.row(1), depth: 0, hasChildren: false)
    var deep = shallow
    deep.depth = 5
    XCTAssertEqual(
      ProcessTreeGeometry.fittedNameWidth([deep]) - ProcessTreeGeometry.fittedNameWidth([shallow]),
      70, accuracy: 1)
  }
}
