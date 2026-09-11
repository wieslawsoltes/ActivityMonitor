import SwiftUI

struct ProcessViewModePicker: View {
  @Binding var mode: ProcessViewMode
  let theme: MonitorTheme
  var compact = false
  var body: some View {
    HStack(spacing: 2) {
      ForEach(ProcessViewMode.allCases) { item in
        Button {
          mode = item
        } label: {
          HStack(spacing: 5) {
            Image(systemName: item.icon).font(.system(size: 11))
            if !compact { Text(item.title).font(.system(size: 10, weight: .medium)) }
          }.foregroundStyle(mode == item ? theme.blue : theme.secondary)
            .frame(width: compact ? 27 : 53, height: 25)
        }.buttonStyle(MonitorSegmentButton(theme: theme, active: mode == item, radius: 5))
          .accessibilityLabel("\(item.title) view")
          .accessibilityIdentifier("process-view-\(item.rawValue)")
          .accessibilityAddTraits(mode == item ? .isSelected : [])
          .help("Show processes as a \(item.rawValue) · ⌘⇧T")
      }
    }.padding(3).background(theme.recessed, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
      .fixedSize().accessibilityElement(children: .contain).accessibilityLabel("Process display")
  }
}

struct ProcessViewActions {
  var mode: Binding<ProcessViewMode>
  var hasBranches: Bool
  var expandAll: () -> Void
  var collapseAll: () -> Void
}
private struct ProcessViewActionsKey: FocusedValueKey {
  typealias Value = ProcessViewActions
}
extension FocusedValues {
  var processViewActions: ProcessViewActions? {
    get { self[ProcessViewActionsKey.self] }
    set { self[ProcessViewActionsKey.self] = newValue }
  }
}
struct ProcessViewCommands: Commands {
  @FocusedValue(\.processViewActions) private var actions
  var body: some Commands {
    CommandGroup(before: .toolbar) {
      Toggle(
        "Show Process Tree",
        isOn: Binding(
          get: { actions?.mode.wrappedValue == .tree },
          set: { actions?.mode.wrappedValue = $0 ? .tree : .list }
        )
      ).keyboardShortcut("t", modifiers: [.command, .shift]).disabled(actions == nil)
      Divider()
      Button("Expand All Processes") { actions?.expandAll() }
        .disabled(actions?.mode.wrappedValue != .tree || actions?.hasBranches != true)
      Button("Collapse All Processes") { actions?.collapseAll() }
        .disabled(actions?.mode.wrappedValue != .tree || actions?.hasBranches != true)
    }
  }
}
