import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

final class PerformanceCorrectnessTests: XCTestCase {
  @MainActor func testFirstLiveSnapshotHasProcessesWithinStartupBudget() async {
    let start = ProcessInfo.processInfo.systemUptime
    let monitor = Monitor(startAutomatically: false)
    await monitor.refresh()
    XCTAssertNotNil(monitor.lastUpdate)
    XCTAssertFalse(monitor.rows.isEmpty)
    XCTAssertGreaterThan(monitor.system.physical, 0)
    XCTAssertLessThan(
      ProcessInfo.processInfo.systemUptime - start, 2,
      "First telemetry must not wait for slow external collectors")
  }
  @MainActor func testCachedIconsRetainOnlyOneRetinaSizedRepresentation() {
    let source = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
      NSColor.systemBlue.setFill()
      rect.fill()
      return true
    }
    let result = ProcessIconCache.thumbnail(source)
    XCTAssertEqual(result.representations.count, 1)
    XCTAssertEqual(result.representations.first?.pixelsWide, 128)
    XCTAssertEqual(result.representations.first?.pixelsHigh, 128)
    XCTAssertEqual(result.size.width, 64)
    let bitmap = result.representations.first as? NSBitmapImageRep
    XCTAssertGreaterThan(bitmap?.colorAt(x: 64, y: 64)?.alphaComponent ?? 0, 0.9)
  }
  func testRenderingCachesAreBoundedAndDoNotShareMutablePreferences() {
    let cache = BoundedCache<Int, String>(capacity: 32)
    DispatchQueue.concurrentPerform(iterations: 2000) { index in
      XCTAssertEqual(cache.value(for: index) { String(index) }, String(index))
    }
    XCTAssertLessThanOrEqual(cache.count, 32)
    var first = ProcessColumnWidths()
    first.set("name", metric: .cpu, width: 600)
    XCTAssertNil(ProcessColumnWidths().width("name", metric: .cpu))
    let json = first.json
    var second = ProcessColumnWidths(json)
    second.set("name", metric: .cpu, width: 900)
    XCTAssertEqual(ProcessColumnWidths(json).width("name", metric: .cpu), 600)
  }
  func testLimitedQueriesMatchFullSortingForEveryColumnFilterAndDirection() {
    let rows = PerformanceFixture.rows(1000).reversed()
    for metric in Metric.allCases {
      for column in ProcessColumns.available(metric) {
        for descending in [true, false] {
          for filter in ["All processes", "Applications", "GPU processes"] {
            let query = ProcessQuery(
              metric: metric, query: "", filter: filter,
              sort: column.id, descending: descending)
            let full = query.apply(Array(rows))
            for limit in [0, 3, 5] {
              XCTAssertEqual(query.apply(Array(rows), limit: limit), Array(full.prefix(limit)))
            }
          }
        }
      }
    }
  }
  func testExactChartPathsPreserveEveryPointGapAndMemoryStep() {
    let end = PerformanceFixture.end
    let samples = [
      TelemetrySample(date: end.addingTimeInterval(-10), value: 0, series: 0, segment: 0),
      TelemetrySample(date: end.addingTimeInterval(-5), value: 100, series: 0, segment: 0),
      TelemetrySample(date: end.addingTimeInterval(-5), value: -50, series: 1, segment: 0),
      TelemetrySample(date: end, value: 20, series: 0, segment: 1),
    ]
    let traces = TelemetryTrace.make(samples)
    XCTAssertEqual(traces.count, 3)
    XCTAssertEqual(traces.flatMap(\.samples).count, samples.count)
    let size = CGSize(width: 100, height: 200)
    let coordinates = traces[0].coordinates(
      size: size, start: end.addingTimeInterval(-10),
      end: end, domain: -100...100, stepped: false)
    XCTAssertEqual(coordinates, [CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 0)])
    let steps = traces[0].coordinates(
      size: size, start: end.addingTimeInterval(-10),
      end: end, domain: -100...100, stepped: true)
    XCTAssertEqual(steps, [CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 100), CGPoint(x: 50, y: 0)])
    let descriptor = TelemetryAccessibility(
      traces: traces, title: "CPU", start: end.addingTimeInterval(-10),
      end: end, domain: -100...100, label: { "Series \($0.series)" }, value: { String($0) }
    ).makeChartDescriptor()
    XCTAssertEqual(descriptor.series.count, 3)
    XCTAssertEqual(descriptor.series.reduce(0) { $0 + $1.dataPoints.count }, samples.count)
  }
  @MainActor func testViewportCoordinatesMatchTopOriginAtBothScrollExtremes() {
    final class Document: NSView { override var isFlipped: Bool { true } }
    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
    let document = Document(frame: CGRect(x: 0, y: 0, width: 800, height: 41_037))
    let anchor = ProcessTableViewport.Anchor(frame: document.bounds)
    document.addSubview(anchor)
    scroll.documentView = document
    for y: CGFloat in [0, 20_000, 40_637] {
      scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
      let visible = anchor.convert(scroll.documentVisibleRect, from: document)
      XCTAssertEqual(visible.minY, y, accuracy: 0.1)
      let range = ProcessVisibleRows.range(count: 1000, viewport: visible)
      XCTAssertTrue(range.contains(min(999, max(0, Int((y - 37) / 41)))))
    }
  }
  func testVirtualRowsCoverViewportWithBoundedOverscan() {
    for count in [0, 1, 30, 1000, 100_000] {
      for height: CGFloat in [1, 240, 480, 900, 1600] {
        let content = CGFloat(count) * 41 + 37
        for y in stride(
          from: CGFloat(0), through: max(0, content - height), by: max(41, content / 19))
        {
          let rect = CGRect(x: 500, y: y, width: 400, height: height)
          let range = ProcessVisibleRows.range(count: count, viewport: rect)
          XCTAssertGreaterThanOrEqual(range.lowerBound, 0)
          XCTAssertLessThanOrEqual(range.upperBound, count)
          XCTAssertLessThanOrEqual(range.count, Int(ceil(height / 41)) + 5)
          if count > 0 {
            XCTAssertLessThanOrEqual(CGFloat(range.lowerBound) * 41 + 37, max(37, y))
            XCTAssertGreaterThanOrEqual(
              CGFloat(range.upperBound) * 41 + 37, min(content, rect.maxY))
          }
        }
      }
    }
  }
  func testVirtualRowsHandleShrinkingFiltersAndJumpToEnd() {
    let rect = CGRect(x: 0, y: 40_000, width: 800, height: 600)
    XCTAssertTrue(ProcessVisibleRows.range(count: 10, viewport: rect).isEmpty)
    let end = ProcessTableGeometry.originToReveal(
      row: 999,
      visible: CGRect(x: 73, y: 0, width: 500, height: 600), contentHeight: 41_037)
    let rows = ProcessVisibleRows.range(
      count: 1000,
      viewport: CGRect(origin: end, size: CGSize(width: 500, height: 600)))
    XCTAssertTrue(rows.contains(999))
    XCTAssertEqual(end.x, 73)
  }
  func testByteFormatterPreservesSignedAndUnsignedRangesAcrossThreads() {
    let values: [UInt64] = [
      0, 1, 1023, 1024, 1_048_575, 1_048_576, 1_073_741_823, UInt64(Int64.max),
    ]
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
      for value in values {
        XCTAssertEqual(
          bytes(value),
          ByteCountFormatter.string(
            fromByteCount: Int64(clamping: value), countStyle: .memory))
      }
      XCTAssertEqual(bytes(1 << 63), "8.0 EiB")
      XCTAssertEqual(bytes(UInt64.max), "16.0 EiB")
    }
  }
  @MainActor func testUnusedMenuBarDoesNotConstructHiddenContent() {
    let monitor = Monitor(startAutomatically: false)
    let controller = MonitorMenuBarController(monitor: monitor, navigation: MonitorNavigation())
    XCTAssertFalse(controller.hasPopoverContent)
    controller.setEnabled(false)
    monitor.rows = PerformanceFixture.rows(1000)
    XCTAssertFalse(controller.hasPopoverContent)
  }
  @MainActor func testProcessIconCachePrunesExitedAndReusedProcesses() {
    _ = ProcessIconCache.icon(pid: 100_001, start: 1, isApp: false)
    _ = ProcessIconCache.icon(pid: 100_002, start: 2, isApp: false)
    ProcessIconCache.retain(identities: [100_001: 3, 100_002: 2])
    XCTAssertEqual(ProcessIconCache.retainedProcessCount, 1)
    ProcessIconCache.retain(identities: [:])
    XCTAssertEqual(ProcessIconCache.retainedProcessCount, 0)
    for index in 0..<600 {
      _ = ProcessIconCache.icon(pid: Int32(101_000 + index), start: UInt64(index + 1), isApp: false)
    }
    XCTAssertLessThanOrEqual(ProcessIconCache.retainedProcessCount, 128)
  }
  @MainActor func testMonitorCanDeallocateWhileSamplerSleeps() async {
    weak var released: Monitor?
    do {
      let monitor = Monitor()
      monitor.paused = true
      released = monitor
      // Allow the repeating task to enter its sleep before releasing the owner.
      await Task.yield()
    }
    await Task.yield()
    XCTAssertNil(released)
  }
  func testNetworkSamplingIsNonblockingSingleFlightAndIdentitySafe() {
    let entered = expectation(description: "network reader starts")
    let release = DispatchSemaphore(value: 0)
    let completed = expectation(description: "network reader finishes")
    let lock = NSLock()
    var calls = 0
    let sampler = ProcessNetworkSampler(
      read: {
        lock.withLock { calls += 1 }
        entered.fulfill()
        _ = release.wait(timeout: .now() + 5)
        return [42: ProcessNetworkCounters(received: 10, sent: 20)]
      },
      identity: { _ in
        completed.fulfill()
        return 100
      })
    let now = Date()
    XCTAssertTrue(sampler.collect(identities: [42: 100], now: now).isEmpty)
    wait(for: [entered], timeout: 2)
    for _ in 0..<50 {
      XCTAssertTrue(sampler.collect(identities: [42: 100], now: now.addingTimeInterval(30)).isEmpty)
    }
    XCTAssertEqual(lock.withLock { calls }, 1)
    release.signal()
    wait(for: [completed], timeout: 2)
    // The completion callback runs immediately before publishing the cache.
    let deadline = Date().addingTimeInterval(1)
    var result: [Int32: ProcessNetworkCounters] = [:]
    while result.isEmpty && Date() < deadline {
      result = sampler.collect(identities: [42: 100], now: now)
      Thread.sleep(forTimeInterval: 0.001)
    }
    XCTAssertEqual(result[42]?.received, 10)
    XCTAssertTrue(sampler.collect(identities: [42: 101], now: now).isEmpty)
    XCTAssertTrue(sampler.collect(identities: [:], now: now).isEmpty)
  }
}
