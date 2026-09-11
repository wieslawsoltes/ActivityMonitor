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
  var diagnose: ((ProcessRow, Bool) -> Void)? = nil
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
              ProcessIcon(pid: p.id, isApp: p.isApp, start: p.start, size: 48)
              VStack(alignment: .leading, spacing: 6) {
                Text(p.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text)
                  .fixedSize(horizontal: false, vertical: true)
                Text("PID \(String(p.id)) · \(p.kind)").font(.system(size: 10)).foregroundStyle(
                  theme.secondary)
              }
            }.padding(.bottom, 22)
            HStack(spacing: 9) {
              hero("CPU usage", p.accessible ? String(format: "%.1f", p.cpu) : "—", "%")
                .help(CPUAccounting.processHelp)
              hero(
                "Memory", p.accessible ? byteParts(p.memory).0 : "—",
                p.accessible ? byteParts(p.memory).1 : "")
            }.padding(.bottom, 18)
            Rectangle().fill(theme.separator).frame(height: 1)
            VStack(spacing: 14) {
              detail("User", p.user)
              detail("Threads", p.accessible ? String(p.threads) : "—")
              detail("CPU time", p.accessible ? duration(p.cpuTime) : "—")
              detail("GPU usage", gpuPercent(p.gpuPercent) + (p.gpuPercent == nil ? "" : "%"))
              detail("Observed GPU time", gpuDuration(p.gpuTime))
              Text(
                p.gpuAvailability
                  + ". Observed time covers this session. Execution-time rates can exceed 100% when GPU work overlaps."
              )
              .font(.system(size: 10)).foregroundStyle(theme.tertiary).fixedSize(
                horizontal: false, vertical: true)
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
              if let diagnose {
                Button {
                  diagnose(p, false)
                } label: {
                  Label("Process diagnostics…", systemImage: "waveform.path.ecg.rectangle")
                }
                Button {
                  diagnose(p, true)
                } label: {
                  Label("Open in tool window", systemImage: "arrow.up.forward.square")
                }
              }
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
  var start: UInt64 = 0
  var size: CGFloat = 24
  var body: some View {
    Group {
      if let icon = ProcessIconCache.icon(pid: pid, start: start, isApp: isApp) {
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
  static let images: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 128
    cache.totalCostLimit = 8 * 1024 * 1024
    return cache
  }()
  static func retain(identities: [Int32: UInt64]) {
    processes = processes.filter { identities[$0.key] == $0.value.start }
    trimIfNeeded()
  }
  static var retainedProcessCount: Int { processes.count }
  private struct Entry {
    let start: UInt64
    let image: NSImage?
    var lastUsed: UInt64
  }
  // Process identities are intentionally kept separate from the shared bundle cache so a
  // recycled PID can never display an old icon. Keep the identity cache small as process
  // tables can contain thousands of short-lived helpers over an app's lifetime.
  private static let processLimit = 128
  private static var accessCounter: UInt64 = 0
  private static var processes: [Int32: Entry] = [:]
  static func icon(pid: Int32, start: UInt64, isApp: Bool) -> NSImage? {
    accessCounter &+= 1
    if var entry = processes[pid], entry.start == start {
      entry.lastUsed = accessCounter
      processes[pid] = entry
      return entry.image
    }
    let image = resolve(pid: pid, isApp: isApp)
    processes[pid] = Entry(start: start, image: image, lastUsed: accessCounter)
    trimIfNeeded()
    return image
  }
  private static func trimIfNeeded() {
    guard processes.count > processLimit else { return }
    let removeCount = max(1, processes.count - processLimit)
    let victims = processes.sorted { $0.value.lastUsed < $1.value.lastUsed }
      .prefix(removeCount).map(\.key)
    for pid in victims { processes.removeValue(forKey: pid) }
  }
  /// Keep one small Retina representation, sufficient for the largest 48-point inspector icon.
  static func thumbnail(_ original: NSImage) -> NSImage {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return original }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    original.draw(
      in: CGRect(x: 0, y: 0, width: 128, height: 128), from: .zero,
      operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: 64, height: 64)
    let result = NSImage(size: bitmap.size)
    result.addRepresentation(bitmap)
    return result
  }
  private static func resolve(pid: Int32, isApp: Bool) -> NSImage? {
    var buffer = [CChar](repeating: 0, count: 4096)
    if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
      let path = String(cString: buffer)
      if let range = path.range(of: ".app/") {
        let bundle = String(path[..<range.lowerBound]) + ".app"
        if let cached = images.object(forKey: bundle as NSString) { return cached }
        let image = thumbnail(NSWorkspace.shared.icon(forFile: bundle))
        images.setObject(image, forKey: bundle as NSString, cost: 128 * 128 * 4)
        return image
      }
    }
    return isApp ? NSRunningApplication(processIdentifier: pid)?.icon.map(thumbnail) : nil
  }
}
