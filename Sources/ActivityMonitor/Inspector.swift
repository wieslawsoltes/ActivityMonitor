import AppKit
import SwiftUI

struct MonitorInspector: View {
  let process: ProcessRow?
  let theme: MonitorTheme
  let busy: Bool
  let close: () -> Void
  let sample: (ProcessRow) -> Void
  let files: (ProcessRow) -> Void
  let reveal: (ProcessRow) -> Void
  let stop: (ProcessRow) -> Void
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Process details").font(.system(size: 11, weight: .medium)).foregroundStyle(
          theme.secondary)
        Spacer()
        Button(action: close) { Image(systemName: "xmark") }.buttonStyle(
          MonitorIconButton(theme: theme)
        ).help("Close inspector")
      }.padding(.leading, 20).padding(.trailing, 14).frame(height: 52)
      ScrollView {
        if let p = process {
          VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
              ProcessIcon(pid: p.id, isApp: p.isApp, size: 48)
              VStack(alignment: .leading, spacing: 6) {
                Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                  .fixedSize(horizontal: false, vertical: true)
                Text("PID \(String(p.id)) · \(p.kind)").font(.system(size: 10)).foregroundStyle(
                  theme.secondary)
              }
            }.padding(.bottom, 22)
            HStack(spacing: 9) {
              hero("CPU usage", p.accessible ? String(format: "%.1f", p.cpu) : "—", "%")
              hero(
                "Memory", p.accessible ? byteParts(p.memory).0 : "—",
                p.accessible ? byteParts(p.memory).1 : "")
            }.padding(.bottom, 18)
            Rectangle().fill(theme.separator).frame(height: 1)
            VStack(spacing: 14) {
              detail("User", p.user)
              detail("Threads", p.accessible ? String(p.threads) : "—")
              detail("CPU time", p.accessible ? duration(p.cpuTime) : "—")
              detail("GPU usage", "—")
              detail("Kind", p.kind)
              detail("Parent PID", String(p.parent))
              HStack {
                Text("Process ID").foregroundStyle(theme.secondary)
                Spacer()
                Text(String(p.id)).foregroundStyle(theme.secondary)
                Button {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(String(p.id), forType: .string)
                } label: {
                  Image(systemName: "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(theme.secondary).help("Copy PID")
              }.font(.system(size: 10))
            }.padding(.top, 17)
            VStack(spacing: 8) {
              Button {
                sample(p)
              } label: {
                Label(
                  busy ? "Collecting…" : "Sample process", systemImage: "doc.text.magnifyingglass")
              }.disabled(busy)
              Button {
                files(p)
              } label: {
                Label("Open files & ports", systemImage: "folder")
              }.disabled(busy)
              Button {
                reveal(p)
              } label: {
                Label("Reveal executable", systemImage: "arrow.up.forward.square")
              }
            }.buttonStyle(MonitorActionButton(theme: theme)).padding(.top, 23)
            Button {
              stop(p)
            } label: {
              Label("Quit process…", systemImage: "xmark.octagon")
            }.buttonStyle(MonitorActionButton(theme: theme, danger: true)).disabled(
              p.uid != getuid() || p.id <= 1 || p.id == getpid()
            ).padding(.top, 8)
            Text(
              "Unavailable counters are shown as —. Some system processes are protected by macOS."
            ).font(.system(size: 10)).foregroundStyle(theme.tertiary).lineSpacing(4).padding(
              .top, 14)
          }.padding(.horizontal, 20).padding(.bottom, 20)
        } else {
          ContentUnavailableView(
            "Select a process", systemImage: "cursorarrow.click",
            description: Text("Choose a row to see its details."))
        }
      }
    }.background(theme.card).clipShape(
      UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
    ).overlay(
      UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).stroke(
        theme.border, lineWidth: 1))
  }
  func hero(_ title: String, _ number: String, _ unit: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 9)).foregroundStyle(theme.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(number).font(.system(size: 21, weight: .medium)).tracking(-0.5)
        Text(unit).font(.system(size: 11)).foregroundStyle(theme.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
      theme.subtle, in: RoundedRectangle(cornerRadius: 8))
  }
  func detail(_ name: String, _ value: String) -> some View {
    HStack {
      Text(name).foregroundStyle(theme.secondary)
      Spacer()
      Text(value).foregroundStyle(theme.text).monospacedDigit()
    }.font(.system(size: 11))
  }
}
struct ProcessIcon: View {
  let pid: Int32
  let isApp: Bool
  var size: CGFloat = 24
  var body: some View {
    Group {
      if let icon = ProcessIconCache.icon(pid: pid) {
        Image(nsImage: icon).resizable().interpolation(.high)
      } else {
        Image(systemName: isApp ? "app.fill" : pid < 1000 ? "cpu" : "terminal.fill").resizable()
          .scaledToFit().foregroundStyle(Color(hex: pid < 1000 ? 0x8fa1b7 : 0xdbe3ed)).padding(
            size * 0.16
          ).background(
            Color(hex: pid < 1000 ? 0xe8edf4 : 0x303946),
            in: RoundedRectangle(cornerRadius: size * 0.22))
      }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }
}

@MainActor enum ProcessIconCache {
  static let images = NSCache<NSString, NSImage>()
  static func icon(pid: Int32) -> NSImage? {
    var buffer = [CChar](repeating: 0, count: 4096)
    if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
      let path = String(cString: buffer)
      if let range = path.range(of: ".app/") {
        let bundle = String(path[..<range.lowerBound]) + ".app"
        if let cached = images.object(forKey: bundle as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: bundle)
        images.setObject(image, forKey: bundle as NSString)
        return image
      }
    }
    return NSRunningApplication(processIdentifier: pid)?.icon
  }
}
