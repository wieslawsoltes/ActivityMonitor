import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

/// Deterministic fixtures: no running-process probes, network tools or user preferences.
enum PerformanceFixture {
  static let end = Date(timeIntervalSince1970: 1_700_000_900)
  static func rows(_ count: Int) -> [ProcessRow] {
    (0..<count).map { i -> ProcessRow in
      var row = ProcessRow(
        id: Int32(100_000 + i), parent: 100_000,
        uid: 501, start: UInt64(i + 1), name: "Example Application Helper (Renderer) \(i)",
        user: "example", cpu: 0, cpuTime: 0, memory: 0, resident: 0,
        threads: 1, read: 0, written: 0, isApp: false, accessible: true,
        kind: "Apple", ioAccessible: true)
      row.parent = i == 0 ? 0 : 100_000
      row.cpu = Double((i * 37) % 900)
      row.cpuTime = Double(i * 13)
      row.memory = UInt64(i + 1) * 1_000_000
      row.resident = row.memory / 2
      row.threads = UInt32(i % 80 + 1)
      row.read = UInt64(i * 100)
      row.written = UInt64(i * 200)
      row.isApp = i % 5 == 0
      row.accessible = i % 7 != 0
      row.networkReceived = UInt64(i * 300)
      row.networkSent = UInt64(i * 400)
      row.gpuPercent = i % 3 == 0 ? Double(i % 100) : nil
      return row
    }
  }

  static func points(_ count: Int = 901, memory: Bool = false) -> [Point] {
    (0..<count).map { i in
      Point(
        date: end.addingTimeInterval(Double(i - count + 1)),
        a: Double(i % 61), b: memory ? [1.0, 2, 4][i / 100 % 3] : Double(i % 29))
    }
  }
  @MainActor static func monitor() -> Monitor {
    let value = Monitor(startAutomatically: false)
    value.rows = rows(1000)
    value.system.physical = 18 * 1024 * 1024 * 1024
    value.system.active = 4 * 1024 * 1024 * 1024
    value.system.pressure = 1
    value.lastUpdate = end
    for metric in Metric.allCases { value.histories[metric] = points(memory: metric == .memory) }
    return value
  }
}

final class PerformanceTests: XCTestCase {
  private func enabled() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["AM_PERFORMANCE"] == "1",
      "Run scripts/performance.sh for release-mode performance gates")
  }
  private func benchmark(_ name: String, iterations: Int = 7, _ work: () throws -> Void) rethrows {
    try work()  // Warm framework/font caches; cold startup is measured separately.
    var milliseconds: [Double] = []
    for _ in 0..<iterations {
      let start = ProcessInfo.processInfo.systemUptime
      try autoreleasepool { try work() }
      milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    let sorted = milliseconds.sorted()
    let result: [String: Any] = [
      "name": name, "median_ms": sorted[sorted.count / 2],
      "max_ms": sorted.last!, "samples_ms": milliseconds,
    ]
    let json = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print("PERF " + String(decoding: json, as: UTF8.self))
  }
  func testQueryAndFormattingBenchmarks() throws {
    try enabled()
    let rows = PerformanceFixture.rows(1000)
    benchmark("query.all_views.1000") {
      for metric in Metric.allCases {
        let result = ProcessQuery(
          metric: metric, query: "", filter: "All processes",
          sort: metric == .network ? "received" : "primary", descending: true
        ).apply(rows)
        XCTAssertEqual(result.count, 1000)
      }
    }
    benchmark("format.all_columns.1000") {
      for row in rows {
        for column in ProcessColumns.available(.cpu) {
          XCTAssertFalse(ProcessValues.text(row, key: column.id, metric: .cpu).isEmpty)
        }
      }
    }
  }
  @MainActor func testHeadlessRenderBenchmarks() throws {
    try enabled()
    let monitor = PerformanceFixture.monitor()
    for metric in [Metric.cpu, .memory, .network] {
      benchmark("chart.\(metric.rawValue).15min", iterations: 3) {
        let view = TelemetryChart(
          samples: TelemetryData.samples(
            points: monitor.histories[metric]!, metric: metric, maximumGap: 10),
          metric: metric, range: 15, end: PerformanceFixture.end, theme: .init(dark: false))
        render(view, size: CGSize(width: 720, height: 160))
      }
    }
    benchmark("workspace.1000", iterations: 3) {
      render(
        ContentView().environmentObject(monitor).environmentObject(MonitorNavigation()),
        size: CGSize(width: 1440, height: 900))
    }
    benchmark("gallery.1000", iterations: 3) {
      render(
        DesignGallery(
          availableSize: CGSize(width: 1440, height: 900), select: { _, _ in }, close: {}
        )
        .environmentObject(monitor), size: CGSize(width: 1080, height: 760))
    }
  }
  @MainActor private func render<V: View>(_ view: V, size: CGSize) {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      XCTFail("Cannot create headless bitmap")
      return
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertGreaterThan(bitmap.pixelsWide, 0)
  }
}
