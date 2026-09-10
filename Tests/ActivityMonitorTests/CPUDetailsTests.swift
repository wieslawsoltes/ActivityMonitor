import AppKit
import SwiftUI
import SystemBridge
import XCTest

@testable import ActivityMonitor

final class CPUDetailsTests: XCTestCase {
  func testGridFitsProcessorCountAndViewportWithoutPagination() {
    for (count, size) in [
      (1, CGSize(width: 360, height: 200)), (16, CGSize(width: 360, height: 240)),
      (11, CGSize(width: 1200, height: 240)), (64, CGSize(width: 800, height: 300)),
      (67, CGSize(width: 800, height: 260)), (128, CGSize(width: 1200, height: 600)),
    ] {
      let layout = CPUGridLayout(count: count, size: size)
      XCTAssertFalse(layout.scrolls, "All \(count) charts should fit")
      XCTAssertGreaterThanOrEqual(layout.columns * layout.rows, count)
      XCTAssertLessThanOrEqual(
        CGFloat(layout.rows) * layout.tileHeight + CGFloat(layout.rows - 1) * layout.spacing,
        size.height)
      XCTAssertLessThanOrEqual(
        CGFloat(layout.columns) * layout.tileWidth + CGFloat(layout.columns - 1) * layout.spacing,
        size.width)
      XCTAssertGreaterThanOrEqual(layout.tileHeight, 38)
    }
    let dense = CPUGridLayout(count: 64, size: .init(width: 800, height: 300))
    let filtered = CPUGridLayout(count: 4, size: .init(width: 800, height: 300))
    XCTAssertGreaterThan(
      filtered.tileWidth * filtered.tileHeight, dense.tileWidth * dense.tileHeight)
    let huge = CPUGridLayout(count: 4096, size: .init(width: 360, height: 240))
    XCTAssertTrue(huge.scrolls)
    XCTAssertGreaterThanOrEqual(huge.tileWidth, 60)
    XCTAssertGreaterThanOrEqual(huge.tileHeight, 38)
  }
  func testPerProcessorRatesIncludeNiceWrapAndKeepIndependentBaselines() {
    var tracker = CPUCoreTracker()
    var a = AMCPUTicks()
    a.slot = 0
    a.identified = 1
    a.user = UInt32.max - 9
    var b = AMCPUTicks()
    b.slot = 4
    b.identified = 1
    let topology = CPUTopology(
      physical: 2, logical: 2, coreTypes: [0: "Efficiency", 4: "Performance"])
    XCTAssertTrue(tracker.sample([a, b], topology: topology).allSatisfy { $0.user == nil })
    a.user = 10
    a.system = 10
    a.idle = 10
    a.nice = 10
    b.user = 10
    b.system = 10
    b.idle = 80
    let values = tracker.sample([a, b], topology: topology)
    XCTAssertEqual(values[0].user, 60)
    XCTAssertEqual(values[0].system, 20)
    XCTAssertEqual(values[1].user, 10)
    XCTAssertEqual(values[1].system, 10)
    XCTAssertEqual(values[0].detail, "Efficiency")
    XCTAssertEqual(values[1].detail, "Performance")
    XCTAssertNil(
      tracker.sample([a], topology: topology)[0].user, "No advancing ticks is unavailable, not zero"
    )
    XCTAssertNil(
      tracker.sample([a, b], topology: topology)[1].user, "Reappearing processors need a baseline")
    a.identified = 0
    XCTAssertEqual(tracker.sample([a], topology: topology)[0].detail, "Logical processor")
  }
  func testThreadRatesRejectNewMissingResetAndLongGapCounters() {
    var tracker = ThreadCPUTracker()
    let counter = ThreadCPUCounter(
      id: 42, name: "Worker", user: 1_000_000_000, system: 1_000_000_000)
    XCTAssertNil(tracker.sample(.init(counters: [counter], uptime: 10))[0].user)
    var next = counter
    next.user = 2_000_000_000
    next.system = 1_500_000_000
    let reading = tracker.sample(.init(counters: [next], uptime: 12))[0]
    XCTAssertEqual(reading.user, 50)
    XCTAssertEqual(reading.system, 25)
    XCTAssertEqual(reading.title, "Thread 42")
    XCTAssertNil(tracker.sample(.init(counters: [counter], uptime: 14))[0].user)
    next.user = nil
    XCTAssertNil(tracker.sample(.init(counters: [next], uptime: 16))[0].system)
    XCTAssertNil(tracker.sample(.init(counters: [counter], uptime: 18))[0].user)
    XCTAssertNil(tracker.sample(.init(counters: [counter], uptime: 100))[0].user)
    tracker.reset()
    XCTAssertNil(tracker.sample(.init(counters: [counter], uptime: 101))[0].user)
    XCTAssertEqual(tracker.sample(.init(counters: [counter, counter], uptime: 102)).count, 1)
  }
  func testHistoryBoundsGapsAndRetiredThreads() {
    let date = Date()
    let points = (0..<900).map {
      CPUUsagePoint(date: date.addingTimeInterval(Double($0 - 900)), user: 30, system: 10)
    }
    var history = CPUHistoryStore(
      series: (0..<200).map { .init(id: String($0), title: "Worker", detail: "", points: points) })
    let readings = (0..<200).map {
      CPUReading(id: String($0), title: "Worker", user: 50, system: 20)
    }
    history.append(readings, at: date)
    XCTAssertLessThanOrEqual(
      history.series.reduce(0) { $0 + $1.points.count }, CPUHistoryStore.pointBudget)
    history.unavailable(at: date.addingTimeInterval(2))
    XCTAssertTrue(history.series.allSatisfy { $0.latest == nil })
    history.append([readings[0]], at: date.addingTimeInterval(4))
    XCTAssertEqual(history.series.count, 1)
    let samples = CPUChartData.samples(history.series[0], since: date.addingTimeInterval(-10))
    XCTAssertEqual(Set(samples.map(\.segment)).count, 2)
    history.append([readings[0]], at: date.addingTimeInterval(1000))
    XCTAssertEqual(history.series[0].points.count, 1)
    XCTAssertEqual(CPUChartData.maximum(history.series[0], since: date, threads: false), 100)
  }
  func testLiveProcessorTopologyAndMachBufferBounds() throws {
    let topology = CPUTopology.current
    XCTAssertGreaterThan(try XCTUnwrap(topology.physical), 0)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(topology.logical), topology.physical!)
    var ticks = [AMCPUTicks](repeating: AMCPUTicks(), count: 4096)
    var count: Int32 = 0
    var truncated: Int32 = 0
    XCTAssertEqual(am_cpu_ticks(&ticks, 4096, &count, &truncated), 0)
    XCTAssertGreaterThan(count, 0)
    XCTAssertEqual(truncated, 0)
    XCTAssertEqual(Set(ticks.prefix(Int(count)).map(\.slot)).count, Int(count))
    XCTAssertEqual(am_cpu_ticks(&ticks, 1, &count, &truncated), 0)
    XCTAssertEqual(count, 1)
    if topology.logical! > 1 { XCTAssertEqual(truncated, 1) }
    XCTAssertNotEqual(am_cpu_ticks(&ticks, 0, &count, &truncated), 0)
    XCTAssertEqual(count, 0)
    XCTAssertTrue(
      topology.coreTypes.values.allSatisfy { ["Performance", "Efficiency"].contains($0) })
  }
  @MainActor func testThreadSamplingIsOptInAndHonorsPauseAndDefaultSingleChart() async throws {
    let row = PerformanceFixture.rows(1)[0]
    let session = ProcessDiagnosticSession(
      row: row,
      threadReader: { _ in
        .init(counters: [.init(id: 1, name: "Worker", user: 0, system: 0)])
      })
    XCTAssertFalse(session.showsThreadCPU)
    session.refreshThreadActivity(force: true)
    XCTAssertFalse(session.collectingThreadCPU)
    XCTAssertTrue(session.threadCPU.isEmpty)
    session.paused = true
    session.showsThreadCPU = true
    XCTAssertFalse(session.collectingThreadCPU)
    session.paused = false
    session.refreshThreadActivity(force: true)
    for _ in 0..<100 {
      if !session.collectingThreadCPU { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(session.threadCPU.count, 1)
    session.showsThreadCPU = false
    XCTAssertFalse(session.collectingThreadCPU)
  }
  @MainActor func testProcessorAndThreadViewsRenderAtNarrowAndWideSizesInBothThemes() throws {
    let now = Date()
    let series: [CPUUsageSeries] = (0..<32).map { index in
      .init(
        id: String(index), title: "CPU \(index)", detail: index < 16 ? "Performance" : "Efficiency",
        points: (0..<61).map {
          .init(date: now.addingTimeInterval(Double($0 - 60)), user: Double($0), system: 10)
        })
    }
    for dark in [false, true] {
      for width in [CGFloat(360), CGFloat(1060)] {
        let host = NSHostingView(
          rootView: CPUChartBrowser(
            series: series, range: 1, end: now, theme: .init(dark: dark), threads: dark))
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: width, height: 350), styleMask: [.borderless],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: 350)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertEqual(host.bounds.width, width, accuracy: 1)
        window.contentView = nil
        window.close()
      }
    }
  }
}
