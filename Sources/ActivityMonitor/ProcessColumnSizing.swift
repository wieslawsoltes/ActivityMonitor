import AppKit
import SwiftUI

/// Point widths are independent of window size and isolated by perspective.
struct ProcessColumnWidths {
  var values: [String: [String: Double]]
  init(_ json: String = "{}") {
    values =
      (try? JSONDecoder().decode([String: [String: Double]].self, from: Data(json.utf8))) ?? [:]
  }
  var json: String { (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "{}" }
  func width(_ key: String, metric: Metric) -> CGFloat? {
    guard let value = values[metric.rawValue]?[key], value.isFinite else { return nil }
    return Self.clamp(value, key: key)
  }
  static func clamp(_ width: CGFloat, key: String) -> CGFloat {
    min(1200, max(key == "name" ? 140 : 60, width.isFinite ? width : 100))
  }
  mutating func set(_ key: String, metric: Metric, width: CGFloat?) {
    values[metric.rawValue, default: [:]][key] = width.map { Double(Self.clamp($0, key: key)) }
  }
  mutating func resize(
    _ key: String, metric: Metric, columns: [ProcessColumn], viewport: CGFloat, to width: CGFloat
  ) {
    // Freeze the current fitted widths on the first manual resize so neighboring
    // columns do not spring back to their preferred sizes during a divider drag.
    let current = ProcessColumnLayout(
      viewport: viewport, metric: metric, columns: columns, saved: self)
    for columnKey in current.order where self.width(columnKey, metric: metric) == nil {
      set(columnKey, metric: metric, width: current.width(columnKey))
    }
    set(key, metric: metric, width: width)
  }
  mutating func reset(_ metric: Metric) { values[metric.rawValue] = nil }
}

struct ProcessColumnLayout: Equatable {
  let name: CGFloat
  let widths: [String: CGFloat]
  let total: CGFloat
  let order: [String]

  init(
    viewport: CGFloat, metric: Metric, columns: [ProcessColumn], saved: ProcessColumnWidths,
    order: ProcessColumnOrder = ProcessColumnOrder()
  ) {
    self.order = order.ordered(["name"] + columns.map(\.id), metric: metric)
    var measured = Dictionary(
      uniqueKeysWithValues: columns.map { column in
        (
          column.id,
          saved.width(column.id, metric: metric) ?? Self.preferred(column, metric: metric)
        )
      })
    let nameFloor = Self.nameMinimum(viewport)
    if saved.width("name", metric: metric) == nil {
      let deficit = max(0, nameFloor + measured.values.reduce(0, +) - viewport)
      let capacities = Dictionary(
        uniqueKeysWithValues: columns.map { column in
          (
            column.id,
            saved.width(column.id, metric: metric) == nil
              ? max(0, measured[column.id]! - Self.minimum(column, metric: metric)) : 0
          )
        })
      let capacity = capacities.values.reduce(0, +)
      if deficit > 0, capacity > 0 {
        for column in columns {
          measured[column.id]! -= min(1, deficit / capacity) * capacities[column.id]!
        }
      }
    }
    widths = measured
    let metrics = measured.values.reduce(0, +)
    name = saved.width("name", metric: metric) ?? max(nameFloor, viewport - metrics)
    let content = name + metrics
    total = content - viewport < 0.01 ? viewport : content
  }

  static func nameMinimum(_ viewport: CGFloat) -> CGFloat {
    min(240, max(180, viewport * 0.20))
  }

  /// Readable value widths, not a fixed allowance for every header and sort arrow.
  static func minimum(_ column: ProcessColumn, metric: Metric) -> CGFloat {
    switch ProcessColumns.canonical(column.id, metric: metric) {
    case "cpu", "gpu": return 78
    case "pid", "ports", "threads": return 60
    case "kind", "nap", "sandbox", "restricted", "sleep", "suddenTermination": return 60
    case "time", "gpuTime": return 86
    case "user": return 100
    case "memory", "resident", "privateMemory", "sharedMemory", "purgeable", "compressed",
      "written", "read", "received", "sent":
      return column.id == "primary" || column.id == "received" ? 110 : 96
    default: return 88
    }
  }

  func width(_ key: String) -> CGFloat { key == "name" ? name : widths[key] ?? 100 }
  func offset(_ key: String) -> CGFloat { order.prefix { $0 != key }.reduce(0) { $0 + width($1) } }

  static func preferred(_ column: ProcessColumn, metric: Metric) -> CGFloat {
    let key = ProcessColumns.canonical(column.id, metric: metric)
    let base: CGFloat
    switch key {
    case "cpu", "gpu": base = 78
    case "threads", "ports", "pid": base = 64
    case "kind", "nap", "sandbox", "restricted": base = 70
    case "user": base = 116
    case "memory", "resident", "privateMemory", "sharedMemory", "purgeable", "compressed",
      "written", "read", "received", "sent":
      base = 112
    case "time", "gpuTime": base = 96
    default: base = 100
    }
    let title = (column.title as NSString).size(withAttributes: [
      .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
    ]).width
    return max(base, ceil(title) + 32)
  }

  static func fitted(key: String, title: String, metric: Metric, rows: [ProcessRow]) -> CGFloat {
    let header =
      (title as NSString).size(withAttributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
      ]).width + 32
    let font =
      key == "name"
      ? NSFont.systemFont(ofSize: 12)
      : NSFont.monospacedDigitSystemFont(ofSize: key == "user" ? 11 : 12, weight: .medium)
    let content = rows.reduce(CGFloat(0)) { width, row in
      let text = key == "name" ? row.name : ProcessValues.text(row, key: key, metric: metric)
      return max(width, (text as NSString).size(withAttributes: [.font: font]).width)
    }
    return ProcessColumnWidths.clamp(
      ceil(max(header, content + (key == "name" ? 68 : 34))), key: key)
  }
}

struct ProcessColumnResizeHandle: View {
  let title: String
  let width: CGFloat
  let theme: MonitorTheme
  let resize: (CGFloat, Bool) -> Void
  let fit: () -> Void
  let reset: () -> Void
  @State private var start: CGFloat?
  @State private var hovered = false
  var body: some View {
    Rectangle().fill(hovered || start != nil ? theme.blue : theme.border)
      .frame(width: 1, height: 16)
      .frame(width: 8, height: 36).contentShape(Rectangle())
      .onHover { value in
        hovered = value
        if value { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
      }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { value in
            if start == nil { start = width }
            resize((start ?? width) + value.translation.width, false)
          }
          .onEnded { value in
            resize((start ?? width) + value.translation.width, true)
            start = nil
          }
      )
      .onTapGesture(count: 2, perform: fit)
      .contextMenu {
        Button("Fit column to contents", action: fit)
        Button("Reset column width", action: reset)
      }
      .help("Drag to resize \(title). Double-click to fit contents.")
      .accessibilityLabel("Resize \(title)")
      .accessibilityValue("\(Int(width)) points")
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: resize(width + 10, true)
        case .decrement: resize(width - 10, true)
        @unknown default: break
        }
      }
  }
}

/// Read the usable clip width, including the space reserved by legacy scrollbars.
struct ProcessTableViewport: NSViewRepresentable {
  var changed: (CGFloat) -> Void
  final class Anchor: NSView {
    var changed: ((CGFloat) -> Void)?
    var observer: NSObjectProtocol?
    weak var clip: NSClipView?
    var lastWidth: CGFloat = 0
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in self?.connect() }
    }
    func connect() {
      guard let content = enclosingScrollView?.contentView else { return }
      if clip !== content {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        clip = content
        content.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification, object: content, queue: .main
        ) { [weak self] _ in self?.report() }
      }
      report()
    }
    func report() {
      guard let width = clip?.bounds.width, width > 0, abs(width - lastWidth) > 0.5 else { return }
      lastWidth = width
      DispatchQueue.main.async { [weak self] in self?.changed?(width) }
    }
  }
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.changed = changed
    DispatchQueue.main.async { [weak view] in view?.connect() }
  }
}

/// Never silently clip leading digits when the user makes a numeric column narrow.
enum ProcessCellText {
  static func truncate(_ text: String, width: CGFloat, font: NSFont) -> String {
    func measured(_ value: String) -> CGFloat {
      (value as NSString).size(withAttributes: [.font: font]).width
    }
    guard measured(text) > width else { return text }
    let characters = Array(text)
    var low = 0
    var high = characters.count
    while low < high {
      let middle = (low + high + 1) / 2
      if measured(String(characters.prefix(middle)) + "…") <= width {
        low = middle
      } else {
        high = middle - 1
      }
    }
    return String(characters.prefix(low)) + "…"
  }
}
