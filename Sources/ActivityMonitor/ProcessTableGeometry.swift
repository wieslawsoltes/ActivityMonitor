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
  final class Anchor: NSView {
    override var isFlipped: Bool { true }
    var selectedID: Int32?
  }
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    guard view.selectedID != selectedID else { return }
    view.selectedID = selectedID
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
