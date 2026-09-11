import AppKit
import SwiftUI
import XCTest

@testable import ActivityMonitor

private struct UpdatingSettingsHarness: View {
  @ObservedObject var monitor: Monitor
  var body: some View {
    VStack {
      Text("CPU: \(monitor.userCPU)")
      SettingsMenuButton {
        let menu = NSMenu()
        menu.addUpdateInterval($monitor.interval)
        return menu
      }
    }
  }
}

@MainActor final class MenuInteractionTests: XCTestCase {
  func testOpenIntervalMenuSurvivesTelemetryRefreshAndAppliesTwoSeconds() async throws {
    _ = NSApplication.shared
    let monitor = Monitor(startAutomatically: false)
    let host = NSHostingView(rootView: UpdatingSettingsHarness(monitor: monitor))
    let container = window()
    container.contentView = host
    defer { container.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(25))
    let button = try XCTUnwrap(findButton(host))
    let coordinator = try XCTUnwrap(button.target as? SettingsMenuButton.Coordinator)
    let openMenu = coordinator.makeMenu()
    let submenu = try XCTUnwrap(openMenu.items.first?.submenu)
    let twoSeconds = submenu.items[1]
    for value in 1...5 {
      monitor.userCPU = Double(value)
      try await Task.sleep(for: .milliseconds(25))
      host.layoutSubtreeIfNeeded()
      XCTAssertTrue(findButton(host) === button)
      XCTAssertTrue(button.target === coordinator)
    }
    XCTAssertTrue(openMenu.items.first?.submenu === submenu)
    XCTAssertEqual(submenu.items[0].state, .on)
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(twoSeconds.action), to: twoSeconds.target, from: twoSeconds))
    XCTAssertEqual(monitor.interval, 2)
    let reopened = try XCTUnwrap(coordinator.makeMenu().items.first?.submenu)
    XCTAssertEqual(reopened.items[0].state, .off)
    XCTAssertEqual(reopened.items[1].state, .on)
  }

  func testOutsideClickClassificationPreservesPopoverAndMenus() {
    _ = NSApplication.shared
    let popover = window()
    let status = window()
    let other = window()
    let child = window()
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

  private func findButton(_ view: NSView) -> NSButton? {
    if let button = view as? NSButton { return button }
    return view.subviews.lazy.compactMap { findButton($0) }.first
  }

  private func window() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }
}
