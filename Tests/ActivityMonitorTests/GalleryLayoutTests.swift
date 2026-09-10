import XCTest

@testable import ActivityMonitor

final class GalleryLayoutTests: XCTestCase {
  func testDefaultGalleryUsesExactlyTwoFittingAppearanceCards() {
    let layout = GalleryLayout(width: 1080)
    XCTAssertEqual(layout.columnCount, 2)
    XCTAssertEqual(layout.cardWidth, 503)
    XCTAssertEqual(layout.cardWidth * 2 + GalleryLayout.spacing, 1024)
  }
  func testCompactGalleryUsesOneCardAndReflowsAtItsExactFitBoundary() {
    XCTAssertEqual(GalleryLayout(width: 390).columnCount, 1)
    XCTAssertEqual(GalleryLayout(width: 390).cardWidth, 334)
    XCTAssertEqual(GalleryLayout(width: 713).columnCount, 1)
    XCTAssertEqual(GalleryLayout(width: 714).columnCount, 2)
    XCTAssertEqual(GalleryLayout(width: 714).cardWidth, 320)
  }
  func testCardsCannotOverlapOrLeaveAnUnintendedThirdColumn() {
    for width in stride(from: 390.0, through: 1800.0, by: 1) {
      let layout = GalleryLayout(width: width)
      XCTAssertTrue((1...2).contains(layout.columnCount))
      XCTAssertGreaterThanOrEqual(layout.cardWidth, GalleryLayout.minimumCardWidth)
      let occupied =
        layout.cardWidth * Double(layout.columnCount) + GalleryLayout.spacing
        * Double(layout.columnCount - 1)
      XCTAssertEqual(occupied, layout.contentWidth, accuracy: 0.001)
    }
  }
}
