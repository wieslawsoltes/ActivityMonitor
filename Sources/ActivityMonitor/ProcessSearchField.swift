import AppKit
import SwiftUI

/// Use AppKit's search field for native editing, cancellation, focus and appearance.
struct ProcessSearchField: NSViewRepresentable {
  @Binding var query: String
  @Binding var presented: Bool
  var focusChanged: (Bool) -> Void

  final class Field: NSSearchField {
    var requestsFocus = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      focusIfRequested()
    }
    func focusIfRequested() {
      DispatchQueue.main.async { [weak self] in
        guard let self, self.requestsFocus, let window = self.window else { return }
        self.requestsFocus = false
        window.makeFirstResponder(self)
      }
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: ProcessSearchField
    var wasPresented = false
    init(_ parent: ProcessSearchField) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      parent.query = field.stringValue
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      parent.focusChanged(true)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      parent.focusChanged(false)
      parent.presented = false
    }
    func control(
      _ control: NSControl, textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
      if !parent.query.isEmpty {
        parent.query = ""
        (control as? NSSearchField)?.stringValue = ""
      } else {
        parent.presented = false
        control.window?.makeFirstResponder(nil)
        parent.focusChanged(false)
      }
      return true
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> Field {
    let field = Field()
    field.placeholderString = "Search processes"
    field.font = .systemFont(ofSize: 11)
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.delegate = context.coordinator
    field.setAccessibilityLabel("Search processes")
    field.setAccessibilityIdentifier("process-search-field")
    return field
  }
  func updateNSView(_ field: Field, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != query { field.stringValue = query }
    if presented && !context.coordinator.wasPresented {
      field.requestsFocus = true
      field.focusIfRequested()
    }
    if !presented { field.requestsFocus = false }
    context.coordinator.wasPresented = presented
  }
}
