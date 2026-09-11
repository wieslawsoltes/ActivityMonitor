import AppKit
import CoreText
import SwiftUI

/// Reuse shaped glyphs between telemetry ticks. Resolving SwiftUI Text for every
/// visible metric on every tick dominated the table's main-thread render time.
enum ProcessMetricDrawing {
  struct Key: Hashable {
    let text: String
    let user: Bool
    let primary: Bool
    let highlighted: Bool
    let dark: Bool
  }
  struct Glyphs {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
  }
  static let cache = BoundedCache<Key, Glyphs>(capacity: 4096)

  static func glyphs(_ key: Key, theme: MonitorTheme) -> Glyphs {
    cache.value(for: key) {
      let font = NSFont.monospacedDigitSystemFont(
        ofSize: key.user ? 11 : 12, weight: key.primary ? .medium : .regular)
      let color = key.highlighted ? theme.blue : key.primary ? theme.text : theme.secondary
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(
          string: key.text, attributes: [.font: font, .foregroundColor: NSColor(color)]))
      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
      return Glyphs(line: line, width: CGFloat(width), ascent: ascent, descent: descent)
    }
  }

  static func draw(
    row: ProcessRow, columns: [ProcessColumn], layout: ProcessColumnLayout,
    metric: Metric, theme: MonitorTheme, usage: ProcessSubtreeUsage? = nil, in context: CGContext
  ) {
    var x: CGFloat = 0
    for key in layout.order {
      let width = layout.width(key)
      defer { x += width }
      guard columns.contains(where: { $0.id == key }) else { continue }
      let primary = key == "primary" || metric == .network && key == "received"
      let highlighted = key == "primary" && [.cpu, .memory, .gpu].contains(metric)
      let user = key == "user"
      let text = ProcessCellText.truncate(
        ProcessValues.text(row, key: key, metric: metric, usage: usage),
        width: width - (highlighted ? 34 : 20),
        font: .monospacedDigitSystemFont(
          ofSize: user ? 11 : 12, weight: primary ? .medium : .regular))
      let glyphs = glyphs(
        Key(text: text, user: user, primary: primary, highlighted: highlighted, dark: theme.dark),
        theme: theme)
      context.saveGState()
      context.clip(to: CGRect(x: x + 10, y: 0, width: max(0, width - 20), height: 41))
      if highlighted {
        let pillWidth = min(width - 20, glyphs.width + 14)
        context.setFillColor(NSColor(theme.blue.opacity(0.095)).cgColor)
        context.addPath(
          CGPath(
            roundedRect: CGRect(
              x: x + width - 10 - pillWidth, y: 8.5, width: pillWidth, height: 24),
            cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.fillPath()
      }
      let left = user ? x + 10 : x + width - (highlighted ? 17 : 10) - glyphs.width
      // Canvas is top-left oriented; Core Text's baseline is bottom-left oriented.
      context.translateBy(x: left, y: 20.5 + (glyphs.ascent - glyphs.descent) / 2)
      context.scaleBy(x: 1, y: -1)
      context.textMatrix = .identity
      context.textPosition = .zero
      CTLineDraw(glyphs.line, context)
      context.restoreGState()
    }
  }
}
