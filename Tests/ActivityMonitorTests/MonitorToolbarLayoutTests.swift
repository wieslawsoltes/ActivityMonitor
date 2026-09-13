import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

@MainActor final class MonitorToolbarLayoutTests: XCTestCase {
  func testLabelsFitBeforeOptionalToolbarControlsAppear() {
    let tabs = NSHostingView(
      rootView:
        MetricSwitcher(metric: .constant(.cpu), theme: .init(dark: false), controlHeight: 26))
    let tabWidth = ceil(tabs.fittingSize.width)
    XCTAssertFalse(MonitorToolbarLayout(width: 420).showsLabels)
    XCTAssertTrue(MonitorToolbarLayout(width: 720).showsLabels)
    XCTAssertFalse(MonitorToolbarLayout(width: 720).showsExpandedActions)
    XCTAssertTrue(MonitorToolbarLayout(width: 1000).showsExpandedActions)
    for width: CGFloat in stride(from: 420, through: 1440, by: 10) {
      let layout = MonitorToolbarLayout(width: width)
      if layout.showsLabels {
        let actions: CGFloat = layout.showsExpandedActions ? 238 : 68
        let brand: CGFloat = layout.showsBrand ? 40 : 0
        XCTAssertLessThanOrEqual(tabWidth + actions + brand + 128, width)
      }
    }
  }
}
