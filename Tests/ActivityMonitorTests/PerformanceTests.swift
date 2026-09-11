import AppKit
import Darwin
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
    value.gpuDevices = [
      GPUDeviceSample(
        id: 1, name: "Fixture GPU", unifiedMemory: true,
        utilization: 42, renderer: 30, tiler: 15, memoryUsed: 512 * 1024 * 1024,
        memoryAllocated: 1024 * 1024 * 1024)
    ]
    value.selectedGPU = 1
    value.gpuHistories[1] = points().map { GPUHistoryPoint(date: $0.date, utilization: $0.a) }
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
    if let selected = ProcessInfo.processInfo.environment["AM_PERFORMANCE_CASE"], selected != name {
      return
    }
    let iterations =
      Int(ProcessInfo.processInfo.environment["AM_PERFORMANCE_ITERATIONS"] ?? "") ?? iterations
    try work()  // Warm framework/font caches; this is not whole-process cold launch latency.
    var milliseconds: [Double] = []
    for _ in 0..<iterations {
      let start = ProcessInfo.processInfo.systemUptime
      try autoreleasepool { try work() }
      milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    report(name, milliseconds: milliseconds)
  }
  private func report(_ name: String, milliseconds: [Double]) {
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
    benchmark("tree.build_filter.all_views.1000") {
      for metric in Metric.allCases {
        var query = ProcessQuery(
          metric: metric, query: "", filter: "All processes",
          sort: metric == .network ? "received" : "primary", descending: true)
        let tree = ProcessTreeSnapshot.build(rows, query: query)
        XCTAssertEqual(tree.visible(collapsed: []).count, 1000)
        query.query = "Renderer) 9"
        let filtered = ProcessTreeSnapshot.build(rows, query: query)
        XCTAssertEqual(filtered.matchingIDs.count, 111)
        XCTAssertEqual(filtered.entries.count, 112)
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
    for metric in Metric.allCases {
      benchmark("chart.\(metric.rawValue).15min", iterations: 3) {
        let view = TelemetryChart(
          samples: metric == .gpu
            ? TelemetryData.gpu(monitor.gpuHistories[1]!, maximumGap: 10)
            : TelemetryData.samples(
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
    let suite = "ActivityMonitor.Performance.Tree.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set("tree", forKey: "processViewMode.v1")
    defer { defaults.removePersistentDomain(forName: suite) }
    benchmark("tree.workspace.1000", iterations: 3) {
      render(
        ContentView().environmentObject(monitor).environmentObject(MonitorNavigation())
          .defaultAppStorage(defaults), size: CGSize(width: 1440, height: 900))
    }
    benchmark("gallery.1000", iterations: 3) {
      render(
        DesignGallery(
          availableSize: CGSize(width: 1440, height: 900), select: { _, _ in }, close: {}
        )
        .environmentObject(monitor), size: CGSize(width: 1080, height: 760))
    }
  }
  @MainActor func testCPUDetailPerformance() throws {
    try enabled()
    let end = PerformanceFixture.end
    let readings = (0..<4096).map {
      CPUReading(id: String($0), title: "Thread \($0)", user: 20, system: 10)
    }
    var history = CPUHistoryStore()
    for i in 0..<40 { history.append(readings, at: end.addingTimeInterval(Double(i))) }
    benchmark("cpu.history.4096") {
      history.append(
        readings, at: (history.series.first?.points.last?.date ?? end).addingTimeInterval(1))
      XCTAssertLessThanOrEqual(
        history.series.reduce(0) { $0 + $1.points.count }, CPUHistoryStore.pointBudget)
    }
    let series = (0..<12).map { index in
      CPUUsageSeries(
        id: String(index), title: "CPU \(index)", detail: "Performance",
        points: (0..<901).map {
          CPUUsagePoint(
            date: end.addingTimeInterval(Double($0 - 900)), user: Double($0 % 60), system: 10)
        })
    }
    benchmark("cpu.grid.12.15min", iterations: 3) {
      render(
        CPUChartBrowser(series: series, range: 15, end: end, theme: .init(dark: true)),
        size: CGSize(width: 960, height: 400))
    }
    let dense = (0..<64).map { index in
      CPUUsageSeries(
        id: String(index), title: "CPU \(index)", detail: "Logical processor",
        points: series[0].points)
    }
    benchmark("cpu.grid.64.15min", iterations: 3) {
      render(
        CPUChartBrowser(series: dense, range: 15, end: end, theme: .init(dark: true)),
        size: CGSize(width: 960, height: 400))
    }
  }
  @MainActor func testMappingChartPerformance() throws {
    try enabled()
    let records = MappingFixture.records(16384)
    benchmark("mapping.aggregate.16384") {
      let data = MappingPlotData.make(
        records: records, images: true, measure: .resident, kind: .protection)
      XCTAssertEqual(data.count, 16384)
      XCTAssertLessThanOrEqual(data.items.count, 9)
    }
    benchmark("mapping.chart.16384", iterations: 3) {
      render(
        MappingVisualization(
          section: .init(records: records), query: "", images: true, theme: .init(dark: true)),
        size: CGSize(width: 800, height: 250))
    }
  }
  @MainActor func testStartupAndSupplementarySurfaces() throws {
    try enabled()
    benchmark("startup.models") {
      let monitor = Monitor(startAutomatically: false)
      let tray = MonitorMenuBarController(monitor: monitor, navigation: MonitorNavigation())
      #if !PERFORMANCE_BASELINE
        XCTAssertFalse(tray.hasPopoverContent)
      #else
        _ = tray
      #endif
    }
    let monitor = PerformanceFixture.monitor()
    benchmark("inspector", iterations: 3) {
      render(
        MonitorInspector(
          process: monitor.rows.first, theme: .init(dark: false), busy: false,
          close: {}, sample: { _ in }, files: { _ in }, reveal: { _ in }, stop: { _ in }),
        size: CGSize(width: 340, height: 600))
    }
    benchmark("popover", iterations: 3) {
      #if PERFORMANCE_BASELINE
        let popover = MenuBarMonitor(openMonitor: {}, closePopover: {})
      #else
        let popover = MenuBarMonitor(
          openMonitor: {}, closePopover: {}, presentation: MenuBarPresentation())
      #endif
      render(
        popover.environmentObject(monitor).environmentObject(MonitorNavigation()),
        size: CGSize(width: 420, height: 690))
    }
  }

  @MainActor func testScrollingAndRefreshBenchmarks() async throws {
    try enabled()
    let suite = "ActivityMonitor.Performance.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let rows = PerformanceFixture.rows(1000)
    let store = HeadlessProcessStore(rows)
    let host = NSHostingView(
      rootView: UpdatingProcessTableHarness(store: store).defaultAppStorage(defaults))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 1000, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    func drain() async {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
          autoreleasepool { host.layoutSubtreeIfNeeded() }
          continuation.resume()
        }
      }
    }
    host.layoutSubtreeIfNeeded()
    await drain()
    await drain()
    func find(_ view: NSView) -> ProcessTableViewport.Anchor? {
      if let anchor = view as? ProcessTableViewport.Anchor { return anchor }
      return view.subviews.lazy.compactMap { find($0) }.first
    }
    let anchor = try XCTUnwrap(find(host))
    let scroll = try XCTUnwrap(anchor.enclosingScrollView)
    let document = try XCTUnwrap(scroll.documentView)
    XCTAssertGreaterThan(document.bounds.height, 40_000)
    var scrollTimes: [Double] = []
    var refreshTimes: [Double] = []
    var initialFootprint: UInt64 = 0
    func footprint() -> UInt64 {
      var value = rusage_info_v4()
      let status = withUnsafeMutablePointer(to: &value) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
      }
      XCTAssertEqual(status, 0)
      return value.ri_phys_footprint
    }
    for iteration in 0..<120 {
      let position = CGFloat(iteration % 40) * 41
      var start = ProcessInfo.processInfo.systemUptime
      scroll.contentView.scroll(to: CGPoint(x: 0, y: position))
      scroll.reflectScrolledClipView(scroll.contentView)
      await drain()
      await drain()
      if iteration >= 40 {
        scrollTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      var updated = rows
      for index in updated.indices { updated[index].cpu += Double(iteration) }
      start = ProcessInfo.processInfo.systemUptime
      store.rows = updated
      await drain()
      await drain()
      if iteration >= 40 {
        refreshTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      if iteration == 39 { initialFootprint = footprint() }
    }
    let endFootprint = footprint()
    let growth = endFootprint > initialFootprint ? endFootprint - initialFootprint : 0
    print(
      "MEMORY {\"name\":\"table.scroll_refresh.1000\",\"growth_bytes\":\(growth),\"start_bytes\":\(initialFootprint),\"end_bytes\":\(endFootprint)}"
    )
    XCTAssertLessThan(
      growth, 64 * 1024 * 1024, "Memory must plateau while scrolling and updating reused rows")
    report("table.scroll.layout.1000", milliseconds: scrollTimes)
    report("table.refresh.layout.1000", milliseconds: refreshTimes)
  }
  #if !PERFORMANCE_BASELINE
    @MainActor func testProcessDiagnosticsSurfaces() throws {
      try enabled()
      let monitor = PerformanceFixture.monitor()
      var row = monitor.rows[0]
      let session = ProcessDiagnosticSession(row: row)
      session.tab = .cpu
      for index in 0...900 {
        row.cpu = 150 + sin(Double(index) / 20) * 60
        session.accept(
          rows: [row], date: PerformanceFixture.end.addingTimeInterval(Double(index - 900)))
      }
      session.range = 15
      benchmark("diagnostics.workspace.15min", iterations: 3) {
        render(
          ProcessDiagnosticsView(
            session: session, center: monitor.diagnostics, persistTableColumns: false, close: {}),
          size: CGSize(width: 1060, height: 740))
      }
      let records = (0..<2500).map {
        DiagnosticRecord(
          id: String($0),
          cells: [
            "FD": String($0), "Type": "File",
            "Path": "/Applications/Example.app/Contents/Resources/document-\($0).json",
            "Size": "128 KB", "Access": "Available",
          ], numbers: ["FD": Double($0)])
      }
      let section = DiagnosticSection(
        columns: ["FD", "Type", "Path", "Size", "Access"], records: records, status: "2500 entries",
        date: PerformanceFixture.end)
      benchmark("diagnostics.table.2500", iterations: 3) {
        render(
          DiagnosticTable(
            section: section, query: "", key: "benchmark", theme: .init(dark: false),
            persistColumns: false), size: CGSize(width: 900, height: 550))
      }
    }
  #endif
  @MainActor private var renderIndex = 0
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
    if let directory = ProcessInfo.processInfo.environment["AM_RENDER_DIR"] {
      try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try? bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("render-\(renderIndex).png"))
      renderIndex += 1
    }
  }
}
