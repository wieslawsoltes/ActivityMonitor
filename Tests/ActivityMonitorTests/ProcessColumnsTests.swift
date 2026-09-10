import Darwin
import SystemBridge
import XCTest

@testable import ActivityMonitor

final class ProcessColumnsTests: XCTestCase {
  func testEveryPerspectiveOffersNativeCatalogWithoutDuplicatesAndPreservesDefaults() {
    for metric in Metric.allCases {
      let all = ProcessColumns.available(metric)
      XCTAssertEqual(all.count, 28)
      XCTAssertEqual(
        Set(all.map { ProcessColumns.canonical($0.id, metric: metric) }),
        Set(ProcessColumns.catalog.map(\.id)))
      let preferences = ProcessColumnPreferences()
      XCTAssertEqual(
        all.filter { preferences.isVisible($0.id, metric: metric) }, ProcessColumns.defaults(metric)
      )
      XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }
    XCTAssertEqual(
      ProcessColumns.defaults(.cpu).map(\.id),
      ["primary", "time", "threads", "memory", "kind", "gpu", "pid", "user"])
    XCTAssertEqual(
      ProcessColumns.defaults(.energy).map(\.id), ["primary", "time", "nap", "sleep", "user"])
  }
  func testColumnChoicesPersistPerViewAndRestoreOnlyThatView() {
    var prefs = ProcessColumnPreferences()
    XCTAssertFalse(prefs.isVisible("compressed", metric: .cpu))
    prefs.set("compressed", metric: .cpu, visible: true)
    prefs.set("compressed", metric: .disk, visible: true)
    prefs.set("threads", metric: .cpu, visible: false)
    prefs = ProcessColumnPreferences(prefs.json)
    XCTAssertTrue(prefs.isVisible("compressed", metric: .cpu))
    XCTAssertFalse(prefs.isVisible("compressed", metric: .network))
    XCTAssertFalse(prefs.isVisible("threads", metric: .cpu))
    prefs.restore(.cpu)
    XCTAssertFalse(prefs.isVisible("compressed", metric: .cpu))
    XCTAssertTrue(prefs.explicitlyEnabled(.cpu).isEmpty)
    XCTAssertTrue(prefs.isVisible("compressed", metric: .disk))
    XCTAssertTrue(prefs.isVisible("threads", metric: .cpu))
    XCTAssertFalse(ProcessColumnPreferences().isVisible("time", metric: .cpu, showTime: false))
    XCTAssertFalse(ProcessColumnPreferences("invalid json").isVisible("compressed", metric: .cpu))
  }
  func testLocalizedProcessNamesKeepExecutableFallback() {
    XCTAssertEqual(
      ProcessDisplayName.resolve(executable: "prl_vm_app", application: "Windows 11"), "Windows 11")
    XCTAssertEqual(
      ProcessDisplayName.resolve(executable: "prl_vm_app", application: "Ubuntu 24.04.3 ARM64"),
      "Ubuntu 24.04.3 ARM64")
    XCTAssertEqual(ProcessDisplayName.resolve(executable: "helper", application: ""), "helper")
    XCTAssertEqual(ProcessDisplayName.resolve(executable: "helper", application: nil), "helper")
  }
  func testPacketParserUsesHeaderOrderAndPreservesMissingCounters() {
    let data = parseProcessNetwork(
      ",packets_in,bytes_in,packets_out,bytes_out,\nname,with.dots.42,3,4096,7,8192,\n")
    XCTAssertEqual(data[42]?.received, 4096)
    XCTAssertEqual(data[42]?.sent, 8192)
    XCTAssertEqual(data[42]?.packetsIn, 3)
    XCTAssertEqual(data[42]?.packetsOut, 7)
    XCTAssertNil(parseProcessNetwork(",bytes_out,bytes_in,\nname.42,9,8,\n")[42]?.packetsIn)
    XCTAssertEqual(parseProcessNetwork(",bytes_out,bytes_in,\nname.42,9,8,\n")[42]?.sent, 9)
  }
  func testPortsParserIgnoresSummaryAndMalformedRows() {
    XCTAssertEqual(
      parseProcessPorts("Processes: 123 total\nPID #PORTS\n42 197\n43 ?\n44 0\n"), [42: 197, 44: 0])
  }
  func testWakeupsAreRatesAndRejectPIDReuseAndCounterReset() {
    var old = AMProcess()
    old.start = 1
    old.ioAccessible = 1
    old.wakeups = 100
    var current = old
    current.wakeups = 140
    XCTAssertEqual(ProcessDetails.wakeupRate(current: current, previous: old, elapsed: 2), 20)
    current.start = 2
    XCTAssertNil(ProcessDetails.wakeupRate(current: current, previous: old, elapsed: 2))
    current = old
    current.wakeups = 99
    XCTAssertNil(ProcessDetails.wakeupRate(current: current, previous: old, elapsed: 2))
    XCTAssertNil(ProcessDetails.wakeupRate(current: old, previous: old, elapsed: 0))
  }
  func testMemoryAccountingDeduplicatesSharedObjectsAndCountsPrivateCOWPages() {
    let result = ProcessMemoryRegions.totals(
      [
        .init(object: 1, mode: UInt32(SM_PRIVATE), references: 1, privatePages: 10, sharedPages: 2),
        .init(object: 2, mode: UInt32(SM_COW), references: 3, privatePages: 4, sharedPages: 20),
        .init(object: 2, mode: UInt32(SM_COW), references: 3, privatePages: 1, sharedPages: 20),
        .init(object: 3, mode: UInt32(SM_SHARED), references: 2, privatePages: 0, sharedPages: 5),
        .init(object: 3, mode: UInt32(SM_SHARED), references: 2, privatePages: 0, sharedPages: 5),
      ], pageSize: 4096)
    XCTAssertEqual(result.privateBytes, 22 * 4096)
    XCTAssertEqual(result.sharedBytes, 20 * 4096)
  }
  func testAssertionsIgnoreInactiveAndUnrelatedAssertions() {
    XCTAssertTrue(
      assertionPreventsSleep(["AssertLevel": 255, "AssertType": "PreventUserIdleSystemSleep"]))
    XCTAssertFalse(
      assertionPreventsSleep(["AssertLevel": 0, "AssertType": "PreventUserIdleSystemSleep"]))
    XCTAssertFalse(assertionPreventsSleep(["AssertLevel": 255, "AssertType": "BackgroundTask"]))
    XCTAssertFalse(assertionPreventsSleep([:]))
  }
  func testAllColumnSortingUsesCorrectValuesAndPutsUnknownLast() throws {
    var a = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    a.id = 1
    a.cpu = 90
    a.name = "Windows 11"
    a.executableName = "prl_vm_app"
    a.details.ports = 2
    a.details.packetsOut = 2
    a.details.compressed = 2
    a.details.preventingSleep = false
    var b = a
    b.id = 2
    b.cpu = 10
    b.details.ports = 10
    b.details.packetsOut = 10
    b.details.compressed = 10
    b.details.preventingSleep = true
    var c = a
    c.id = 3
    c.details = ProcessDetails()
    for key in ["ports", "packetsOut", "compressed", "sleep"] {
      for metric in Metric.allCases {
        XCTAssertEqual(
          ProcessQuery(
            metric: metric, query: "", filter: "All processes", sort: key, descending: false
          ).apply([c, b, a]).map(\.id), [1, 2, 3])
        XCTAssertEqual(
          ProcessQuery(
            metric: metric, query: "", filter: "All processes", sort: key, descending: true
          ).apply([a, c, b]).map(\.id), [2, 1, 3])
      }
    }
    XCTAssertEqual(
      ProcessQuery(
        metric: .cpu, query: "prl_vm_app", filter: "All processes", sort: "name", descending: false
      ).apply([a]).count, 1)
    XCTAssertEqual(ProcessValues.text(c, key: "compressed", metric: .cpu), "—")
    XCTAssertEqual(ProcessValues.text(b, key: "sleep", metric: .cpu), "Yes")
    XCTAssertEqual(ProcessValues.text(a, key: "sleep", metric: .cpu), "No")
    XCTAssertEqual(ProcessValues.text(a, key: "energyImpact", metric: .energy), "—")
  }
  func testRegionCollectionForCurrentProcessAndInvalidPID() {
    XCTAssertNotNil(ProcessMemoryRegions.read(pid: getpid(), translated: false))
    XCTAssertNil(ProcessMemoryRegions.read(pid: Int32.max, translated: false))
  }
  func testTaskNameMemoryStatisticsForCurrentProcess() {
    var memory = AMMemoryDetails()
    am_memory_details(getpid(), &memory)
    XCTAssertEqual(memory.vmAccessible, 1)
  }
}

extension ProcessColumnsTests {
  func testKeyboardRevealPreservesHorizontalScrollAndPinnedHeader() {
    let visible = CGRect(x: 640, y: 400, width: 800, height: 300)
    XCTAssertEqual(
      ProcessTableGeometry.originToReveal(row: 12, visible: visible, contentHeight: 5000),
      visible.origin)
    XCTAssertEqual(
      ProcessTableGeometry.originToReveal(row: 0, visible: visible, contentHeight: 5000),
      CGPoint(x: 640, y: 0))
    let lower = ProcessTableGeometry.originToReveal(row: 30, visible: visible, contentHeight: 5000)
    XCTAssertEqual(lower.x, 640)
    XCTAssertEqual(lower.y + visible.height, 37 + 31 * 41)
  }
}
