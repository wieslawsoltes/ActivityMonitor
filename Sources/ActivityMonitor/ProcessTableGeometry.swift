import AppKit
import SwiftUI

enum ProcessTableGeometry {
  static func originToReveal(row: Int, visible: CGRect, contentHeight: CGFloat) -> CGPoint {
    let header: CGFloat = 37
    let top = header + CGFloat(row) * 41
    let bottom = top + 41
    var y = visible.minY
    if top < y + header {
      y = top - header
    } else if bottom > visible.maxY {
      y = bottom - visible.height
    }
    return CGPoint(x: visible.minX, y: min(max(0, y), max(0, contentHeight - visible.height)))
  }
}

/// Preserve horizontal position when keyboard navigation reveals a selected row.
/// A two-axis ScrollViewReader would also reveal the wide row horizontally.
struct ProcessTableSelectionScroll: NSViewRepresentable {
  var selectedID: Int32?
  var rowIndex: Int?
  var revealRevision = 0
  final class Anchor: NSView {
    override var isFlipped: Bool { true }
    var selectedID: Int32?
    var revealRevision = -1
  }
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    guard view.selectedID != selectedID || view.revealRevision != revealRevision else { return }
    view.selectedID = selectedID
    view.revealRevision = revealRevision
    guard let rowIndex, let selectedID else { return }
    DispatchQueue.main.async { [weak view] in
      guard let view, view.selectedID == selectedID,
        let scroll = view.enclosingScrollView, let document = scroll.documentView
      else { return }
      let clip = scroll.contentView
      // SwiftUI's hosting document can include scroller insets and an origin
      // different from the stack. Calculate in the stack's actual coordinates.
      let visible = view.convert(scroll.documentVisibleRect, from: document)
      let origin = ProcessTableGeometry.originToReveal(
        row: rowIndex, visible: visible, contentHeight: view.bounds.height)
      let revealed = view.convert(CGRect(origin: origin, size: visible.size), to: document)
      let target = CGPoint(x: clip.bounds.minX, y: revealed.minY)
      if target != clip.bounds.origin {
        clip.scroll(to: target)
        scroll.reflectScrolledClipView(clip)
      }
    }
  }
}

/// Bound SwiftUI row construction even when a two-axis scroll view proposes an
/// unbounded height. Absolute row indices preserve striping, selection and reveal.
enum ProcessVisibleRows {
  static func range(count: Int, viewport: CGRect, overscan: Int = 2) -> Range<Int> {
    guard count > 0 else { return 0..<0 }
    let first = max(0, Int(floor(max(0, viewport.minY - 37) / 41)) - overscan)
    let last = Int(ceil(max(0, viewport.maxY - 37) / 41)) + overscan
    let lower = min(count, first)
    return lower..<min(count, max(lower, last))
  }
}

/// Keep scroll-position invalidation inside the row viewport. Scrolling must not
/// rebuild the process toolbar, menus, column preferences or dashboard shell.
struct ProcessViewportRows<RowContent: View>: View {
  let entries: [ProcessTreeEntry]
  let widthChanged: (CGFloat) -> Void
  let horizontalChanged: (CGFloat) -> Void
  let rowContent: (Int, ProcessTreeEntry) -> RowContent
  @State private var viewport: CGRect
  init(
    entries: [ProcessTreeEntry], height: CGFloat,
    widthChanged: @escaping (CGFloat) -> Void,
    horizontalChanged: @escaping (CGFloat) -> Void,
    @ViewBuilder rowContent: @escaping (Int, ProcessTreeEntry) -> RowContent
  ) {
    self.entries = entries
    self.widthChanged = widthChanged
    self.horizontalChanged = horizontalChanged
    self.rowContent = rowContent
    _viewport = State(initialValue: CGRect(x: 0, y: 0, width: 1200, height: height))
  }
  var body: some View {
    let range = ProcessVisibleRows.range(count: entries.count, viewport: viewport)
    VStack(spacing: 0) {
      Color.clear.frame(height: 37 + CGFloat(range.lowerBound) * 41)
      ForEach(Array(entries[range].enumerated()), id: \.element.id) { offset, entry in
        rowContent(range.lowerBound + offset, entry)
      }
      Color.clear.frame(height: CGFloat(entries.count - range.upperBound) * 41)
    }.background(
      ProcessTableViewport(
        changed: widthChanged,
        visibleChanged: { rect in
          if abs(viewport.minX - rect.minX) > 0.1 { horizontalChanged(rect.minX) }
          if ProcessVisibleRows.range(count: entries.count, viewport: rect) != range
            || abs(viewport.minX - rect.minX) > 0.1
            // Remember the reset origin even when both visible ranges are empty.
            || (entries.isEmpty && viewport != rect)
          {
            viewport = rect
          }
        }))
  }
}
