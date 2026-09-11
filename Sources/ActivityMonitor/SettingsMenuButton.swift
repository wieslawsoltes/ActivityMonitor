import AppKit
import SwiftUI

/// A settings button whose native menu remains independent from SwiftUI telemetry updates.
///
/// SwiftUI's `Menu` is rebuilt when the observed monitor publishes a new process snapshot. If
/// a nested submenu is open at that moment, AppKit loses the menu tracking session. The button
/// below is a stable `NSView`; it creates a native menu only when the user opens it and updates
/// only the factory while the view is being redrawn.
struct SettingsMenuButton: NSViewRepresentable {
  var size: CGFloat = 32
  var accessibilityLabel = "More"
  var toolTip = "More"
  var makeMenu: () -> NSMenu

  func makeCoordinator() -> Coordinator {
    Coordinator(makeMenu: makeMenu)
  }

  func makeNSView(context: Context) -> NSButton {
    let image =
      NSImage(
        systemSymbolName: "ellipsis",
        accessibilityDescription: accessibilityLabel
      ) ?? NSImage()
    image.isTemplate = true
    let button = NSButton(
      image: image,
      target: context.coordinator,
      action: #selector(Coordinator.openMenu(_:))
    )
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.setButtonType(.momentaryPushIn)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.focusRingType = .none
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = toolTip
    button.setAccessibilityLabel(accessibilityLabel)
    button.setAccessibilityIdentifier("monitor-settings")
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    // Keep the native button and any menu AppKit is tracking. Only the next-open factory changes.
    context.coordinator.makeMenu = makeMenu
    button.toolTip = toolTip
    button.setAccessibilityLabel(accessibilityLabel)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NSButton, context: Context
  ) -> CGSize? {
    CGSize(width: size, height: size)
  }

  final class Coordinator: NSObject, NSMenuDelegate {
    var makeMenu: () -> NSMenu
    private var activeMenu: NSMenu?

    init(makeMenu: @escaping () -> NSMenu) {
      self.makeMenu = makeMenu
    }

    @objc func openMenu(_ sender: NSButton) {
      let menu = makeMenu()
      activeMenu = menu
      menu.delegate = self
      // NSMenu positions a popup from the supplied point in the sender's coordinate space. The
      // lower edge is the correct anchor for an unflipped title-bar view; use the upper edge for
      // a flipped host such as a popover.
      let point =
        sender.isFlipped
        ? NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4)
        : NSPoint(x: sender.bounds.minX, y: sender.bounds.minY - 4)
      menu.popUp(positioning: nil, at: point, in: sender)
      if activeMenu === menu { activeMenu = nil }
    }

    func menuDidClose(_ menu: NSMenu) {
      if activeMenu === menu { activeMenu = nil }
    }
  }
}

private final class SettingsMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
    handler = action
    super.init(title: title, action: #selector(invoke), keyEquivalent: "")
    target = self
    state = checked ? .on : .off
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func invoke() {
    handler()
  }
}

extension NSMenu {
  func addSettingsAction(
    _ title: String, checked: Bool = false, action: @escaping () -> Void
  ) {
    addItem(SettingsMenuItem(title, checked: checked, action: action))
  }

  func addSettingsChoices<Value: Equatable>(
    _ title: String, values: [(String, Value)], selection: Binding<Value>
  ) {
    let submenu = NSMenu(title: title)
    for (label, value) in values {
      submenu.addSettingsAction(label, checked: selection.wrappedValue == value) {
        selection.wrappedValue = value
      }
    }
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    addItem(item)
  }

  func addSettingsToggle(
    _ title: String, selection: Binding<Bool>
  ) {
    addSettingsAction(title, checked: selection.wrappedValue) {
      selection.wrappedValue.toggle()
    }
  }

  func addUpdateInterval(_ selection: Binding<Double>) {
    addSettingsChoices(
      "Update interval",
      values: [("Every second", 1.0), ("Every 2 seconds", 2.0), ("Every 5 seconds", 5.0)],
      selection: selection
    )
  }

  func addAppearance(_ selection: Binding<String>) {
    addSettingsChoices(
      "Appearance",
      values: ["Light", "Dark", "System"].map { ($0, $0) },
      selection: selection
    )
  }
}
