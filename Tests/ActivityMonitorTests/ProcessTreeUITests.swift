import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

@MainActor final class ProcessTreeUITests: XCTestCase {
  private func descendant<T: NSView>(_ root: NSView, _: T.Type) -> T? {
    if let result = root as? T { return result }
    for child in root.subviews { if let result = descendant(child, T.self) { return result } }
    return nil
  }
  private func settle(_ host: NSView) async throws {
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try await Task.sleep(for: .milliseconds(50))
    host.layoutSubtreeIfNeeded()
  }
  private func document(_ host: NSView) throws -> NSView {
    try XCTUnwrap(
      descendant(host, ProcessTableViewport.Anchor.self)?.enclosingScrollView?.documentView)
  }
  private func save(_ host: NSView, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["AM_TREE_RENDER_DIR"] else { return }
    let url = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: url.appendingPathComponent(name + ".png"))
  }

  func testModeExpansionAndSelectionSurviveAdaptiveRecreationAndMetricChanges() async throws {
    let suite = "ActivityMonitor.Tree.Adaptive.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("tree", forKey: "processViewMode.v1")
    let tree = ProcessTreePresentation()
    let monitor = PerformanceFixture.monitor()
    monitor.rows = ProcessTreeFixture.rows
    let navigation = MonitorNavigation()
    let host = NSHostingView(
      rootView:
        ContentView(processTree: tree, selection: 30, selectedIDs: [30])
        .environmentObject(monitor).environmentObject(navigation).defaultAppStorage(defaults))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 1440, height: 900),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    host.frame = window.contentView!.bounds
    try await settle(host)
    XCTAssertEqual(tree.entries.count, 6)
    tree.setExpanded(20, false)
    try await settle(host)
    XCTAssertEqual(tree.selectedStarts, [20: 100])
    for size in [
      CGSize(width: 1440, height: 900), .init(width: 1119, height: 900),
      .init(width: 420, height: 600), .init(width: 1440, height: 699),
      .init(width: 1600, height: 1000), .init(width: 720, height: 900),
    ] {
      window.setContentSize(size)
      host.frame = .init(origin: .zero, size: size)
      try await settle(host)
      XCTAssertEqual(tree.entries.map(\.id), [10, 20, 50, 60])
      XCTAssertEqual(try document(host).bounds.height, 37 + 4 * 41, accuracy: 2)
      XCTAssertEqual(defaults.string(forKey: "processViewMode.v1"), "tree")
      XCTAssertEqual(tree.selectedStarts, [20: 100])
    }
    for metric in [Metric.memory, .disk, .network, .gpu, .cpu] {
      navigation.request = MonitorDestination(metric: metric, range: 1, pid: nil)
      try await settle(host)
      XCTAssertEqual(Set(tree.entries.map(\.id)), [10, 20, 50, 60])
      XCTAssertEqual(try document(host).bounds.height, 37 + 4 * 41, accuracy: 2)
    }
    defaults.set("list", forKey: "processViewMode.v1")
    try await settle(host)
    XCTAssertEqual(try document(host).bounds.height, 37 + 6 * 41, accuracy: 2)
    defaults.set("tree", forKey: "processViewMode.v1")
    try await settle(host)
    XCTAssertEqual(try document(host).bounds.height, 37 + 4 * 41, accuracy: 2)
    XCTAssertEqual(tree.selectedStarts, [20: 100])
  }

  func testSavedModeReopensAndEveryTreeRendersInBothThemesAndWidths() async throws {
    let suite = "ActivityMonitor.Tree.Render.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("tree", forKey: "processViewMode.v1")
    let monitor = PerformanceFixture.monitor()
    monitor.rows = ProcessTreeFixture.rows
    for dark in [false, true] {
      defaults.set(dark ? "Dark" : "Light", forKey: "appearance")
      for metric in Metric.allCases {
        for width: CGFloat in [420, 1440] {
          let tree = ProcessTreePresentation()
          let host = NSHostingView(
            rootView: ContentView(processTree: tree, metric: metric)
              .environmentObject(monitor).environmentObject(MonitorNavigation())
              .defaultAppStorage(defaults))
          let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: width, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.contentView = host
          host.frame = window.contentView!.bounds
          try await settle(host)
          XCTAssertEqual(tree.entries.count, 6)
          XCTAssertEqual(try document(host).bounds.height, 37 + 6 * 41, accuracy: 2)
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          XCTAssertGreaterThan(bitmap.pixelsWide, 0)
          try save(host, name: "\(metric.rawValue)-\(dark ? "dark" : "light")-\(Int(width))")
          window.contentView = nil
          window.close()
        }
      }
    }
  }

  func testFilteredTreeKeepsContextWithReorderedNarrowNameColumnAndOverflow() async throws {
    let suite = "ActivityMonitor.Tree.Columns.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("tree", forKey: "processViewMode.v1")
    defaults.set(true, forKey: "showAllProcessColumns")
    var order = ProcessColumnOrder()
    order.move("name", to: "time", metric: .cpu)
    defaults.set(order.json, forKey: "processColumnOrder.v1")
    var widths = ProcessColumnWidths()
    widths.set("name", metric: .cpu, width: 140)
    defaults.set(widths.json, forKey: "processColumnWidths.v1")
    let tree = ProcessTreePresentation()
    let monitor = PerformanceFixture.monitor()
    monitor.rows = ProcessTreeFixture.rows
    let host = NSHostingView(
      rootView: ContentView(processTree: tree, query: "Compiler")
        .environmentObject(monitor).environmentObject(MonitorNavigation()).defaultAppStorage(
          defaults))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 600, height: 900),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    host.frame = window.contentView!.bounds
    try await settle(host)
    XCTAssertEqual(tree.entries.map(\.id), [10, 20, 30])
    let anchor = try XCTUnwrap(descendant(host, ProcessTableViewport.Anchor.self))
    let scroll = try XCTUnwrap(anchor.enclosingScrollView)
    let content = try document(host)
    XCTAssertGreaterThan(content.bounds.width, scroll.contentView.bounds.width)
    scroll.contentView.scroll(to: .init(x: 70, y: 0))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(host)
    tree.setExpanded(20, false)
    try await settle(host)
    XCTAssertEqual(scroll.contentView.bounds.minX, 70, accuracy: 2)
    XCTAssertEqual(content.bounds.height, 37 + 2 * 41, accuracy: 2)
    tree.expandAll()
    try await settle(host)
    try save(host, name: "filtered-narrow-reordered")
    XCTAssertEqual(content.bounds.height, 37 + 3 * 41, accuracy: 2)
  }
}
