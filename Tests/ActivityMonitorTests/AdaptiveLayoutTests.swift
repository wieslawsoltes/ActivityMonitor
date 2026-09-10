import XCTest

@testable import ActivityMonitor

final class AdaptiveLayoutTests: XCTestCase {
  func testDefaultGeometryAndAdaptiveBoundaries() {
    let standard = MonitorLayout(width: 1440, height: 900)
    XCTAssertTrue(standard.standard)
    XCTAssertFalse(standard.scrollsWorkspace)
    XCTAssertEqual(standard.overviewHeight, 213)
    XCTAssertTrue(standard.inlineInspector)
    XCTAssertEqual(standard.gutter, 26)
    XCTAssertTrue(MonitorLayout(width: 420, height: 480).compact)
    XCTAssertTrue(MonitorLayout(width: 1440, height: 500).scrollsWorkspace)
    XCTAssertFalse(MonitorLayout(width: 1440, height: 500).inlineInspector)
    XCTAssertEqual(MonitorLayout(width: 1800, height: 1100).overviewHeight, 280)
  }
  func testPanelsStayInsideWidthAndNeverOverlapAcrossBreakpoints() {
    for width in [CGFloat(0), 392, 500, 667, 668, 1067, 1068, 1388, 1748] {
      for expanded in [false, true] {
        let frames = OverviewGrid.frames(width: width, expanded: expanded)
        XCTAssertEqual(frames.count, 3)
        for frame in frames {
          XCTAssertGreaterThanOrEqual(frame.width, 0)
          XCTAssertGreaterThanOrEqual(frame.minX, 0)
          XCTAssertLessThanOrEqual(frame.maxX, width + 0.001)
        }
        for i in 0..<3 { for j in (i + 1)..<3 { XCTAssertFalse(frames[i].intersects(frames[j])) } }
      }
    }
    let standard = OverviewGrid.frames(width: 1388, expanded: false)
    XCTAssertEqual(standard[0].width / standard[1].width, 1.82, accuracy: 0.001)
    XCTAssertEqual(standard[2].maxY, 213)
  }
  func testCompactOverviewLeavesRoomForProcessesWithoutHidingMediumWidthDetails() {
    for width in [CGFloat(668), 800, 1067] {
      let panels = OverviewGrid.frames(width: width, expanded: false)
      XCTAssertEqual(panels[0].height, 148)
      XCTAssertEqual(panels[1].minY, 158)
      XCTAssertEqual(panels[1].maxY, panels[2].maxY)
      XCTAssertLessThanOrEqual(panels[2].maxY, 306)
      // Previously these same two rows occupied 440 points before the table.
      XCTAssertGreaterThanOrEqual(440 - panels[2].maxY, 134)
    }
    let shortWindow = MonitorLayout(width: 1440, height: 600)
    XCTAssertTrue(shortWindow.denseOverview)
    XCTAssertEqual(shortWindow.overviewHeight, 148)
    let shortPanels = OverviewGrid.frames(width: 1388, expanded: false, condensed: true)
    XCTAssertEqual(shortPanels.map(\.maxY), [148, 148, 148])
    XCTAssertFalse(MonitorLayout(width: 1440, height: 900).denseOverview)
    XCTAssertEqual(OverviewGrid.frames(width: 1748, expanded: true)[2].maxY, 280)
  }
  func testProcessListFillsRemainingViewportAcrossResizeAndOverviewChanges() {
    // Includes collapsed details, two-row summaries, and expanded disclosure content.
    for viewport in [CGFloat(638), 778, 1100, 1600] {
      for overview in [CGFloat(184), 316, 498] {
        let frames = WorkspaceLayout.frames(
          width: 492, viewportHeight: viewport, overviewHeights: [42, overview])
        let list = frames.last!
        XCTAssertEqual(list.minY, 42 + overview)
        XCTAssertGreaterThanOrEqual(list.height, 340)
        XCTAssertEqual(list.maxY, max(viewport, list.minY + 340))
        XCTAssertEqual(frames[0].maxY, frames[1].minY)
        XCTAssertEqual(frames[1].maxY, list.minY)
      }
    }
    let collapsed = WorkspaceLayout.frames(
      width: 492, viewportHeight: 1000, overviewHeights: [42, 184]
    ).last!
    let expanded = WorkspaceLayout.frames(
      width: 492, viewportHeight: 1000, overviewHeights: [42, 498]
    ).last!
    XCTAssertEqual(collapsed.maxY, expanded.maxY)
    XCTAssertEqual(collapsed.height - expanded.height, 498 - 184)
  }

  func testShortWorkspaceScrollsInsteadOfCrushingProcessList() {
    let list = WorkspaceLayout.frames(
      width: 392, viewportHeight: 358, overviewHeights: [42, 498]
    ).last!
    XCTAssertEqual(list.height, 340)
    XCTAssertGreaterThan(list.maxY, 358)
  }

  func testPriorityColumnsRetainSortAndRespectAvailableColumns() {
    let columns = ["primary", "gpuTime", "cpu", "memory", "pid", "user"].map {
      ProcessColumn(id: $0, title: $0, weight: 1)
    }
    XCTAssertEqual(
      ProcessColumnPolicy.visible(columns, metric: .gpu, width: 392, sort: "primary").map(\.id),
      ["primary", "pid"])
    XCTAssertEqual(
      ProcessColumnPolicy.visible(columns, metric: .gpu, width: 700, sort: "user").map(\.id),
      ["primary", "gpuTime", "cpu", "memory", "pid", "user"])
    XCTAssertFalse(
      ProcessColumnPolicy.visible(
        columns.filter { $0.id != "gpuTime" }, metric: .gpu, width: 700, sort: "primary"
      ).contains { $0.id == "gpuTime" })
  }
  func testChartsSplitUnknownPressureAndSamplingGaps() {
    let points = [(0.0, 1.0), (2, 0), (4, 2), (40, 4)].map {
      Point(date: Date(timeIntervalSince1970: $0.0), a: 20, b: $0.1)
    }
    let samples = TelemetryData.samples(points: points, metric: .memory, maximumGap: 10)
    XCTAssertEqual(samples.map(\.value), [1, 2, 3])
    XCTAssertEqual(samples.map(\.segment), [0, 1, 2])
    XCTAssertEqual(TelemetryData.domain(samples, metric: .memory), 0...3)
  }
  func testBidirectionalChartAndNearestSelection() {
    let points = [
      Point(date: Date(timeIntervalSince1970: 10), a: 0, b: 100),
      Point(date: Date(timeIntervalSince1970: 12), a: 200, b: 0),
    ]
    let samples = TelemetryData.samples(points: points, metric: .network, maximumGap: 10)
    XCTAssertEqual(samples.map(\.value), [0, -100, 200, 0])
    let domain = TelemetryData.domain(samples, metric: .network)
    XCTAssertLessThan(domain.lowerBound, -100)
    XCTAssertGreaterThan(domain.upperBound, 200)
    XCTAssertEqual(
      TelemetryData.nearest(Date(timeIntervalSince1970: 11.9), in: samples), points[1].date)
    XCTAssertNil(TelemetryData.nearest(Date(), in: []))
    XCTAssertEqual(TelemetryData.domain(samples, metric: .cpu, logicalProcessors: 16), 0...1600)
  }
}
