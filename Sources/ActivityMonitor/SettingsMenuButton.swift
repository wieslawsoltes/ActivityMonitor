import AppKit
import SwiftUI

/// Build once per opening. Telemetry can redraw SwiftUI without replacing a tracked submenu.
struct SettingsMenuButton: NSViewRepresentable {
  var size: CGFloat = 32
  var makeMenu: () -> NSMenu

  func makeCoordinator() -> Coordinator { Coordinator(makeMenu: makeMenu) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Settings")!,
                          target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.toolTip = "Monitor settings"
    button.setAccessibilityIdentifier("monitor-settings")
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    // Only update the factory, never the menu AppKit is currently tracking.
    context.coordinator.makeMenu = makeMenu
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
    CGSize(width: size, height: size)
  }
  final class Coordinator: NSObject {
    var makeMenu: () -> NSMenu
    init(makeMenu: @escaping () -> NSMenu) { self.makeMenu = makeMenu }
    @objc func openMenu(_ sender: NSButton) {
      let menu = makeMenu()
      let y = sender.isFlipped ? sender.bounds.maxY + 4 : sender.bounds.minY - 4
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
    }
  }
}

/// Each item owns its action for the lifetime of the native tracking session.
final class SettingsMenuItem: NSMenuItem {
  private let handler: () -> Void
  init(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: #selector(invoke), keyEquivalent: "")
    target = self
    state = checked ? .on : .off
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func invoke() { handler() }
}

extension NSMenu {
  func addAction(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
    addItem(SettingsMenuItem(title, checked: checked, action: action))
  }
  func addChoices<Value: Equatable>(_ title: String, values: [(String, Value)], selection: Binding<Value>) {
    let submenu = NSMenu(title: title)
    for (label, value) in values {
      submenu.addAction(label, checked: selection.wrappedValue == value) { selection.wrappedValue = value }
    }
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    addItem(item)
  }
  func addUpdateInterval(_ selection: Binding<Double>) {
    addChoices("Update interval", values: [("Every second", 1), ("Every 2 seconds", 2), ("Every 5 seconds", 5)], selection: selection)
  }
  func addAppearance(_ selection: Binding<String>) {
    addChoices("Appearance", values: ["Light", "Dark", "System"].map { ($0, $0) }, selection: selection)
  }
}
