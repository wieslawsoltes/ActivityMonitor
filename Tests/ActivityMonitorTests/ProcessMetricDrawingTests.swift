import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

final class ProcessMetricDrawingTests: XCTestCase {
  @MainActor func testEveryMetricDrawsValuesAndRefreshesInBothAppearances() throws {
    for metric in Metric.allCases {
      for dark in [false, true] {
        var row = PerformanceFixture.rows(2)[1]
        row.cpu = 123.4
        let columns = ProcessColumns.available(metric)
        let layout = ProcessColumnLayout(
          viewport: 1200, metric: metric, columns: columns, saved: ProcessColumnWidths())
        let theme = MonitorTheme(dark: dark)
        func render(_ row: ProcessRow) throws -> NSBitmapImageRep {
          let view = Canvas { context, _ in
            context.withCGContext {
              ProcessMetricDrawing.draw(
                row: row, columns: columns, layout: layout, metric: metric, theme: theme, in: $0)
            }
          }.background(theme.card)
          let host = NSHostingView(rootView: view)
          host.frame = CGRect(x: 0, y: 0, width: layout.total, height: 41)
          host.layoutSubtreeIfNeeded()
          let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: image)
          return image
        }
        let image = try render(row)
        if let directory = ProcessInfo.processInfo.environment["AM_RENDER_DIR"], metric == .cpu {
          try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
          try image.representation(using: .png, properties: [:])?.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent(
              "metrics-\(dark ? "dark" : "light").png"))
        }
        let scale = CGFloat(image.pixelsWide) / layout.total
        let background = try XCTUnwrap(image.colorAt(x: 1, y: 1)?.usingColorSpace(.sRGB))
        for column in columns {
          var ink = 0
          for y in 12..<29 {
            for x in Int(
              layout.offset(column.id) + 10)..<Int(
                layout.offset(column.id) + layout.width(column.id) - 10)
            {
              let color = try XCTUnwrap(
                image.colorAt(
                  x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.usingColorSpace(.sRGB))
              let difference =
                abs(color.redComponent - background.redComponent)
                + abs(color.greenComponent - background.greenComponent)
                + abs(color.blueComponent - background.blueComponent)
              if difference > 0.45 { ink += 1 }
            }
          }
          XCTAssertGreaterThan(ink, 0, "Missing \(metric) \(column.id), dark=\(dark)")
        }
        if metric == .cpu {
          row.cpu = 987.6
          let updated = try render(row)
          XCTAssertNotEqual(
            image.representation(using: .png, properties: [:]),
            updated.representation(using: .png, properties: [:]))
        }
      }
    }
    XCTAssertLessThanOrEqual(ProcessMetricDrawing.cache.count, 4096)
  }
}
