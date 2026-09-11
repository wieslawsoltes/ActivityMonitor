import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

private struct UpdatingSettingsHarness: View {
  @ObservedObject var monitor: Monitor

  var body: some View {
    VStack {
      Text("Rows: \(monitor.rows.count) · CPU: \(monitor.userCPU)")
      SettingsMenuButton {
        let menu = NSMenu()
        menu.addUpdateInterval($monitor.interval)
        return menu
      }
    }
  }
}

@MainActor final class MenuInteractionTests: XCTestCase {
  func testSettingsButtonSurvivesTelemetryRefreshesAndKeepsMenuSourceStable() async throws {
    _ = NSApplication.shared
    let monitor = Monitor(startAutomatically: false)
    let host = NSHostingView(rootView: UpdatingSettingsHarness(monitor: monitor))
    let window = testWindow()
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(25))

    let button = try XCTUnwrap(findButton(in: host))
    let coordinator = try XCTUnwrap(button.target as? SettingsMenuButton.Coordinator)
    let menu = coordinator.makeMenu()
    let submenu = try XCTUnwrap(menu.items.first?.submenu)
    XCTAssertEqual(submenu.items[0].state, .on)

    for value in 1...5 {
      monitor.rows = []
      monitor.userCPU = Double(value)
      monitor.lastUpdate = Date(timeIntervalSince1970: Double(value))
      host.layoutSubtreeIfNeeded()
      XCTAssertTrue(findButton(in: host) === button)
      XCTAssertTrue(button.target === coordinator)
      XCTAssertTrue(menu.items.first?.submenu === submenu)
    }

    let twoSeconds = submenu.items[1]
    XCTAssertTrue(
      NSApp.sendAction(try XCTUnwrap(twoSeconds.action), to: twoSeconds.target, from: twoSeconds))
    XCTAssertEqual(monitor.interval, 2)
    let reopened = try XCTUnwrap(coordinator.makeMenu().items.first?.submenu)
    XCTAssertEqual(reopened.items[0].state, .off)
    XCTAssertEqual(reopened.items[1].state, .on)
  }

  func testSettingsMenuButtonExposesAccessibleNativeControl() throws {
    _ = NSApplication.shared
    let host = NSHostingView(
      rootView: SettingsMenuButton(accessibilityLabel: "Monitor settings") { NSMenu() }
    )
    let window = testWindow()
    window.contentView = host
    defer {
      window.contentView = nil
      window.close()
    }
    host.layoutSubtreeIfNeeded()

    let button = try XCTUnwrap(findButton(in: host))
    XCTAssertEqual(button.accessibilityLabel(), "Monitor settings")
    XCTAssertEqual(button.accessibilityIdentifier(), "monitor-settings")
    XCTAssertFalse(button.isBordered)
  }

  func testOutsideClickClassificationPreservesPopoverAndMenus() {
    _ = NSApplication.shared
    let popover = testWindow()
    let status = testWindow()
    let other = testWindow()
    let child = testWindow()
    popover.addChildWindow(child, ordered: .above)
    defer {
      popover.removeChildWindow(child)
      [popover, status, other, child].forEach { $0.close() }
    }
    func outside(_ target: NSWindow?) -> Bool {
      PopoverOutsideClickMonitor.isOutside(target, popoverWindow: popover, statusWindow: status)
    }
    XCTAssertFalse(outside(popover))
    XCTAssertFalse(outside(status))
    XCTAssertFalse(outside(child))
    XCTAssertTrue(outside(other))
    XCTAssertTrue(outside(nil))
    other.level = .popUpMenu
    XCTAssertFalse(outside(other))
  }

  private func findButton(in view: NSView) -> NSButton? {
    if let button = view as? NSButton { return button }
    return view.subviews.lazy.compactMap { self.findButton(in: $0) }.first
  }

  private func testWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }
}
