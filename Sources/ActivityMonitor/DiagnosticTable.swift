import AppKit
import SwiftUI

/// A single native scroll view keeps both scrollbars on the viewport. AppKit supplies
/// resizing, reordering, multi-selection, keyboard navigation, and reusable row cells.
struct DiagnosticTable: NSViewRepresentable {
  let section: DiagnosticSection
  let query: String
  let key: String
  let theme: MonitorTheme
  var persistColumns = true
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = DiagnosticScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    let table = CopyingDiagnosticTable()
    table.identifier = NSUserInterfaceItemIdentifier("process-diagnostic-table")
    table.delegate = context.coordinator
    table.dataSource = context.coordinator
    table.allowsMultipleSelection = true
    table.allowsColumnReordering = true
    table.allowsColumnResizing = true
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.rowHeight = 34
    table.intercellSpacing = NSSize(width: 12, height: 0)
    table.usesAlternatingRowBackgroundColors = false
    table.style = .plain
    table.copyRows = { [weak coordinator = context.coordinator] in coordinator?.copyRows() }
    let menu = NSMenu()
    for (title, action) in [
      ("Copy selected rows", #selector(Coordinator.copyRows)),
      ("Reveal in Finder", #selector(Coordinator.reveal)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = context.coordinator
      menu.addItem(item)
    }
    table.menu = menu
    context.coordinator.table = table
    scroll.fitColumns = { [weak coordinator = context.coordinator] in coordinator?.fitColumns() }
    scroll.documentView = table
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let c = context.coordinator
    let table = c.table!
    let themeChanged = c.theme.dark != theme.dark
    c.theme = theme
    if c.key != key || c.columns != section.columns {
      c.key = key
      c.columns = section.columns
      c.adjustingColumns = true
      c.persistColumns = persistColumns
      c.automaticSizing = true
      table.autosaveTableColumns = false
      for column in table.tableColumns { table.removeTableColumn(column) }
      for title in section.columns {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
        column.title = title
        column.minWidth = DiagnosticColumnLayout.minimum(title)
        column.maxWidth = 2400
        column.width =
          ["Path", "Local endpoint", "Remote endpoint", "Name"].contains(title)
          ? 280 : max(90, CGFloat(title.count) * 7 + 26)
        column.headerCell.alignment = DiagnosticColumnLayout.numeric(title) ? .right : .left
        column.resizingMask = .userResizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(key: title, ascending: true)
        table.addTableColumn(column)
      }
      let initialWidths = Dictionary(
        uniqueKeysWithValues: table.tableColumns.map { ($0.title, $0.width) })
      if persistColumns {
        table.autosaveName = "ProcessDiagnostics.\(key).v1"
        table.autosaveTableColumns = true
      }
      // Preserve an existing customized native layout. Untouched legacy layouts
      // migrate to the compact defaults instead of restoring every metadata column.
      let customized =
        table.tableColumns.map { $0.title } != section.columns
        || table.tableColumns.contains { column in
          return column.isHidden
            || abs(column.width - (initialWidths[column.title] ?? column.width)) > 1
        }
      let savedMode =
        persistColumns ? UserDefaults.standard.object(forKey: c.sizingKey) as? Bool : nil
      c.automaticSizing = savedMode ?? !customized
      if savedMode == nil && !customized { c.applyDefaults() }
      let menu = NSMenu()
      for column in table.tableColumns {
        let item = NSMenuItem(
          title: column.title, action: #selector(Coordinator.toggleColumn(_:)), keyEquivalent: "")
        item.target = c
        item.representedObject = column
        item.state = column.isHidden ? .off : .on
        menu.addItem(item)
      }
      menu.addItem(.separator())
      for (title, action) in [
        ("Fit columns to window", #selector(Coordinator.fitToWindow)),
        ("Restore default columns", #selector(Coordinator.restoreDefaults)),
      ] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = c
        menu.addItem(item)
      }
      table.headerView?.menu = menu
      c.adjustingColumns = false
      c.fitColumns()
      c.saveSizing()
      c.date = nil
    }
    table.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
    table.backgroundColor = NSColor(theme.card)
    scroll.backgroundColor = NSColor(theme.card)
    if themeChanged { table.reloadData() }
    if c.date != section.date || c.query != query || c.source != section.records {
      let selected = Set(
        table.selectedRowIndexes.compactMap { c.rows.indices.contains($0) ? c.rows[$0].id : nil })
      c.source = section.records
      c.query = query
      c.date = section.date
      c.refresh()
      table.selectRowIndexes(
        IndexSet(c.rows.indices.filter { selected.contains(c.rows[$0].id) }),
        byExtendingSelection: false)
    }
  }
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSMenuItemValidation
  {
    var theme = MonitorTheme(dark: false)
    weak var table: NSTableView?
    var key = "", columns: [String] = [], source: [DiagnosticRecord] = [],
      rows: [DiagnosticRecord] = []
    var query = "", date: Date?
    var adjustingColumns = false, automaticSizing = true, persistColumns = true
    var sizingKey: String { "ProcessDiagnostics.\(key).automaticSizing" }
    func saveSizing() {
      if persistColumns { UserDefaults.standard.set(automaticSizing, forKey: sizingKey) }
    }
    func applyDefaults() {
      guard let table else { return }
      let defaults = DiagnosticColumnLayout.defaults(key)
      for column in table.tableColumns {
        column.isHidden = defaults.map { !$0.contains(column.title) } ?? false
      }
      // Unknown or partial schemas must always leave at least one column visible.
      if table.tableColumns.allSatisfy(\.isHidden) { table.tableColumns.first?.isHidden = false }
    }
    @objc func restoreDefaults() {
      guard let table else { return }
      adjustingColumns = true
      for (index, title) in columns.enumerated() {
        let current = table.column(withIdentifier: NSUserInterfaceItemIdentifier(title))
        if current >= 0 && current != index { table.moveColumn(current, toColumn: index) }
      }
      applyDefaults()
      adjustingColumns = false
      fitToWindow()
    }
    @objc func fitToWindow() {
      automaticSizing = true
      saveSizing()
      fitColumns()
    }
    func fitColumns() {
      guard automaticSizing, !adjustingColumns, let table,
        let scroll = table.enclosingScrollView, scroll.contentSize.width > 0
      else { return }
      adjustingColumns = true
      defer { adjustingColumns = false }
      let visible = table.tableColumns.filter { !$0.isHidden }
      let available = max(
        0, scroll.contentSize.width - CGFloat(visible.count) * table.intercellSpacing.width)
      let minima = visible.map { DiagnosticColumnLayout.minimum($0.title) }
      let surplus = max(0, available - minima.reduce(0, +))
      let weights = visible.map { DiagnosticColumnLayout.flexible($0.title) ? 5.0 : 1.0 }
      let totalWeight = max(1, weights.reduce(0, +))
      for index in visible.indices {
        visible[index].width = minima[index] + surplus * weights[index] / totalWeight
      }
      table.sizeToFit()
      let contentWidth = visible.reduce(CGFloat.zero) {
        $0 + $1.width + table.intercellSpacing.width
      }
      table.setFrameSize(
        NSSize(width: max(scroll.contentSize.width, contentWidth), height: table.frame.height))
    }
    func tableViewColumnDidResize(_ notification: Notification) {
      guard !adjustingColumns else { return }
      automaticSizing = false
      saveSizing()
    }
    func refresh() {
      let selection = Set(
        table?.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil } ?? []
      )
      rows = source.filter { row in
        query.isEmpty || row.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
      }
      if let descriptor = table?.sortDescriptors.first, let key = descriptor.key {
        rows.sort { a, b in
          let comparison: ComparisonResult
          if let av = a.numbers[key], let bv = b.numbers[key] {
            comparison = av == bv ? .orderedSame : av < bv ? .orderedAscending : .orderedDescending
          } else {
            comparison = (a.cells[key] ?? "").localizedStandardCompare(b.cells[key] ?? "")
          }
          if comparison == .orderedSame {
            return a.id.localizedStandardCompare(b.id) == .orderedAscending
          }
          return descriptor.ascending
            ? comparison == .orderedAscending : comparison == .orderedDescending
        }
      }
      table?.reloadData()
      table?.selectRowIndexes(
        IndexSet(rows.indices.filter { selection.contains(rows[$0].id) }),
        byExtendingSelection: false)
    }
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
      let title = tableView.tableColumns[column].title
      let font = NSFont.systemFont(ofSize: 12)
      let values = [title] + rows.prefix(1024).map { $0.cells[title] ?? "" }
      return min(
        1200,
        max(
          70,
          values.map { ($0 as NSString).size(withAttributes: [.font: font]).width + 24 }.max() ?? 90
        ))
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      let view = DiagnosticRowView()
      view.theme = theme
      view.alternate = row % 2 == 1
      return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard rows.indices.contains(row), let column = tableColumn else { return nil }
      let identifier = NSUserInterfaceItemIdentifier("diagnostic-cell")
      let field =
        tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
        ?? NSTextField(labelWithString: "")
      field.identifier = identifier
      let numeric = DiagnosticColumnLayout.numeric(column.title)
      field.font =
        numeric
        ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        : .systemFont(ofSize: 12)
      field.alignment = numeric ? .right : .left
      field.textColor = NSColor(theme.text)
      field.lineBreakMode =
        DiagnosticColumnLayout.flexible(column.title) ? .byTruncatingMiddle : .byTruncatingTail
      let value = rows[row].cells[column.title] ?? ""
      field.stringValue = value.isEmpty ? "—" : value
      field.toolTip = field.stringValue
      field.setAccessibilityLabel(column.title + ": " + field.stringValue)
      return field
    }
    func tableView(
      _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) { refresh() }
    private var selected: [DiagnosticRecord] {
      guard let table else { return [] }
      let indexes =
        table.clickedRow >= 0 && !table.selectedRowIndexes.contains(table.clickedRow)
        ? IndexSet(integer: table.clickedRow) : table.selectedRowIndexes
      return indexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
    }
    @objc func copyRows() {
      guard let table else { return }
      let columns = table.tableColumns.filter { !$0.isHidden }.map(\.title)
      let text =
        ([columns.joined(separator: "\t")]
        + selected.map { row in columns.map { row.cells[$0] ?? "" }.joined(separator: "\t") })
        .joined(separator: "\n")
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    }
    @objc func reveal() {
      let urls = selected.compactMap(\.path).map { URL(fileURLWithPath: $0) }
      if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    @objc func toggleColumn(_ sender: NSMenuItem) {
      guard let column = sender.representedObject as? NSTableColumn,
        column.isHidden || (table?.tableColumns.filter { !$0.isHidden }.count ?? 0) > 1
      else { return }
      column.isHidden.toggle()
      sender.state = column.isHidden ? .off : .on
      fitColumns()
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
      if let column = item.representedObject as? NSTableColumn {
        item.state = column.isHidden ? .off : .on
        return column.isHidden || (table?.tableColumns.filter { !$0.isHidden }.count ?? 0) > 1
      }
      if item.action == #selector(reveal) { return selected.contains { $0.path != nil } }
      if item.action == #selector(copyRows) { return !selected.isEmpty }
      return true
    }
  }
}
private final class CopyingDiagnosticTable: NSTableView {
  var copyRows: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
      && event.charactersIgnoringModifiers == "c"
    {
      copyRows?()
    } else {
      super.keyDown(with: event)
    }
  }
}

private final class DiagnosticRowView: NSTableRowView {
  var theme = MonitorTheme(dark: false)
  var alternate = false
  override func drawBackground(in dirtyRect: NSRect) {
    NSColor(alternate ? theme.subtle : theme.card).setFill()
    dirtyRect.fill()
    NSColor(theme.separator).setFill()
    NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
  }
  override func drawSelection(in dirtyRect: NSRect) {
    NSColor(theme.selected).setFill()
    bounds.fill()
    NSColor(theme.blue).setFill()
    NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
  }
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

/// Column policies keep the initial diagnostic tables readable at the minimum window
/// width. All source fields remain available for searching, export and customization.
enum DiagnosticColumnLayout {
  static func defaults(_ key: String) -> Set<String>? {
    switch key {
    case "Threads": return ["Thread ID", "Name", "CPU %", "User time", "State"]
    case "Open files": return ["FD", "Type", "Path", "Size"]
    case "Connections": return ["FD", "Protocol", "Local endpoint", "Remote endpoint", "State"]
    case "Memory map": return ["Address", "Size", "Resident", "Path"]
    case "Mapped images": return ["Path", "Size", "Resident"]
    case "Mach ports": return ["Name", "Rights"]
    case "Fileports": return ["Port name", "Descriptor type"]
    default: return nil
    }
  }
  static func flexible(_ title: String) -> Bool {
    ["Path", "Name", "Local endpoint", "Remote endpoint", "Rights"].contains(title)
  }
  static func numeric(_ title: String) -> Bool {
    [
      "FD", "Thread ID", "CPU %", "User time", "System time", "Size", "Resident",
      "Private resident", "Shared resident", "Swapped", "Dirty", "Offset", "Inode",
      "Priority", "Base priority", "Max priority", "Sleep seconds", "References",
      "Receive queue", "Send queue",
    ].contains(title)
  }
  static func minimum(_ title: String) -> CGFloat {
    switch title {
    case "FD": return 30
    case "CPU %": return 52
    case "Thread ID": return 72
    case "Address", "Thread handle": return 140
    case "Path": return 120
    case "Local endpoint", "Remote endpoint": return 100
    case "Name", "Rights": return 90
    case "Size", "Resident", "User time", "System time": return 72
    case "Protocol", "Type": return 60
    case "State": return 78
    default: return max(65, CGFloat(title.count) * 6 + 16)
    }
  }
}

private final class DiagnosticScrollView: NSScrollView {
  var fitColumns: (() -> Void)?
  override func layout() {
    super.layout()
    fitColumns?()
  }
}
