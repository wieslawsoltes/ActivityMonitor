import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

@MainActor final class ToolbarMetricPickerTests: XCTestCase {
  func testNativeSegmentsUpdateTheMetricBinding() async throws {
    for compact in [false, true] {
      var selection = Metric.cpu
      let host = NSHostingView(rootView: ToolbarMetricPicker(
        metric: Binding(get: { selection }, set: { selection = $0 }), compact: compact))
      host.frame = NSRect(x: 0, y: 0, width: compact ? 240 : 680, height: 50)
      let window = NSWindow(
        contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(30))
      host.layoutSubtreeIfNeeded()
      let control = try XCTUnwrap(segmentedControl(in: host))
      XCTAssertEqual(control.segmentCount, Metric.allCases.count)
      XCTAssertEqual(control.selectedSegment, 0)
      XCTAssertLessThanOrEqual(control.fittingSize.width, compact ? 210 : 600)
      for (index, metric) in Metric.allCases.enumerated() {
        control.selectedSegment = index
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
        XCTAssertEqual(selection, metric, "compact=\(compact)")
      }
    }
  }

  private func segmentedControl(in view: NSView) -> NSSegmentedControl? {
    if let control = view as? NSSegmentedControl { return control }
    return view.subviews.lazy.compactMap { self.segmentedControl(in: $0) }.first
  }
}
