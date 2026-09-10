import AppKit
import SwiftUI
import SystemBridge
import XCTest

@testable import ActivityMonitor

@MainActor final class ProcessDiagnosticsUITests: XCTestCase {
  private func descendant<T: NSView>(_ root: NSView, _ type: T.Type) -> T? {
    if let value = root as? T, value.identifier?.rawValue == "process-diagnostic-table" {
      return value
    }
    for child in root.subviews { if let value = descendant(child, type) { return value } }
    return nil
  }
  private func fixture() -> ProcessDiagnosticSession {
    var row = PerformanceFixture.rows(1)[0]
    row.id = getpid()
    row.name = "Process Diagnostics Preview"
    var start: UInt64 = 0
    _ = am_process_identity(row.id, &start)
    row.start = start
    let session = ProcessDiagnosticSession(
      row: row,
      reader: { identity, tab in
        let columns: [String]
        switch tab {
        case .threads:
          columns = ["Thread ID", "Name", "CPU %", "User time", "System time", "State", "Priority"]
        case .files: columns = ["FD", "Type", "Path", "Size", "Offset", "Inode", "Access"]
        case .connections:
          columns = [
            "FD", "Protocol", "Local endpoint", "Remote endpoint", "State", "Receive queue",
            "Send queue",
          ]
        case .maps, .images: columns = ["Address", "Size", "Resident", "Protection", "Path"]
        default: columns = ["Name", "Rights", "Type"]
        }
        let records: [DiagnosticRecord] = (0..<2500).map { index in
          DiagnosticRecord(
            id: String(index),
            cells: Dictionary(
              uniqueKeysWithValues: columns.map { key in
                (
                  key,
                  key == "Path"
                    ? "/Applications/Example.app/Contents/Resources/Document-\(index).json"
                    : key == "Name" ? "Worker \(index)" : "\(index)"
                )
              }), numbers: Dictionary(uniqueKeysWithValues: columns.map { ($0, Double(index)) }))
        }
        return DiagnosticSnapshot(
          identity: identity,
          fields: [
            .init("Executable", "/Applications/Example.app/Contents/MacOS/Example"),
            .init("User CPU time", "0:04:12"), .init("System CPU time", "0:01:03"),
          ],
          section: .init(columns: columns, records: records, status: "2500 entries", date: Date()),
          tab: tab)
      })
    let end = Date()
    for index in 0..<61 {
      row.cpu = 120 + sin(Double(index) / 5) * 80
      row.memory = UInt64(500_000_000 + index * 100_000)
      row.read = UInt64(index * 300000)
      row.written = UInt64(index * 500000)
      row.networkReceived = UInt64(index * 120000)
      row.networkSent = UInt64(index * 80000)
      row.gpuPercent = 25 + sin(Double(index) / 10) * 15
      session.accept(rows: [row], date: end.addingTimeInterval(Double(index - 60)))
    }
    return session
  }
  private func collect(_ session: ProcessDiagnosticSession) async throws {
    session.refreshDetails(force: true)
    for _ in 0..<200 {
      if !session.collecting { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Diagnostic worker did not finish")
  }
  func testEveryDiagnosticPageRendersInBothThemesAtMinimumAndDefaultSizes() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "Diagnostics.Headless"))
    defer { defaults.removePersistentDomain(forName: "Diagnostics.Headless") }
    let monitor = Monitor(startAutomatically: false)
    let session = fixture()
    for dark in [false, true] {
      defaults.set(dark ? "Dark" : "Light", forKey: "appearance")
      for tab in DiagnosticTab.allCases {
        session.tab = tab
        try await collect(session)
        for size in [NSSize(width: 760, height: 500), NSSize(width: 1060, height: 740)] {
          let root = ProcessDiagnosticsView(
            session: session, center: monitor.diagnostics, persistTableColumns: false, close: {}
          )
          .defaultAppStorage(defaults)
          let host = NSHostingView(rootView: root)
          let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
            backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.contentView = host
          host.frame = NSRect(origin: .zero, size: size)
          host.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(15))
          host.layoutSubtreeIfNeeded()
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          XCTAssertGreaterThan(bitmap.pixelsWide, 700, "\(tab) \(dark)")
          XCTAssertEqual(host.bounds.width, size.width, accuracy: 1)
          if let table = descendant(host, NSTableView.self) {
            XCTAssertEqual(table.numberOfRows, 2500)
            XCTAssertTrue(table.allowsColumnResizing)
            XCTAssertTrue(table.allowsColumnReordering)
            let scroll = try XCTUnwrap(table.enclosingScrollView)
            XCTAssertLessThanOrEqual(scroll.frame.maxX, host.bounds.width + 1)
            table.scrollRowToVisible(2499)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(table.rows(in: scroll.documentVisibleRect).contains(2499))
            let original = table.tableColumns[0]
            original.width += 45
            table.moveColumn(0, toColumn: 1)
            XCTAssertTrue(table.tableColumns[1] === original)
          }
          window.contentView = nil
          window.close()
        }
      }
    }
  }
  func testNativeTableRetainsSelectionWhenSortingAndFiltering() async throws {
    let records = (0..<50).map {
      DiagnosticRecord(
        id: String($0), cells: ["Name": "Worker \($0)", "Value": String($0)],
        numbers: ["Value": Double($0)])
    }
    let section = DiagnosticSection(
      columns: ["Name", "Value"], records: records, status: "50 entries", date: Date())
    let host = NSHostingView(
      rootView: DiagnosticTable(
        section: section, query: "", key: "headless", theme: .init(dark: false),
        persistColumns: false))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 500), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    defer {
      window.contentView = nil
      window.close()
    }
    let table = try XCTUnwrap(descendant(host, NSTableView.self))
    table.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
    table.sortDescriptors = [NSSortDescriptor(key: "Value", ascending: false)]
    XCTAssertEqual(table.selectedRow, 44)
    host.rootView = DiagnosticTable(
      section: section, query: "Worker 5", key: "headless", theme: .init(dark: false),
      persistColumns: false)
    try await Task.sleep(for: .milliseconds(20))
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(table.numberOfRows, 1)
    XCTAssertEqual(table.selectedRow, 0)
  }
  func testAccessDeniedDoesNotClaimExitAndRefreshSwitchesToLatestTab() async throws {
    let row = PerformanceFixture.rows(1)[0]
    let denied = ProcessDiagnosticSession(
      row: row,
      reader: { identity, tab in
        var result = DiagnosticSnapshot(identity: identity, tab: tab)
        result.valid = false
        result.identityStatus = .unavailable
        return result
      })
    try await collect(denied)
    XCTAssertFalse(denied.exited)
    XCTAssertNotNil(denied.collectionStatus)
    let session = fixture()
    session.tab = .threads
    session.refreshDetails(force: true)
    session.tab = .connections
    for _ in 0..<200 {
      if !session.collecting { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNotNil(session.sections[.connections])
  }
}
