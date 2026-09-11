import AppKit
import Combine
import SwiftUI

@MainActor final class ProcessDiagnosticsCenter {
  private weak var monitor: Monitor?
  private var sessions: [ProcessIdentity: ProcessDiagnosticSession] = [:]
  private var detailLeases: [ProcessIdentity: Int] = [:]
  private var leases: [ProcessIdentity: Int] = [:]
  private var windows: [ProcessIdentity: DiagnosticWindowController] = [:]
  private var pins: [ProcessIdentity: ProcessPinController] = [:]
  private var subscription: AnyCancellable?
  var sessionCount: Int { sessions.count }
  init(monitor: Monitor) {
    self.monitor = monitor
    subscription = monitor.$lastUpdate.combineLatest(monitor.$paused).sink {
      [weak self, weak monitor] date, paused in
      guard let self, let monitor, let date else { return }
      for session in self.sessions.values {
        session.sourcePaused = paused
        session.accept(rows: monitor.rows, date: date, gpuDevices: monitor.gpuDevices)
        session.refreshThreadActivity()
        if (self.detailLeases[session.id] ?? 0) > 0 { session.refreshDetails() }
      }
    }
  }
  func acquire(_ row: ProcessRow, details: Bool = true) -> ProcessDiagnosticSession {
    let id = ProcessIdentity(row)
    let session = sessions[id] ?? ProcessDiagnosticSession(row: row)
    sessions[id] = session
    leases[id, default: 0] += 1
    if details { detailLeases[id, default: 0] += 1 }
    session.sourcePaused = monitor?.paused ?? false
    session.accept(
      rows: [row], date: monitor?.lastUpdate ?? Date(), gpuDevices: monitor?.gpuDevices ?? [])
    if details { session.refreshDetails() }
    return session
  }
  func release(_ session: ProcessDiagnosticSession, details: Bool = true) {
    if details { detailLeases[session.id, default: 0] -= 1 }
    leases[session.id, default: 0] -= 1
    if (leases[session.id] ?? 0) <= 0 {
      sessions[session.id] = nil
      leases[session.id] = nil
      detailLeases[session.id] = nil
      session.cancelReport()
    }
  }
  func openWindow(_ row: ProcessRow) {
    let id = ProcessIdentity(row)
    if let controller = windows[id] {
      controller.showWindow(nil)
      controller.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let session = acquire(row)
    let controller = DiagnosticWindowController(session: session, center: self)
    controller.onClose = { [weak self, weak session] in
      guard let self, let session else { return }
      self.windows[id] = nil
      self.release(session)
    }
    windows[id] = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func showPin(_ session: ProcessDiagnosticSession) {
    // Let the action menu finish closing before presenting a transient popover.
    DispatchQueue.main.async { [weak self] in self?.pins[session.id]?.toggle() }
  }
  func togglePin(_ session: ProcessDiagnosticSession) {
    if let pin = pins.removeValue(forKey: session.id) {
      pin.remove()
      session.pinned = false
      release(session, details: false)
    } else {
      let retained = acquire(session.row, details: false)
      pins[session.id] = ProcessPinController(session: retained, center: self)
      session.pinned = true
    }
  }
  func terminate(_ session: ProcessDiagnosticSession, force: Bool) {
    monitor?.terminate(session.row, force: force)
  }
  func related(to session: ProcessDiagnosticSession) -> [ProcessRow] {
    monitor?.rows.filter { $0.id == session.row.parent || $0.parent == session.id.pid } ?? []
  }
}
@MainActor final class DiagnosticWindowController: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?
  init(session: ProcessDiagnosticSession, center: ProcessDiagnosticsCenter) {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740),
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .utilityWindow],
      backing: .buffered, defer: false)
    super.init(window: panel)
    panel.title = "\(session.row.name) — PID \(session.id.pid)"
    panel.minSize = NSSize(width: 780, height: 540)
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.contentViewController = NSHostingController(
      rootView: ProcessDiagnosticsView(
        session: session, center: center, toolWindow: true, close: { [weak self] in self?.close() },
        float: { [weak panel] enabled in panel?.level = enabled ? .floating : .normal }))
    panel.setContentSize(NSSize(width: 1060, height: 740))
    panel.delegate = self
    panel.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowWillClose(_ notification: Notification) {
    onClose?()
    onClose = nil
  }
}
@MainActor final class ProcessPinController: NSObject, NSPopoverDelegate {
  private var item: NSStatusItem?
  private let popover = NSPopover()
  private let session: ProcessDiagnosticSession
  private weak var center: ProcessDiagnosticsCenter?
  private var subscription: AnyCancellable?
  init(session: ProcessDiagnosticSession, center: ProcessDiagnosticsCenter) {
    self.session = session
    self.center = center
    super.init()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.item = item
    item.button?.target = self
    item.button?.action = #selector(toggle)
    item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    item.button?.setAccessibilityIdentifier("process-pin-\(session.id.pid)")
    popover.behavior = .transient
    popover.delegate = self
    subscription = session.objectWillChange.sink { [weak self] in
      DispatchQueue.main.async { [weak self] in self?.update() }
    }
    update()
  }
  private func update() {
    let value = ProcessActivityPresentation.latest(session, metric: session.pinMetric)
    item?.button?.title = "\(session.row.name.prefix(12)) \(session.exited ? "Exited" : value)"
    item?.button?.toolTip =
      "\(session.row.name) · PID \(session.id.pid) · \(session.pinMetric.rawValue) · \(session.state)"
    item?.button?.setAccessibilityLabel(item?.button?.toolTip)
  }
  @objc func toggle() {
    guard let button = item?.button, let center else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    let session = self.session
    popover.contentViewController = NSHostingController(
      rootView: ProcessPinView(
        session: session,
        open: { [weak self, weak center] in
          self?.popover.performClose(nil)
          center?.openWindow(session.row)
        },
        unpin: { [weak self, weak center] in
          self?.popover.performClose(nil)
          center?.togglePin(session)
        }))
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }
  func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }
  func remove() {
    popover.performClose(nil)
    if let item { NSStatusBar.system.removeStatusItem(item) }
    item = nil
    subscription = nil
  }
}
