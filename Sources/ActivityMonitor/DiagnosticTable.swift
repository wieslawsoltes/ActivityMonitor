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
    let scroll = NSScrollView()
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
    table.rowHeight = 28
    table.intercellSpacing = NSSize(width: 12, height: 0)
    table.usesAlternatingRowBackgroundColors = true
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
    scroll.documentView = table
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let c = context.coordinator
    let table = c.table!
    if c.key != key || c.columns != section.columns {
      c.key = key
      c.columns = section.columns
      table.autosaveTableColumns = false
      for column in table.tableColumns { table.removeTableColumn(column) }
      for title in section.columns {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
        column.title = title
        column.minWidth = 55
        column.maxWidth = 2400
        column.width =
          ["Path", "Local endpoint", "Remote endpoint", "Name"].contains(title)
          ? 280 : max(90, CGFloat(title.count) * 7 + 26)
        column.resizingMask = .userResizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(key: title, ascending: true)
        table.addTableColumn(column)
      }
      if persistColumns {
        table.autosaveName = "ProcessDiagnostics.\(key).v1"
        table.autosaveTableColumns = true
      }
      let menu = NSMenu()
      for column in table.tableColumns {
        let item = NSMenuItem(
          title: column.title, action: #selector(Coordinator.toggleColumn(_:)), keyEquivalent: "")
        item.target = c
        item.representedObject = column
        item.state = column.isHidden ? .off : .on
        menu.addItem(item)
      }
      table.headerView?.menu = menu
      c.date = nil
    }
    table.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
    table.backgroundColor = NSColor(theme.card)
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
    weak var table: NSTableView?
    var key = "", columns: [String] = [], source: [DiagnosticRecord] = [],
      rows: [DiagnosticRecord] = []
    var query = "", date: Date?
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
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
      -> NSView?
    {
      guard rows.indices.contains(row), let column = tableColumn else { return nil }
      let identifier = NSUserInterfaceItemIdentifier("diagnostic-cell")
      let field =
        tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
        ?? NSTextField(labelWithString: "")
      field.identifier = identifier
      field.font = .systemFont(ofSize: 12)
      field.lineBreakMode = .byTruncatingMiddle
      field.stringValue = rows[row].cells[column.title] ?? "—"
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
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
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
