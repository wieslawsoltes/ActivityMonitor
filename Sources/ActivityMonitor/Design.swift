import AppKit
import SwiftUI

struct MonitorTheme {
  let dark: Bool
  var window: Color { Color(hex: dark ? 0x1c1e23 : 0xf6f7f9) }
  var toolbar: Color { Color(hex: dark ? 0x24262c : 0xfbfcfe) }
  var card: Color { Color(hex: dark ? 0x24272e : 0xffffff) }
  var subtle: Color { Color(hex: dark ? 0x2a2d35 : 0xf5f6f8) }
  var recessed: Color { Color(hex: dark ? 0x1b1d23 : 0xeceef2) }
  var hover: Color { Color(hex: dark ? 0x2c323e : 0xf0f4fa) }
  var selected: Color { Color(hex: dark ? 0x283b59 : 0xeaf2ff) }
  var text: Color { Color(hex: dark ? 0xedf0f6 : 0x20242c) }
  var secondary: Color { Color(hex: dark ? 0xa3acbc : 0x69717f) }
  var tertiary: Color { Color(hex: dark ? 0x7f899b : 0x858e9e) }
  var border: Color { Color(hex: dark ? 0xcedbf1 : 0x2c3d58).opacity(dark ? 0.09 : 0.10) }
  var separator: Color { Color(hex: dark ? 0xcedbf1 : 0x2c3d58).opacity(0.07) }
  var blue: Color { Color(hex: dark ? 0x76a8ff : 0x4086f7) }
  var coral: Color { Color(hex: dark ? 0xf090a0 : 0xee8492) }
  var green: Color { Color(hex: dark ? 0x73cca5 : 0x57b98e) }
  var amber: Color { Color(hex: dark ? 0xefbd6a : 0xe6aa49) }
  var purple: Color { Color(hex: dark ? 0xb3a3ee : 0x9b8bd9) }
  var stripe: Color { Color(hex: dark ? 0xb8c6dc : 0x24354f).opacity(0.02) }
}
extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255, opacity: 1)
  }
}
struct DesignCard<Content: View>: View {
  let theme: MonitorTheme
  var padding: CGFloat = 20
  @ViewBuilder var content: Content
  var body: some View {
    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(
      padding
    ).background(theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(
      RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1)
    ).shadow(color: .black.opacity(theme.dark ? 0.06 : 0.025), radius: 2, y: 1)
  }
}
struct MonitorIconButton: ButtonStyle {
  let theme: MonitorTheme
  var active = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 14, weight: .regular)).foregroundStyle(
      active ? theme.text : theme.secondary
    ).frame(width: 32, height: 32).background(
      active || configuration.isPressed ? theme.recessed : Color.clear,
      in: RoundedRectangle(cornerRadius: 8)
    ).contentShape(Rectangle())
  }
}
struct MonitorActionButton: ButtonStyle {
  let theme: MonitorTheme
  var danger = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(
      danger ? theme.coral : theme.text
    ).frame(maxWidth: .infinity).frame(height: 33).background(
      configuration.isPressed ? theme.hover : danger ? theme.coral.opacity(0.08) : Color.clear,
      in: RoundedRectangle(cornerRadius: 8)
    ).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
  }
}
struct BrandMark: View {
  var size: CGFloat = 33
  var body: some View {
    Image(systemName: "waveform.path.ecg").font(.system(size: size * 0.65, weight: .regular))
      .foregroundStyle(Color(hex: 0x8ee0bd)).frame(width: size, height: size).background(
        LinearGradient(
          colors: [Color(hex: 0x47566a), Color(hex: 0x1e2837)], startPoint: .topLeading,
          endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.27)
      ).overlay(
        RoundedRectangle(cornerRadius: size * 0.27).stroke(.white.opacity(0.14), lineWidth: 1)
      ).shadow(color: .black.opacity(0.14), radius: 2, y: 1)
  }
}
struct WindowChrome: NSViewRepresentable {
  class ChromeView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      DispatchQueue.main.async { [weak self] in
        guard let window = self?.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
          window.standardWindowButton(button)?.isHidden = true
        }
      }
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override var mouseDownCanMoveWindow: Bool { true }
  }
  func makeNSView(context: Context) -> ChromeView { ChromeView() }
  func updateNSView(_ view: ChromeView, context: Context) {}
}
struct TrafficLights: View {
  @State var hovering = false
  var body: some View {
    HStack(spacing: 8) {
      light(0xff6059, "xmark", "Close") { NSApp.keyWindow?.performClose(nil) }
      light(0xffbe2f, "minus", "Minimize") { NSApp.keyWindow?.miniaturize(nil) }
      light(0x28c840, "arrow.up.left.and.arrow.down.right", "Zoom") { NSApp.keyWindow?.zoom(nil) }
    }.onHover { hovering = $0 }
  }
  func light(_ color: UInt32, _ icon: String, _ label: String, _ action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Circle().fill(Color(hex: color)).frame(width: 12, height: 12).overlay {
        if hovering {
          Image(systemName: icon).font(.system(size: 7, weight: .bold)).foregroundStyle(
            .black.opacity(0.55))
        }
      }
    }.buttonStyle(.plain).help(label).accessibilityLabel(label)
  }
}
