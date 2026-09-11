import AppKit
import SwiftUI

struct ProcessColumnOrder {
  private static let decoded = BoundedCache<String, [String: [String]]>(capacity: 16)
  var values: [String: [String]]
  init(_ json: String = "{}") {
    values = Self.decoded.value(for: json) {
      (try? JSONDecoder().decode([String: [String]].self, from: Data(json.utf8))) ?? [:]
    }
  }
  var json: String { (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "{}" }
  func ordered(_ keys: [String], metric: Metric) -> [String] {
    let allowed = Set(keys)
    var seen = Set<String>()
    return ((values[metric.rawValue] ?? []) + keys).filter {
      allowed.contains($0) && seen.insert($0).inserted
    }
  }
  mutating func move(_ key: String, to target: String, metric: Metric) {
    var order = ordered(["name"] + ProcessColumns.available(metric).map(\.id), metric: metric)
    guard key != target, let source = order.firstIndex(of: key),
      let destination = order.firstIndex(of: target)
    else { return }
    order.remove(at: source)
    order.insert(key, at: destination)
    values[metric.rawValue] = order
  }
  mutating func reset(_ metric: Metric) { values[metric.rawValue] = nil }
}

struct ProcessHeaderReorder: ViewModifier {
  let key: String
  let layout: ProcessColumnLayout
  let move: (String, String) -> Void
  @State private var translation: CGFloat = 0
  func body(content: Content) -> some View {
    content
      .background(translation == 0 ? Color.clear : Color.accentColor.opacity(0.1))
      .offset(x: translation)
      .zIndex(translation == 0 ? 0 : 1)
      .highPriorityGesture(
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
          .onChanged { translation = $0.translation.width }
          .onEnded { value in
            let center = layout.offset(key) + layout.width(key) / 2 + value.translation.width
            let target =
              layout.order.first { center < layout.offset($0) + layout.width($0) }
              ?? layout.order.last
            translation = 0
            if let target { move(key, target) }
          })
  }
}

struct ProcessListSelection {
  var ids: Set<Int32> = []
  var anchor: Int32?
  var lead: Int32?
  mutating func select(_ id: Int32, order: [Int32], extending: Bool = false, toggling: Bool = false)
  {
    if extending, let anchor, let first = order.firstIndex(of: anchor),
      let last = order.firstIndex(of: id)
    {
      let range = Set(order[min(first, last)...max(first, last)])
      ids = toggling ? ids.union(range) : range
    } else if toggling {
      if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
      anchor = id
    } else {
      ids = [id]
      anchor = id
    }
    lead = ids.contains(id) ? id : order.first { ids.contains($0) }
  }
  mutating func move(_ distance: Int, order: [Int32], extending: Bool = false) {
    guard !order.isEmpty else { return }
    let index = order.firstIndex { $0 == lead } ?? (distance > 0 ? -1 : order.count)
    select(
      order[min(max(index + distance, 0), order.count - 1)], order: order, extending: extending)
  }
}

func processClipboard(
  _ rows: [ProcessRow], keys: [String], metric: Metric,
  usage: [Int32: ProcessSubtreeUsage]? = nil
) -> String {
  let titles = Dictionary(
    uniqueKeysWithValues: ProcessColumns.available(metric).map { ($0.id, $0.title) })
  func clean(_ text: String) -> String {
    text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
  }
  let header = keys.map { key in
    let title = key == "name" ? "Process name" : titles[key] ?? key
    return usage != nil && ProcessUsageMetric.resolve(key, metric: metric) != nil
      ? "Σ " + title : title
  }.joined(separator: "\t")
  return
    ([header]
    + rows.map { row in
      keys.map { key in
        clean(
          key == "name"
            ? row.name
            : ProcessValues.text(row, key: key, metric: metric, usage: usage?[row.id]))
      }.joined(separator: "\t")
    }).joined(separator: "\n")
}
