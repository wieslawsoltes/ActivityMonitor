import AppKit
import Combine
import SwiftUI

@MainActor final class MonitorServices {
  let monitor = Monitor()
  let navigation = MonitorNavigation()
  lazy var tray = MonitorMenuBarController(monitor: monitor, navigation: navigation)
}

/// SwiftUI scene routing stays available when the last main window has closed.
struct TrayLifecycle: View {
  let services: MonitorServices
  let enabled: Bool
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Color.clear.frame(width: 0, height: 0)
      .onAppear {
        services.tray.openMonitor = {
          openWindow(id: "monitor")
          NSApp.activate(ignoringOtherApps: true)
        }
        services.tray.setEnabled(enabled)
      }
      .onChange(of: enabled) { services.tray.setEnabled(enabled) }
  }
}

/// AppKit owns only the status item and transient popover; content and telemetry remain SwiftUI.
@MainActor final class MonitorMenuBarController: NSObject, NSPopoverDelegate {
  let monitor: Monitor
  let navigation: MonitorNavigation
  var openMonitor: () -> Void = {}
  private var item: NSStatusItem?
  private let popover = NSPopover()
  private let presentation = MenuBarPresentation()
  var hasPopoverContent: Bool { popover.contentViewController != nil }
  private var subscriptions = Set<AnyCancellable>()
  init(monitor: Monitor, navigation: MonitorNavigation) {
    self.monitor = monitor
    self.navigation = navigation
    super.init()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.delegate = self
    monitor.$lastUpdate.combineLatest(monitor.$paused)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.updateLabel() }.store(in: &subscriptions)
  }
  private func createPopoverContent() {
    popover.contentViewController = NSHostingController(
      rootView:
        MenuBarMonitor(
          openMonitor: { [weak self] in self?.openMonitor() },
          closePopover: { [weak self] in self?.popover.performClose(nil) },
          presentation: presentation
        )
        .environmentObject(monitor).environmentObject(navigation))
  }
  func popoverDidClose(_ notification: Notification) {
    popover.contentViewController = nil
  }
  func setEnabled(_ enabled: Bool) {
    if enabled && item == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      self.item = item
      item.button?.target = self
      item.button?.action = #selector(togglePopover)
      item.button?.imagePosition = .imageLeading
      item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      item.button?.setAccessibilityIdentifier("activity-monitor-status")
      updateLabel()
    } else if !enabled, let item {
      popover.performClose(nil)
      NSStatusBar.system.removeStatusItem(item)
      self.item = nil
    }
  }
  private func updateLabel() {
    guard let button = item?.button else { return }
    button.image = MenuBarGlyph.image(monitor.histories[.cpu] ?? [], paused: monitor.paused)
    button.title = String(
      format: " %.0f%%", CPUAccounting.executionPercent(monitor.userCPU + monitor.systemCPU))
    button.toolTip =
      "Activity Monitor · Total CPU" + button.title + " " + CPUAccounting.capacityLabel
      + (monitor.paused ? " · Paused" : "")
    button.setAccessibilityLabel(button.toolTip)
  }
  @objc func togglePopover() {
    guard let button = item?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      if !hasPopoverContent { createPopoverContent() }
      popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }
}
