import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

struct ProcessTableHarness: View {
  let rows: [ProcessRow]
  var metric: Metric = .cpu
  var dark = false
  @State private var query = ""
  @State private var filter = "All processes"
  @State private var selection: Int32?
  @State private var selected: Set<Int32> = []
  @State private var inspector = false
  @State private var sort = "primary"
  @State private var descending = true
  @FocusState private var search: Bool
  var body: some View {
    MonitorProcessTable(
      rows: rows, metric: metric, theme: .init(dark: dark), query: $query,
      filter: $filter, selection: $selection, selectedIDs: $selected, inspector: $inspector,
      sort: $sort, descending: $descending, inspect: { _ in }, stop: { _ in },
      stopMany: { _ in }, searchFocus: $search)
  }
}

@MainActor final class HeadlessProcessStore: ObservableObject {
  @Published var rows: [ProcessRow]
  init(_ rows: [ProcessRow]) { self.rows = rows }
}
struct UpdatingProcessTableHarness: View {
  @ObservedObject var store: HeadlessProcessStore
  var body: some View { ProcessTableHarness(rows: store.rows) }
}

@MainActor final class HeadlessUITests: XCTestCase {
  private func descendant<T: NSView>(_ root: NSView, _: T.Type) -> T? {
    if let view = root as? T { return view }
    for child in root.subviews { if let view = descendant(child, T.self) { return view } }
    return nil
  }
  private func settle(_ view: NSView) async throws {
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(25))
    view.layoutSubtreeIfNeeded()
  }
  private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
    let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    return image
  }
  private func rowHasInk(_ image: NSBitmapImageRep, width: CGFloat, dark: Bool) -> Bool {
    let scale = CGFloat(image.pixelsWide) / width
    // Inside the first fully visible row, away from the toolbar, header and icons.
    var ink = 0
    let top = width >= 900 ? 110 : 125
    for y in stride(from: top, to: top + 23, by: 2) {
      for x in stride(from: 55, to: min(280, Int(width * 0.32)), by: 3) {
        guard
          let color = image.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?
            .usingColorSpace(.sRGB)
        else { continue }
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        if dark ? brightness > 0.65 : brightness < 0.4 { ink += 1 }
      }
    }
    return ink > 12
  }
  func testEveryListRendersRowsAtTopMiddleAndBottomInBothThemes() async throws {
    let suite = "ActivityMonitor.Headless.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    for metric in Metric.allCases {
      for dark in [false, true] {
        for width: CGFloat in [420, 1000] {
          let host = NSHostingView(
            rootView: ProcessTableHarness(
              rows: PerformanceFixture.rows(1000), metric: metric, dark: dark
            )
            .defaultAppStorage(defaults))
          host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
          // Attach to an unordered window so AppKit initializes its real clip geometry.
          // This window is never shown or made key and cannot interact with user windows.
          let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
          window.isReleasedWhenClosed = false
          window.contentView = host
          defer { window.close() }
          try await settle(host)
          _ = try bitmap(host)
          try await settle(host)
          let anchor = try XCTUnwrap(descendant(host, ProcessTableViewport.Anchor.self))
          let scroll = try XCTUnwrap(anchor.enclosingScrollView)
          let document = try XCTUnwrap(scroll.documentView)
          let height = document.bounds.height
          XCTAssertEqual(height, 41_037, accuracy: 2)
          for fraction in [0.0, 0.5, 1.0, 0.0] {
            let y = max(0, height - scroll.contentView.bounds.height) * fraction
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(host)
            let image = try bitmap(host)
            XCTAssertTrue(
              rowHasInk(image, width: width, dark: dark),
              "Blank \(metric) \(dark) viewport at \(fraction)")
            XCTAssertEqual(document.bounds.height, height, accuracy: 2)
            XCTAssertEqual(scroll.contentView.bounds.minY, y, accuracy: 2)
          }
        }
      }
    }
  }
  func testEveryOverviewAndInspectorRenderInBothThemes() throws {
    let monitor = PerformanceFixture.monitor()
    for dark in [false, true] {
      for metric in Metric.allCases {
        let host = NSHostingView(
          rootView: MonitorOverview(
            metric: metric, range: 15,
            theme: .init(dark: dark), width: 1100
          ).environmentObject(monitor))
        host.frame = CGRect(x: 0, y: 0, width: 1100, height: 220)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(try bitmap(host).pixelsWide, 0)
      }
      let inspector = MonitorInspector(
        process: monitor.rows.first, theme: .init(dark: dark), busy: false,
        close: {}, sample: { _ in }, files: { _ in }, reveal: { _ in }, stop: { _ in })
      let host = NSHostingView(rootView: inspector)
      host.frame = CGRect(x: 0, y: 0, width: 340, height: 600)
      host.layoutSubtreeIfNeeded()
      XCTAssertGreaterThan(try bitmap(host).pixelsWide, 0)
    }
  }
}
