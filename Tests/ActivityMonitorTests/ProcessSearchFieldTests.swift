import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

@MainActor final class ProcessSearchFieldTests: XCTestCase {
  func testPresentationFocusesNativeFieldAndEscapeClearsThenDismisses() async throws {
    var query = "Chrome"
    var presented = true
    var focused = false
    let search = ProcessSearchField(
      query: Binding(get: { query }, set: { query = $0 }),
      presented: Binding(get: { presented }, set: { presented = $0 }),
      focusChanged: { focused = $0 })
    let host = NSHostingView(rootView: search)
    host.frame = CGRect(x: 0, y: 0, width: 180, height: 30)
    let window = NSWindow(
      contentRect: host.frame, styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(50))
    func field(in view: NSView) -> NSSearchField? {
      if let search = view as? NSSearchField { return search }
      return view.subviews.lazy.compactMap { field(in: $0) }.first
    }
    let control = try XCTUnwrap(field(in: host))
    let editor = try XCTUnwrap(control.currentEditor() as? NSTextView)
    XCTAssertTrue(window.firstResponder === editor)
    XCTAssertEqual(control.stringValue, "Chrome")
    let delegate = try XCTUnwrap(control.delegate as? ProcessSearchField.Coordinator)
    let cancel = #selector(NSResponder.cancelOperation(_:))
    XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: cancel))
    XCTAssertEqual(query, "")
    XCTAssertTrue(presented)
    XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: cancel))
    XCTAssertFalse(presented)
    XCTAssertFalse(focused)
  }
}
