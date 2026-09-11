import AppKit
import SwiftUI

struct ProcessColumn: Identifiable, Equatable {
  let id: String
  let title: String
  let weight: CGFloat
}
struct MonitorProcessTable: View {
  let rows: [ProcessRow]
  let metric: Metric
  let theme: MonitorTheme
  @Binding var query: String
  @Binding var filter: String
  @Binding var mode: ProcessViewMode
  @ObservedObject var tree: ProcessTreePresentation
  let sourceRows: [ProcessRow]
  @Binding var selection: Int32?
  @Binding var selectedIDs: Set<Int32>
  @Binding var inspector: Bool
  @Binding var sort: String
  @Binding var descending: Bool
  let inspect: (ProcessRow) -> Void
  let stop: (ProcessRow) -> Void
  let stopMany: ([ProcessRow]) -> Void
  let searchFocus: FocusState<Bool>.Binding
  var diagnose: ((ProcessRow, Bool) -> Void)? = nil
  @AppStorage("showThreads") var showThreads = true
  @AppStorage("showUser") var showUser = true
  @AppStorage("showTime") var showTime = true
  @FocusState var focused: Bool
  @State private var availableWidth: CGFloat = 1200
  @AppStorage("showAllProcessColumns") private var allColumnsVisible = false
  @AppStorage("processColumnVisibility.v1") private var columnVisibility = "{}"
  @AppStorage("processColumnWidths.v1") private var columnWidths = "{}"
  @State private var draftWidths: [String: CGFloat] = [:]
  @State private var viewportWidth: CGFloat?
  @State private var horizontalOffset: CGFloat = 0
  @AppStorage("processColumnOrder.v1") private var columnOrder = "{}"
  var hierarchy: Bool { mode == .tree }
  var entries: [ProcessTreeEntry] {
    hierarchy
      ? tree.entries
      : rows.map { ProcessTreeEntry(row: $0, depth: 0, hasChildren: false) }
  }
  var displayRows: [ProcessRow] { hierarchy ? tree.entries.map(\.row) : rows }
  var orderPreferences: ProcessColumnOrder { ProcessColumnOrder(columnOrder) }
  var orderedKeys: [String] {
    orderPreferences.ordered(["name"] + columns.map(\.id), metric: metric)
  }
  var selectedRows: [ProcessRow] {
    guard !selectedIDs.isEmpty else { return [] }
    return displayRows.filter { selectedIDs.contains($0.id) }
  }
  var widthPreferences: ProcessColumnWidths {
    var value = ProcessColumnWidths(columnWidths)
    for (key, width) in draftWidths { value.set(key, metric: metric, width: width) }
    return value
  }
  var preferences: ProcessColumnPreferences { ProcessColumnPreferences(columnVisibility) }
  var allColumns: [ProcessColumn] {
    let saved = preferences
    let enabled = ProcessColumns.available(metric).filter {
      saved.isVisible(
        $0.id, metric: metric, showTime: showTime,
        showThreads: showThreads, showUser: showUser)
    }
    guard hierarchy else { return enabled }
    return enabled.map { column in
      ProcessColumn(
        id: column.id,
        title: ProcessUsageMetric.resolve(column.id, metric: metric) == nil
          ? column.title : "Σ " + column.title,
        weight: column.weight)
    }
  }
  var columns: [ProcessColumn] {
    let enabled = allColumns
    let explicit = preferences.explicitlyEnabled(metric)
    guard !allColumnsVisible else { return enabled }
    let automatic = Set(
      ProcessColumnPolicy.visible(
        enabled, metric: metric, width: viewportWidth ?? availableWidth, sort: sort
      ).map(\.id))
    return enabled.filter {
      automatic.contains($0.id) || explicit.contains($0.id)
    }
  }
  var body: some View {
    GeometryReader { g in
      let visibleColumns = columns
      let visibleEntries = entries
      let chosenRows = selectedRows
      let canStopChosen = canStop
      let toolbarHeight: CGFloat = g.size.width >= 900 ? 61 : 76
      VStack(spacing: 0) {
        if g.size.width >= 900 {
          toolbar.frame(height: toolbarHeight)
        } else {
          compactToolbar.frame(height: toolbarHeight)
        }
        Rectangle().fill(theme.separator).frame(height: 1)
        let fallback =
          g.size.width
          - (NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
        let layout = ProcessColumnLayout(
          viewport: viewportWidth ?? fallback, metric: metric, columns: visibleColumns,
          saved: widthPreferences, order: orderPreferences)
        ScrollView([.horizontal, .vertical]) {
          ProcessViewportRows(
            entries: visibleEntries,
            height: max(1, g.size.height - toolbarHeight - 1),
            widthChanged: { viewportWidth = $0 },
            horizontalChanged: { horizontalOffset = $0 }
          ) { index, entry in
            let row = entry.row
            ProcessTableRow(
              row: row, index: index, layout: layout, metric: metric, theme: theme,
              columns: visibleColumns, selectedSet: selectedIDs, hierarchical: hierarchy,
              depth: entry.depth, hasChildren: entry.hasChildren,
              expanded: entry.expanded, isContext: entry.isContext,
              parentID: entry.parentID, parentName: entry.parentName,
              usage: entry.usage,
              toggleExpanded: {
                tree.toggle(row.id, recursive: NSEvent.modifierFlags.contains(.option))
              },
              expandBranch: { tree.setExpanded(row.id, true, recursive: true) },
              collapseBranch: { tree.setExpanded(row.id, false, recursive: true) },
              selectParent: { if let parent = entry.parentID { selectOnly(parent) } },
              isSelected: selectedIDs.contains(row.id),
              select: {
                selectRow(row.id)
              }, inspect: inspect, stop: stop,
              copy: { copyRows(selectedIDs.contains(row.id) ? chosenRows : [row]) },
              stopSelection: { stopMany(selectedIDs.contains(row.id) ? chosenRows : [row]) },
              canStopSelection: selectedIDs.contains(row.id)
                ? canStopChosen : row.uid == getuid() && row.id > 1 && row.id != getpid(),
              diagnose: diagnose
            ).equatable().id(row.id)
          }.frame(width: layout.total)
            .background(
              ProcessTableSelectionScroll(
                selectedID: selection, rowIndex: visibleEntries.firstIndex { $0.id == selection },
                revealRevision: tree.revealRevision))
        }.defaultScrollAnchor(.topLeading)
          .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
              header(layout, columns: visibleColumns).frame(height: 36)
              Rectangle().fill(theme.separator).frame(height: 1)
            }
            .offset(x: -horizontalOffset)
            .frame(width: viewportWidth ?? fallback, height: 37, alignment: .leading)
            .clipped()
            .background(theme.subtle)
          }
          .overlay {
            if rows.isEmpty { ContentUnavailableView.search(text: query).padding(.top, 37) }
          }
          .scrollIndicators(.automatic)
          .focusable().focusEffectDisabled().focused($focused)
          .onKeyPress(.upArrow, phases: .down) { press in
            move(-1, extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.downArrow, phases: .down) { press in
            move(1, extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.home, phases: .down) { press in
            move(-displayRows.count, extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.end, phases: .down) { press in
            move(displayRows.count, extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.pageUp, phases: .down) { press in
            move(-max(1, Int(g.size.height / 41) - 3), extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.pageDown, phases: .down) { press in
            move(max(1, Int(g.size.height / 41) - 3), extending: press.modifiers.contains(.shift))
            return .handled
          }
          .onKeyPress(.leftArrow, phases: .down) { press in
            guard hierarchy, let selection else { return .ignored }
            selectOnly(
              tree.navigate(selection, right: false, recursive: press.modifiers.contains(.option)))
            return .handled
          }
          .onKeyPress(.rightArrow, phases: .down) { press in
            guard hierarchy, let selection else { return .ignored }
            selectOnly(
              tree.navigate(selection, right: true, recursive: press.modifiers.contains(.option)))
            return .handled
          }
          .onKeyPress(.return) {
            if let p = displayRows.first(where: { $0.id == selection }) { inspect(p) }
            return .handled
          }
          .onKeyPress(.escape) {
            inspector = false
            return .handled
          }
          .onCopyCommand {
            guard !selectedRows.isEmpty else { return [] }
            return [
              NSItemProvider(
                object: processClipboard(
                  selectedRows, keys: orderedKeys, metric: metric,
                  usage: hierarchy ? tree.snapshot.usageByID : nil)
                  as NSString)
            ]
          }
          .onCommand(#selector(NSText.selectAll(_:))) { selectAllRows() }
          .onKeyPress { press in
            if press.modifiers.contains(.command), press.characters.lowercased() == "a" {
              selectAllRows()
              return .handled
            }
            if press.modifiers.contains(.command), press.characters.lowercased() == "c" {
              copyRows(selectedRows)
              return .handled
            }
            return .ignored
          }
          .onAppear {
            availableWidth = g.size.width
            if tree.selectedStarts.isEmpty { rememberSelection() }
          }
          .onChange(of: selection) {
            if let selection, !selectedIDs.contains(selection) {
              selectedIDs = [selection]
              tree.selectionAnchor = selection
            }
            rememberSelection()
          }
          .onChange(of: selectedIDs.isEmpty ? [] : visibleEntries.map(\.identity)) {
            reconcileSelection()
          }
          .onChange(of: g.size.width) { availableWidth = g.size.width }
          .onChange(of: metric) { draftWidths = [:] }
      }.background(theme.card).clipShape(
        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
      ).overlay(
        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).stroke(
          theme.border, lineWidth: 1))
    }
  }
  var toolbar: some View {
    HStack(spacing: 9) {
      Text(metric == .energy ? "Applications" : "Processes").font(
        .system(size: 13, weight: .semibold)
      ).foregroundStyle(theme.text)
      Text(
        selectedIDs.count > 1
          ? "\(selectedIDs.count) selected"
          : hierarchy && tree.snapshot.filtered ? processCountLabel : rows.count.formatted()
      ).font(
        .system(size: 10)
      ).foregroundStyle(theme.secondary).padding(
        .horizontal, 6
      ).padding(.vertical, 2).background(theme.subtle, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
        .help(processCountHelp)
      viewModePicker(compact: false)
      Spacer(minLength: 6)
      Menu {
        ForEach(ProcessQuery.filters, id: \.self) {
          item in
          Button {
            filter = item
          } label: {
            if filter == item { Label(item, systemImage: "checkmark") } else { Text(item) }
          }
        }
      } label: {
        HStack(spacing: 14) {
          Text(filter)
          Image(systemName: "chevron.down").font(.system(size: 8))
        }.font(.system(size: 11)).foregroundStyle(theme.secondary).frame(
          width: 128, alignment: .trailing)
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.tertiary)
        TextField("Search processes", text: $query).textFieldStyle(.plain).font(.system(size: 11))
          .foregroundStyle(theme.text).focused(searchFocus)
        if query.isEmpty {
          Text("⌘ K").font(.system(size: 9)).foregroundStyle(theme.tertiary).padding(.horizontal, 4)
            .padding(.vertical, 1).overlay(
              RoundedRectangle(cornerRadius: 3).stroke(theme.border, lineWidth: 1))
        } else {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(
              theme.tertiary)
          }.buttonStyle(.plain)
        }
      }.padding(.horizontal, 10).frame(width: 230, height: 31).background(
        theme.subtle, in: RoundedRectangle(cornerRadius: 7)
      ).overlay(
        RoundedRectangle(cornerRadius: 7).stroke(
          searchFocus.wrappedValue ? theme.blue.opacity(0.65) : theme.border, lineWidth: 1)
      ).padding(
        .leading, 8)
      Rectangle().fill(theme.border).frame(width: 1, height: 18).padding(.horizontal, 3)
      Button {
        if !selectedRows.isEmpty { stopMany(selectedRows) }
      } label: {
        Image(systemName: "xmark.octagon")
      }.buttonStyle(MonitorIconButton(theme: theme)).disabled(!canStop).help(
        "Quit selected process")
      Button {
        inspector.toggle()
      } label: {
        Image(systemName: "info.circle")
      }.buttonStyle(MonitorIconButton(theme: theme, active: inspector)).help("Process details")
      Menu {
        columnMenu
      } label: {
        Image(systemName: "rectangle.split.3x1").font(.system(size: 13)).foregroundStyle(
          theme.secondary
        ).frame(width: 30, height: 32)
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose columns")
    }.padding(.horizontal, 18)
  }
  @ViewBuilder var columnMenu: some View {
    Button("Select all processes") { selectAllRows() }
    Button("Copy selected rows") { copyRows(selectedRows) }.disabled(selectedRows.isEmpty)
    if hierarchy {
      Button("Expand all processes", action: tree.expandAll).disabled(!tree.hasBranches)
      Button("Collapse all processes", action: tree.collapseAll).disabled(!tree.hasBranches)
    }
    Divider()
    Button("Reset column order") {
      var value = orderPreferences
      value.reset(metric)
      columnOrder = value.json
    }
    Button("Fit all columns to contents") {
      var value = ProcessColumnWidths(columnWidths)
      value.set(
        "name", metric: metric,
        width: fittedWidth("name", title: "Process name"))
      for column in columns {
        value.set(
          column.id, metric: metric,
          width: fittedWidth(column.id, title: column.title))
      }
      columnWidths = value.json
    }
    Button("Reset column widths") {
      var value = ProcessColumnWidths(columnWidths)
      value.reset(metric)
      columnWidths = value.json
      draftWidths = [:]
    }
    Toggle("Show all enabled columns at narrow widths", isOn: $allColumnsVisible)
    Divider()
    ForEach(ProcessColumns.available(metric)) { column in
      Toggle(
        column.title,
        isOn: Binding(
          get: {
            preferences.isVisible(
              column.id, metric: metric, showTime: showTime,
              showThreads: showThreads, showUser: showUser)
          },
          set: { enabled in
            var value = preferences
            value.set(column.id, metric: metric, visible: enabled)
            columnVisibility = value.json
            if !enabled && sort == column.id {
              sort = metric == .network ? "received" : "primary"
            }
          }
        )
      ).help(ProcessColumns.unavailableReason(column.id) ?? "Show or hide \(column.title)")
    }
    Divider()
    Button("Restore columns") {
      var value = preferences
      value.restore(metric)
      columnVisibility = value.json
      allColumnsVisible = false
      sort = metric == .network ? "received" : "primary"
      descending = true
    }
    Text("— means the metric is unavailable.")
    if hierarchy { Text(ProcessSubtreeUsage.menuScopeHelp) }
  }
  var compactToolbar: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Text(selectedIDs.count > 1 ? "\(selectedIDs.count) selected" : processCountLabel)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1).help(processCountHelp)
        viewModePicker(compact: true)
        Spacer(minLength: 0)
        Menu {
          Picker("Process filter", selection: $filter) {
            ForEach(
              ProcessQuery.filters, id: \.self
            ) { Text($0).tag($0) }
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton).fixedSize().help("Filter: \(filter)")
        Menu {
          Button("Process name") {
            sort = "name"
            descending = false
          }
          ForEach(allColumns.filter { !unavailableColumn($0.id) }) { column in
            Button(column.title) {
              sort = column.id
              descending = true
            }
          }
          Divider()
          Toggle("Descending", isOn: $descending)
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton).fixedSize().help("Sort processes")
        Menu {
          columnMenu
        } label: {
          Image(systemName: "rectangle.split.3x1")
        }
        .menuStyle(.borderlessButton).fixedSize().help("Choose columns")
      }
      HStack(spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").foregroundStyle(theme.tertiary)
          TextField("Search processes", text: $query).textFieldStyle(.plain).focused(searchFocus)
          if !query.isEmpty {
            Button {
              query = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).help("Clear search")
          }
        }.font(.system(size: 11)).padding(.horizontal, 9).frame(height: 30)
          .background(theme.subtle, in: RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(
              searchFocus.wrappedValue ? theme.blue : theme.border, lineWidth: 1))
        Button {
          if !selectedRows.isEmpty { stopMany(selectedRows) }
        } label: {
          Image(systemName: "xmark.octagon")
        }
        .buttonStyle(MonitorIconButton(theme: theme)).disabled(!canStop).help(
          "Quit selected process")
        Button {
          inspector.toggle()
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(MonitorIconButton(theme: theme, active: inspector)).help("Process details")
      }
    }.padding(.horizontal, 14)
  }
  var canStop: Bool {
    !selectedRows.isEmpty
      && selectedRows.allSatisfy { $0.uid == getuid() && $0.id > 1 && $0.id != getpid() }
  }
  func moveColumn(_ key: String, to target: String) {
    var value = orderPreferences
    value.move(key, to: target, metric: metric)
    columnOrder = value.json
  }
  func resizeColumn(_ key: String, width: CGFloat, finished: Bool) {
    var value = widthPreferences
    value.resize(
      key, metric: metric, columns: columns, viewport: viewportWidth ?? availableWidth, to: width)
    if finished {
      columnWidths = value.json
      draftWidths = [:]
    } else {
      draftWidths = (value.values[metric.rawValue] ?? [:]).mapValues { CGFloat($0) }
    }
  }
  func resetColumnWidth(_ key: String) {
    var value = ProcessColumnWidths(columnWidths)
    value.set(key, metric: metric, width: nil)
    columnWidths = value.json
  }
  func resizeHandle(_ key: String, title: String, width: CGFloat) -> some View {
    ProcessColumnResizeHandle(
      title: title, width: width, theme: theme,
      resize: { resizeColumn(key, width: $0, finished: $1) },
      fit: {
        resizeColumn(
          key,
          width: fittedWidth(key, title: title),
          finished: true)
      },
      reset: { resetColumnWidth(key) })
  }
  func header(_ layout: ProcessColumnLayout, columns: [ProcessColumn]) -> some View {
    HStack(spacing: 0) {
      ForEach(layout.order, id: \.self) { key in
        let title =
          key == "name"
          ? (metric == .energy ? "App name" : "Process name")
          : columns.first { $0.id == key }?.title ?? key
        let width = layout.width(key)
        headerButton(title, key, alignment: key == "user" || key == "name" ? .leading : .trailing)
          .frame(width: width)
          .modifier(ProcessHeaderReorder(key: key, layout: layout, move: moveColumn))
          .contextMenu {
            Button("Fit column to contents") {
              resizeColumn(
                key,
                width: fittedWidth(key, title: title), finished: true)
            }
            Button("Reset column width") { resetColumnWidth(key) }
            if let index = layout.order.firstIndex(of: key) {
              Button("Move column left") { moveColumn(key, to: layout.order[index - 1]) }.disabled(
                index == 0)
              Button("Move column right") { moveColumn(key, to: layout.order[index + 1]) }.disabled(
                index == layout.order.count - 1)
            }
          }
          .overlay(alignment: .trailing) { resizeHandle(key, title: title, width: width) }
      }
      Spacer(minLength: 0)
    }.frame(width: layout.total)
  }
  func headerButton(_ title: String, _ key: String, alignment: Alignment) -> some View {
    Button {
      if sort == key {
        descending.toggle()
      } else {
        sort = key
        descending = key != "name" && key != "user"
      }
    } label: {
      HStack(spacing: 5) {
        Text(title).lineLimit(1)
        if sort == key {
          Image(systemName: descending ? "chevron.down" : "chevron.up").font(.system(size: 7))
        }
      }.font(.system(size: 10, weight: sort == key ? .semibold : .regular)).foregroundStyle(
        sort == key ? theme.text : theme.secondary
      ).frame(maxWidth: .infinity, alignment: alignment).padding(.horizontal, 10)
        .frame(height: 36).contentShape(Rectangle())
    }.buttonStyle(MonitorSegmentButton(theme: theme, radius: 0))
      .help(headerHelp(title, key))
      .accessibilityLabel(
        hierarchy && ProcessUsageMetric.resolve(key, metric: metric) != nil
          ? "Subtree " + title.replacingOccurrences(of: "Σ ", with: "") : title
      )
      .disabled(unavailableColumn(key))
  }
  func headerHelp(_ title: String, _ key: String) -> String {
    if let reason = ProcessColumns.unavailableReason(key) { return reason }
    if hierarchy, let counter = ProcessUsageMetric.resolve(key, metric: metric) {
      return "Sort by subtree usage. " + counter.help + "\n" + ProcessSubtreeUsage.scopeHelp
    }
    switch ProcessColumns.canonical(key, metric: metric) {
    case "gpuTime": return "Sort by GPU execution time observed during this session"
    case "gpu":
      return
        "Sort by GPU execution-time rate across all reporting devices; overlapping work can exceed 100%"
    case "cpu": return "Sort by CPU execution-time rate. " + CPUAccounting.processHelp
    default: return "Sort by \(title)"
    }
  }
  func unavailableColumn(_ key: String) -> Bool {
    ProcessColumns.unavailableReason(key) != nil
  }
  var processCountHelp: String {
    hierarchy
      ? "\(rows.count) matching processes, \(tree.contextCount) ancestors for context, \(entries.count) visible rows. "
        + ProcessSubtreeUsage.scopeHelp
      : "\(rows.count) matching processes"
  }
  var processCountLabel: String {
    if hierarchy && tree.snapshot.filtered {
      return "\(rows.count) \(rows.count == 1 ? "match" : "matches")"
    }
    return "\(rows.count) \(rows.count == 1 ? "process" : "processes")"
  }
  func viewModePicker(compact: Bool) -> some View {
    ProcessViewModePicker(mode: $mode, theme: theme, compact: compact)
      .contextMenu {
        Button("Expand all processes", action: tree.expandAll).disabled(
          !hierarchy || !tree.hasBranches)
        Button("Collapse all processes", action: tree.collapseAll).disabled(
          !hierarchy || !tree.hasBranches)
      }
  }
  func fittedWidth(_ key: String, title: String) -> CGFloat {
    if hierarchy && key == "name" {
      return ProcessTreeGeometry.fittedNameWidth(tree.snapshot.entries)
    }
    return ProcessColumnLayout.fitted(
      key: key, title: title, metric: metric, rows: displayRows,
      usage: hierarchy ? tree.snapshot.usageByID : nil)
  }
  func reconcileSelection() {
    let current = ProcessListSelection(
      ids: selectedIDs, anchor: tree.selectionAnchor, lead: selection)
    applySelection(
      tree.reconcile(current, visible: entries, source: sourceRows, hierarchical: hierarchy))
  }
  func selectOnly(_ id: Int32) {
    applySelection(ProcessListSelection(ids: [id], anchor: id, lead: id))
    focused = true
  }
  func rememberSelection() {
    tree.selectedStarts = Dictionary(
      sourceRows.filter { selectedIDs.contains($0.id) }.map { ($0.id, $0.start) },
      uniquingKeysWith: { first, _ in first })
  }
  func selectRow(_ id: Int32) {
    var value = ProcessListSelection(
      ids: selectedIDs, anchor: tree.selectionAnchor, lead: selection)
    let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    value.select(
      id, order: displayRows.map(\.id), extending: modifiers.contains(.shift),
      toggling: modifiers.contains(.command))
    applySelection(value)
    focused = true
  }
  func applySelection(_ value: ProcessListSelection) {
    selectedIDs = value.ids
    tree.selectionAnchor = value.anchor
    selection = value.lead
    rememberSelection()
  }
  func move(_ delta: Int, extending: Bool = false) {
    var value = ProcessListSelection(
      ids: selectedIDs, anchor: tree.selectionAnchor, lead: selection)
    value.move(delta, order: displayRows.map(\.id), extending: extending)
    applySelection(value)
  }
  func selectAllRows() {
    selectedIDs = Set(displayRows.map(\.id))
    if selection == nil { selection = displayRows.first?.id }
    tree.selectionAnchor = displayRows.first?.id
    rememberSelection()
  }
  func copyRows(_ values: [ProcessRow]) {
    guard !values.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      processClipboard(
        values, keys: orderedKeys, metric: metric,
        usage: hierarchy ? tree.snapshot.usageByID : nil), forType: .string)
  }

}

private struct ProcessTableRow: View, Equatable {
  let row: ProcessRow
  let index: Int
  let layout: ProcessColumnLayout
  let metric: Metric
  let theme: MonitorTheme
  let columns: [ProcessColumn]
  let selectedSet: Set<Int32>
  let hierarchical: Bool
  let depth: Int
  let hasChildren: Bool
  let expanded: Bool
  let isContext: Bool
  let parentID: Int32?
  let parentName: String?
  let usage: ProcessSubtreeUsage?
  let toggleExpanded: () -> Void
  let expandBranch: () -> Void
  let collapseBranch: () -> Void
  let selectParent: () -> Void
  let isSelected: Bool
  let select: () -> Void
  let inspect: (ProcessRow) -> Void
  let stop: (ProcessRow) -> Void
  let copy: () -> Void
  let stopSelection: () -> Void
  let canStopSelection: Bool
  var diagnose: ((ProcessRow, Bool) -> Void)? = nil
  @State private var hovered = false
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.row == rhs.row && lhs.index == rhs.index && lhs.layout == rhs.layout
      && lhs.metric == rhs.metric && lhs.theme.dark == rhs.theme.dark
      && lhs.columns == rhs.columns && lhs.isSelected == rhs.isSelected
      && lhs.hierarchical == rhs.hierarchical && lhs.selectedSet == rhs.selectedSet
      && lhs.depth == rhs.depth && lhs.hasChildren == rhs.hasChildren
      && lhs.expanded == rhs.expanded && lhs.canStopSelection == rhs.canStopSelection
      && lhs.isContext == rhs.isContext && lhs.parentID == rhs.parentID
      && lhs.parentName == rhs.parentName
      && lhs.usage == rhs.usage
  }
  private var indentation: CGFloat {
    hierarchical ? ProcessTreeGeometry.indentation(depth: depth, width: layout.name) : 0
  }
  var body: some View {
    Group {
      if hierarchical {
        ZStack(alignment: .leading) {
          rowButton.accessibilityActions {
            if hasChildren {
              Button(expanded ? "Collapse branch" : "Expand branch", action: toggleExpanded)
            }
            if parentID != nil { Button("Select parent", action: selectParent) }
          }
          if hasChildren {
            Button(action: toggleExpanded) {
              Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.secondary)
                .frame(width: 20, height: 29).contentShape(Rectangle())
            }.buttonStyle(MonitorSegmentButton(theme: theme, radius: 4))
              .offset(x: layout.offset("name") + 13 + indentation)
              .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(row.name)")
              .accessibilityIdentifier("process-disclosure-\(row.id)")
              .help(
                "\(expanded ? "Collapse" : "Expand") branch. Option-click includes all descendants."
              )
          }
        }.frame(width: layout.total, height: 41).accessibilityElement(children: .contain)
      } else {
        rowButton
      }
    }
    .onHover { hovered = $0 }
    .contextMenu {
      Button("Inspect") { inspect(row) }
      if let diagnose {
        Button("Process diagnostics…") { diagnose(row, false) }
        Button("Open in tool window") { diagnose(row, true) }
      }
      if hierarchical {
        Divider()
        Button("Expand subtree", action: expandBranch).disabled(!hasChildren)
        Button("Collapse subtree", action: collapseBranch).disabled(!hasChildren)
        Button("Select parent", action: selectParent).disabled(parentID == nil)
        Divider()
      }
      Button("Copy selected rows", action: copy)
      Button("Quit selected processes…", role: .destructive, action: stopSelection).disabled(
        !canStopSelection)
      Divider()
      Button("Copy PID") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(row.id), forType: .string)
      }
      Button("Quit…", role: .destructive) { stop(row) }.disabled(
        row.uid != getuid() || row.id <= 1 || row.id == getpid())
    }
  }
  private var rowButton: some View {
    Button {
      select()
    } label: {
      ZStack(alignment: .leading) {
        metricCells.frame(width: layout.total, height: 41)
        ProcessTableNameCell(
          pid: row.id, start: row.start, name: row.name, isApp: row.isApp,
          dark: theme.dark, hierarchical: hierarchical, hasChildren: hasChildren,
          isContext: isContext, subtreeCount: usage?.processCount ?? 1,
          indentation: indentation, width: layout.name
        ).equatable().offset(x: layout.offset("name"))
      }.frame(height: 41).background(
        isSelected
          ? theme.selected
          : hovered ? theme.hover : index % 2 == 1 ? theme.stripe : Color.clear
      ).overlay(alignment: .leading) {
        if isSelected { Rectangle().fill(theme.blue).frame(width: 2) }
      }.overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
        .contentShape(Rectangle())
    }.buttonStyle(.plain).focusEffectDisabled().help(rowHelp)
      .simultaneousGesture(TapGesture(count: 2).onEnded { inspect(row) })
      .accessibilityAddTraits(isSelected ? .isSelected : []).accessibilityLabel(
        "\(row.name), PID \(row.id)"
      ).accessibilityValue(accessibleValues)
      .accessibilityAction(named: "Inspect") { inspect(row) }
  }
  private var rowHelp: String {
    [
      row.name, row.executableName.map { "Executable: " + $0 },
      hierarchical ? parentDescription : nil,
      isContext ? "Ancestor shown for context; does not match the current filter." : nil,
      usageDescription,
      row.gpuAvailability,
    ]
    .compactMap { $0 }.joined(separator: "\n")
  }
  private var usageDescription: String? {
    guard let usage else { return nil }
    let values = columns.compactMap { column -> String? in
      guard let counter = ProcessUsageMetric.resolve(column.id, metric: metric) else { return nil }
      let title = column.title.replacingOccurrences(of: "Σ ", with: "")
      return title + ": own " + ProcessValues.text(row, key: column.id, metric: metric)
        + "; subtree " + ProcessValues.text(row, key: column.id, metric: metric, usage: usage)
        + " (" + usage.coverage(counter) + ")"
    }
    return ([usage.description] + values).joined(separator: "\n")
  }
  private var parentDescription: String {
    if let parentID {
      return "Parent: \(parentName ?? "Process") (PID \(parentID)). Level \(depth + 1)."
    }
    return "Root process. Level 1."
  }
  private var accessibleValues: String {
    let values = columns.map { column in
      let value = ProcessValues.text(row, key: column.id, metric: metric, usage: usage)
      if let usage, let counter = ProcessUsageMetric.resolve(column.id, metric: metric) {
        return "Subtree " + column.title.replacingOccurrences(of: "Σ ", with: "") + ": "
          + value + " (" + usage.coverage(counter) + ")"
      }
      return column.title + ": " + value
    }.joined(separator: ", ")
    guard hierarchical else { return values }
    return parentDescription + (hasChildren ? (expanded ? " Expanded. " : " Collapsed. ") : " ")
      + (isContext ? "Ancestor context. " : "")
      + (usage.map { "Subtree contains \($0.processCount) processes. " } ?? "") + values
  }
  private var metricCells: some View {
    Canvas { context, size in
      context.withCGContext { cg in
        ProcessMetricDrawing.draw(
          row: row, columns: columns, layout: layout, metric: metric, theme: theme,
          usage: usage, in: cg)
      }
    }.accessibilityHidden(true)
  }
  func text(_ p: ProcessRow, _ key: String) -> String {
    ProcessValues.text(p, key: key, metric: metric)
  }
}

/// Telemetry changes do not invalidate the process icon, name or ancestry label.
private struct ProcessTableNameCell: View, Equatable {
  let pid: Int32
  let start: UInt64
  let name: String
  let isApp: Bool
  let dark: Bool
  let hierarchical: Bool
  let hasChildren: Bool
  let isContext: Bool
  let subtreeCount: Int
  let indentation: CGFloat
  let width: CGFloat
  var body: some View {
    let theme = MonitorTheme(dark: dark)
    HStack(spacing: 10) {
      if hierarchical { Color.clear.frame(width: 12, height: 30) }
      ProcessIcon(pid: pid, isApp: isApp, start: start).frame(width: 24, height: 24)
      Text(name).font(
        .system(size: 12, weight: hierarchical && hasChildren ? .medium : .regular)
      ).foregroundStyle(isContext ? theme.secondary : theme.text).lineLimit(1)
        .truncationMode(.middle)
      if subtreeCount > 1 && width > 240 {
        Text("Σ \(subtreeCount)").font(.system(size: 9)).foregroundStyle(theme.secondary)
          .fixedSize().padding(.horizontal, 5).padding(.vertical, 2)
          .background(theme.subtle, in: RoundedRectangle(cornerRadius: 3))
          .accessibilityLabel("Subtree contains \(subtreeCount) processes")
      }
      if isContext && width > 280 {
        Text("Parent").font(.system(size: 9)).foregroundStyle(theme.secondary)
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(theme.subtle, in: RoundedRectangle(cornerRadius: 3))
      }
    }.padding(.leading, 17 + indentation).padding(.trailing, 17)
      .frame(width: width, alignment: .leading).clipped()
  }
}

/// Retain the selected sort column so resizing never hides the meaning of the current ordering.
enum ProcessColumnPolicy {
  static func visible(_ columns: [ProcessColumn], metric: Metric, width: CGFloat, sort: String)
    -> [ProcessColumn]
  {
    let budget = max(0, width - ProcessColumnLayout.nameMinimum(width))
    let minimum = Dictionary(
      uniqueKeysWithValues: columns.map { ($0.id, ProcessColumnLayout.minimum($0, metric: metric)) }
    )
    if minimum.values.reduce(0, +) <= budget { return columns }
    let primary = metric == .network ? "received" : "primary"
    var keys = Set([minimum[sort] != nil ? sort : primary].filter { minimum[$0] != nil })
    var used = keys.reduce(CGFloat(0)) { $0 + (minimum[$1] ?? 0) }
    if let primaryWidth = minimum[primary], !keys.contains(primary), used + primaryWidth <= budget {
      keys.insert(primary)
      used += primaryWidth
    }
    if let pidWidth = minimum["pid"], !keys.contains("pid"), used + pidWidth <= budget {
      keys.insert("pid")
      used += pidWidth
    }
    let priorities: [String]
    switch metric {
    case .gpu: priorities = ["gpuTime", "memory", "cpu", "kind", "user"]
    case .network: priorities = ["sent", "packetsIn", "packetsOut", "user"]
    case .disk: priorities = ["secondary", "user"]
    case .energy: priorities = ["time", "sleep", "nap", "user"]
    default:
      priorities = ["memory", "time", "threads", "ports", "kind", "gpu", "cpu", "resident", "user"]
    }
    for key in priorities + columns.map(\.id) where !keys.contains(key) {
      guard let cost = minimum[key], used + cost <= budget else { continue }
      keys.insert(key)
      used += cost
    }
    return columns.filter { keys.contains($0.id) }
  }
}
