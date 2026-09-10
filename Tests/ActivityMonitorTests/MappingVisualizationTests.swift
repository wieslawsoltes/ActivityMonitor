import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

enum MappingFixture {
  static func records(_ count: Int) -> [DiagnosticRecord] {
    (0..<count).map { index in
      let address = String(format: "0x%016llX", UInt64(0x100000 + index * 0x10000))
      let path = "/Library/Frameworks/Example\(index % 20).framework/Example\(index % 20)"
      return DiagnosticRecord(
        id: address,
        cells: [
          "Address": address, "Protection": ["r−x", "rw−", "r−−", "−−−"][index % 4], "Path": path,
        ],
        numbers: [
          "Size": Double((index % 40 + 1) * 65536), "Resident": Double((index % 8) * 16384),
        ], path: path)
    }
  }
}
final class MappingVisualizationTests: XCTestCase {
  func testProtectionTotalsKeepResidentAndVirtualSeparateAndRejectMissingValues() {
    var records = MappingFixture.records(4)
    records[0].numbers["Resident"] = nil
    records[1].numbers["Resident"] = .nan
    records[2].numbers["Resident"] = -1
    records[3].numbers["Resident"] = 0
    let resident = MappingPlotData.make(
      records: records, images: false, measure: .resident, kind: .protection)
    XCTAssertEqual(resident.total, 0)
    XCTAssertEqual(resident.omitted, 3)
    XCTAssertEqual(resident.items.count, 1, "Measured zero is retained")
    let virtual = MappingPlotData.make(
      records: records, images: false, measure: .virtual, kind: .protection)
    XCTAssertEqual(virtual.total, 655360)
    XCTAssertEqual(virtual.omitted, 0)
  }
  func testImageChartAggregatesAllMappingsByFullPathAndAccountsForOther() {
    let records = MappingFixture.records(40)
    let data = MappingPlotData.make(
      records: records, images: true, measure: .virtual, kind: .protection, limit: 3)
    XCTAssertEqual(data.items.count, 4)
    XCTAssertEqual(data.items.reduce(0) { $0 + $1.value }, data.total)
    XCTAssertEqual(data.total, records.reduce(0) { $0 + $1.numbers["Size"]! })
    XCTAssertTrue(data.items[0].detail.contains("2 mappings"))
    let a = DiagnosticRecord(
      id: "a", cells: ["Path": "/A/Same.dylib"], numbers: ["Size": 10], path: "/A/Same.dylib")
    let b = DiagnosticRecord(
      id: "b", cells: ["Path": "/B/Same.dylib"], numbers: ["Size": 20], path: "/B/Same.dylib")
    XCTAssertEqual(
      MappingPlotData.make(records: [a, b], images: true, measure: .virtual, kind: .protection)
        .items.count, 2)
  }
  func testAddressRangesRetainIntegerPrecisionAndRejectOverflow() {
    let base: UInt64 = (1 << 60) + 1
    var records = (0..<2).map { index in
      let text = String(format: "0x%016llX", base + UInt64(index * 8))
      return DiagnosticRecord(id: text, cells: ["Address": text], numbers: ["Size": 4])
    }
    records.append(
      .init(id: "bad", cells: ["Address": "0xFFFFFFFFFFFFFFFE"], numbers: ["Size": 10]))
    records.append(
      .init(id: "invalid", cells: ["Address": "not an address"], numbers: ["Size": 10]))
    let data = MappingPlotData.make(
      records: records, images: false, measure: .virtual, kind: .addresses)
    XCTAssertEqual(data.base, base)
    XCTAssertEqual(data.span, 12)
    XCTAssertEqual(data.items[0].end! - data.base, 4)
    XCTAssertEqual(data.items[1].start! - data.base, 8)
    XCTAssertEqual(data.omitted, 2)
    XCTAssertEqual(data.items.count, 2)
  }
  func testMappedImagesPreserveEveryExecutableMappingAndPartialStatus() {
    var records = MappingFixture.records(4)
    records[1].path = records[0].path
    records[1].cells["Protection"] = "r−x"
    let section = DiagnosticSection(records: records, status: "Partial results", date: Date())
    let images = DiagnosticCollector.images(in: section)
    XCTAssertEqual(images.records.count, 2)
    XCTAssertEqual(images.records[0].path, images.records[1].path)
    XCTAssertTrue(images.status.contains("Partial results"))
    XCTAssertEqual(images.date, section.date)
  }
  @MainActor func testAllMappingChartsRenderInBothThemes() throws {
    let section = DiagnosticSection(
      records: MappingFixture.records(50), status: "50 entries", date: Date())
    for dark in [false, true] {
      for (images, kind) in [
        (false, MappingPlotKind.protection), (false, .addresses), (true, .protection),
      ] {
        let view = MappingVisualization(
          section: section, query: "", images: images, theme: .init(dark: dark), kind: kind)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 280)
        let window = NSWindow(
          contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["AM_MAPPING_RENDER"] {
          try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
          try bitmap.representation(using: .png, properties: [:])?.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
              "\(images ? "images" : kind == .addresses ? "ranges" : "protection")-\(dark ? "dark" : "light").png"
            ))
        }
        XCTAssertEqual(host.bounds.height, 280, accuracy: 1)
        window.contentView = nil
        window.close()
      }
    }
  }
}
