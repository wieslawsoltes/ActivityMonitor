import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

@MainActor final class CPUAdaptiveStateTests: XCTestCase {
  func testLogicalModeAndGridPreferencesSurviveWorkspaceRecreation() async throws {
    let presentation = CPUChartPresentation()
    XCTAssertFalse(presentation.individual)
    XCTAssertFalse(presentation.paginated)
    let monitor = PerformanceFixture.monitor()
    let host = NSHostingView(
      rootView: ContentView(cpuPresentation: presentation)
        .environmentObject(monitor).environmentObject(MonitorNavigation()))
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
    host.layoutSubtreeIfNeeded()
    presentation.individual = true
    presentation.paginated = true
    presentation.query = "Performance"
    presentation.page = 1
    for size in [
      CGSize(width: 1440, height: 900), .init(width: 1119, height: 900),
      .init(width: 420, height: 600), .init(width: 1440, height: 699),
      .init(width: 1600, height: 1000), .init(width: 720, height: 900),
      .init(width: 1440, height: 900),
    ] {
      window.setContentSize(size)
      host.frame = .init(origin: .zero, size: size)
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(40))
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      XCTAssertGreaterThan(bitmap.pixelsWide, 0)
      XCTAssertTrue(presentation.individual)
      XCTAssertTrue(presentation.paginated)
      XCTAssertEqual(presentation.query, "Performance")
      XCTAssertEqual(presentation.page, 1)
    }
  }

  func testGridHeightAdaptsToCountAndViewportWithoutChangingMode() {
    let small = CPUOverviewGeometry.height(width: 1388, viewportHeight: 780, count: 4)
    let many = CPUOverviewGeometry.height(width: 1388, viewportHeight: 780, count: 64)
    XCTAssertGreaterThan(many, small)
    XCTAssertLessThan(CPUOverviewGeometry.height(width: 1388, viewportHeight: 450, count: 64), many)
    for count in [1, 11, 16, 64, 128] {
      for width: CGFloat in [392, 668, 1068, 1748] {
        let height = CPUOverviewGeometry.height(width: width, viewportHeight: 780, count: count)
        XCTAssertGreaterThanOrEqual(height, 220)
        XCTAssertLessThanOrEqual(height, 480)
        let grid = CPUGridLayout(count: count, size: .init(width: width - 40, height: height - 130))
        XCTAssertGreaterThanOrEqual(grid.tileHeight, 38)
        XCTAssertGreaterThanOrEqual(grid.columns * grid.rows, count)
      }
    }
  }

  func testGridAvoidsNearlyEmptyRowsForUnevenProcessorCounts() {
    for width: CGFloat in [560, 1350] {
      let layout = CPUGridLayout(count: 11, size: .init(width: width, height: 150))
      XCTAssertFalse(layout.scrolls)
      XCTAssertLessThanOrEqual(layout.columns * layout.rows - 11, 1)
    }
  }

  func testGridPreferencesResetPageOnlyForExplicitFilterOrLayoutChanges() {
    let state = CPUChartPresentation()
    state.paginated = true
    state.page = 3
    state.individual = true
    state.details = true
    XCTAssertEqual(state.page, 3)
    state.query = "Worker"
    XCTAssertEqual(state.page, 0)
    state.page = 2
    state.query = "Worker"
    XCTAssertEqual(state.page, 2)
    state.paginated = false
    XCTAssertEqual(state.page, 0)
  }
}
