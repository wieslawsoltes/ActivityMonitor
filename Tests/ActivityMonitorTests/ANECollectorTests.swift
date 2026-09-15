import Foundation
import XCTest
@testable import ActivityMonitor

final class ANECollectorTests: XCTestCase {
  func testHardwarePropertiesRemainOptionalAndValidated() {
    XCTAssertEqual(ANERegistryParser.deviceCount(
      ["DeviceProperties": ["ANEDevicePropertyNumANECores": 16]],
      key: "ANEDevicePropertyNumANECores"), 16)
    XCTAssertNil(ANERegistryParser.deviceCount([:], key: "ANEDevicePropertyNumANECores"))
    for invalid: Any in [-1, 0, 1.5, true, "16", 1025] {
      XCTAssertNil(ANERegistryParser.positiveCount(invalid))
    }
  }
  func testOnlyDirectPathClientsCanBeAttributedToProcesses() {
    let direct: [String: Any] = [
      "IOUserClientCreator": "pid 1207, Example Process",
    ]
    XCTAssertEqual(ANERegistryParser.directClientPID(
      className: "H1xANELoadBalancerDirectPathClient", properties: direct), 1207)
    XCTAssertNil(ANERegistryParser.directClientPID(className: "H1xANELoadBalancerClient", properties: [
      "IOUserClientCreator": "pid 453, aned",
    ]))
    XCTAssertNil(ANERegistryParser.directClientPID(className: "H1xANELoadBalancerDirectPathClient", properties: [
      "IOUserClientCreator": "pid -1, stale",
    ]))
    XCTAssertNil(ANERegistryParser.directClientPID(className: "H1xANELoadBalancerDirectPathClient", properties: [
      "IOUserClientCreator": "unparseable",
    ]))
  }
  func testUnreadableConnectionsAreNotReportedAsZero() {
    let unavailable = ANEHardwareSnapshot(
      available: false, engineCount: nil, coreCount: nil, connections: [:])
    XCTAssertNil(unavailable.connectionCount)
    XCTAssertNil(unavailable.processCount)
    var readable = unavailable
    readable.available = true
    readable.connectionsReadable = true
    XCTAssertEqual(readable.connectionCount, 0)
    readable.connections = [1207: 2, 453: 1]
    XCTAssertEqual(readable.connectionCount, 3)
    XCTAssertEqual(readable.processCount, 2)
  }
  func testConnectionSortAndExportKeepUnknownSeparateFromZero() {
    let unavailable = ProcessRow(
      id: 11, parent: 1, uid: 0, start: 1, name: "Unknown", user: "root",
      cpu: 0, cpuTime: 0, memory: 0, resident: 0, threads: 0, read: 0,
      written: 0, isApp: false, accessible: false, kind: "Apple", ioAccessible: false)
    var zero = unavailable
    zero.id = 12
    zero.aneConnections = 0
    var connected = unavailable
    connected.id = 13
    connected.aneConnections = 2
    var query = ProcessQuery(
      metric: .ane, query: "", filter: "All processes", sort: "primary", descending: true)
    XCTAssertEqual(query.apply([unavailable, zero, connected]).map(\.id), [13, 12, 11])
    query.descending = false
    XCTAssertEqual(query.apply([connected, unavailable, zero]).map(\.id), [12, 13, 11])
    XCTAssertEqual(ProcessValues.text(unavailable, key: "primary", metric: .ane), "—")
    XCTAssertEqual(ProcessValues.text(zero, key: "primary", metric: .ane), "0")
    XCTAssertTrue(processCSV([unavailable]).hasSuffix(","))
    XCTAssertTrue(processCSV([zero]).hasSuffix(",0"))
    XCTAssertTrue(processCSV([connected]).hasSuffix(",2"))
  }
  func testLiveDriverSnapshotIsInternallyConsistent() {
    let hardware = ANEHardwareReader().read()
    if hardware.connectionsReadable {
      XCTAssertTrue(hardware.available)
      XCTAssertEqual(hardware.connectionCount, hardware.connections.values.reduce(0, +))
    } else {
      XCTAssertNil(hardware.connectionCount)
    }
  }
}
