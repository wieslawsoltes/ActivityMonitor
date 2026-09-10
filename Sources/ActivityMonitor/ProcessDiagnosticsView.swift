import AppKit
import SwiftUI

/// Process history has independent missing-data segments and a dynamic CPU/GPU axis.
/// 100% CPU represents one logical core; memory is footprint bytes, not host pressure.
enum ProcessActivityPresentation {
  static func samples(_ history: [ProcessActivitySample], metric: Metric) -> [TelemetrySample] {
    var result: [TelemetrySample] = []
    var segments = [0, 0]
    var previous: Date?
    for point in history {
      if let previous, point.date.timeIntervalSince(previous) > 3 {
        segments[0] += 1
        segments[1] += 1
      }
      previous = point.date
      let values: [Double?]
      switch metric {
      case .cpu, .energy: values = [point.cpu]
      case .memory: values = [point.memory.map { Double($0) }]
      case .gpu: values = [point.gpu]
      case .disk: values = [point.read, point.written.map { -$0 }]
      case .network: values = [point.received, point.sent.map { -$0 }]
      }
      for (series, value) in values.enumerated() {
        guard let value, value.isFinite else {
          segments[series] += 1
          continue
        }
        result.append(
          .init(date: point.date, value: value, series: series, segment: segments[series]))
      }
    }
    return result
  }
  @MainActor static func latest(_ session: ProcessDiagnosticSession, metric: Metric) -> String {
    let p = session.row
    let latest = session.histories.last
    switch metric {
    case .cpu, .energy: return p.accessible ? String(format: "%.1f%%", p.cpu) : "—"
    case .memory: return p.accessible ? bytes(p.memory) : "—"
    case .gpu: return p.gpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
    case .disk: return latest?.read.map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—"
    case .network: return latest?.received.map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—"
    }
  }
  static func keys(_ metric: Metric) -> [String] {
    switch metric {
    case .cpu: return ["cpu", "time", "threads", "wakeups", "kind", "ports"]
    case .memory:
      return [
        "memory", "resident", "privateMemory", "sharedMemory", "compressed", "purgeable", "ports",
      ]
    case .energy: return ["cpu", "wakeups", "sleep", "nap", "energyImpact", "suddenTermination"]
    case .disk: return ["read", "written"]
    case .network: return ["received", "sent", "packetsIn", "packetsOut"]
    case .gpu: return ["gpu", "gpuTime", "cpu", "memory"]
    }
  }
  static func note(_ metric: Metric) -> String {
    switch metric {
    case .cpu: return CPUAccounting.processHelp
    case .memory:
      return "Memory shows physical footprint. Memory regions provide mapping-level resident usage."
    case .energy:
      return
        "CPU workload is a proxy, not Apple’s Energy Impact score. App Nap and Energy Impact are unavailable through public process APIs."
    case .disk:
      return
        "Read is above the baseline; write is below. Rates use observed counter deltas; totals cover the process lifetime."
    case .network:
      return
        "Receive is above the baseline; send is below. Network counters refresh approximately every five seconds; observed rates can be bursty."
    case .gpu:
      return
        "GPU execution rate can exceed 100% when work overlaps. Observed GPU time covers this app session; unsupported counters remain unavailable."
    }
  }
}
struct ProcessDiagnosticsView: View {
  @ObservedObject var session: ProcessDiagnosticSession
  let center: ProcessDiagnosticsCenter
  var toolWindow = false
  var persistTableColumns = true
  let close: () -> Void
  var float: (Bool) -> Void = { _ in }
  @Environment(\.colorScheme) private var scheme
  @AppStorage("appearance") private var appearance = "System"
  @State private var query = ""
  @State private var floating = false
  @State private var confirmStop = false
  @State private var exportError: String?
  private var theme: MonitorTheme {
    .init(dark: appearance == "Dark" || appearance == "System" && scheme == .dark)
  }
  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        DiagnosticSidebar(selection: $session.tab, theme: theme)
        Divider()
        VStack(alignment: .leading, spacing: 0) {
          contentHeader
          content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      Divider()
      HStack(spacing: 10) {
        Circle().fill(
          session.exited
            ? theme.tertiary : (session.paused || session.sourcePaused) ? theme.amber : theme.green
        )
        .frame(width: 6, height: 6)
        Text(session.state)
        if let status = session.collectionStatus { Text(status).lineLimit(1).help(status) }
        if session.collecting {
          ProgressView().controlSize(.mini)
          Text("Refreshing details")
        }
        Spacer()
        if let date = session.histories.last?.date {
          Text("Last activity \(date.formatted(date:.omitted,time:.standard))")
        }
      }.font(.system(size: 10)).foregroundStyle(theme.secondary).padding(.horizontal, 18).frame(
        height: 30
      ).background(theme.toolbar)
    }.background(theme.window).foregroundStyle(theme.text)
      .frame(minWidth: 760, minHeight: 500)
      .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
      .onChange(of: session.tab) {
        query = ""
        session.refreshDetails(force: true)
      }
      .onChange(of: session.paused) { if !session.paused { session.refreshDetails(force: true) } }
      .alert("Stop \(session.row.name)?", isPresented: $confirmStop) {
        Button("Cancel", role: .cancel) {}
        Button("Quit", role: .destructive) { center.terminate(session, force: false) }
        Button("Force Quit", role: .destructive) { center.terminate(session, force: true) }
      } message: {
        Text("Force Quit stops the process immediately and may lose unsaved work.")
      }
      .alert(
        "Export failed",
        isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
      ) {
        Button("OK") { exportError = nil }
      } message: {
        Text(exportError ?? "")
      }
  }
  private var header: some View {
    HStack(spacing: 12) {
      ProcessIcon(pid: session.id.pid, isApp: session.row.isApp, start: session.id.start, size: 36)
      VStack(alignment: .leading, spacing: 5) {
        Text(session.row.name).font(.system(size: 19, weight: .semibold)).lineLimit(1).help(
          session.row.name)
        Text("PID \(session.id.pid) · \(session.row.user) · \(session.row.kind)").font(
          .system(size: 11)
        ).foregroundStyle(theme.secondary)
      }
      Spacer(minLength: 10)
      Button {
        session.paused.toggle()
      } label: {
        Image(systemName: session.paused ? "play" : "pause")
      }.help(session.paused ? "Resume process activity" : "Pause process activity").disabled(
        session.exited)
      Button {
        session.refreshDetails(force: true)
      } label: {
        Image(systemName: "arrow.clockwise")
      }.help("Refresh process details").disabled(session.collecting || session.exited)
      if toolWindow {
        Button {
          floating.toggle()
          float(floating)
        } label: {
          Image(systemName: floating ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
        }.help(floating ? "Stop floating above windows" : "Float above windows")
      } else {
        Button {
          center.openWindow(session.row)
          close()
        } label: {
          Image(systemName: "arrow.up.forward.square")
        }.help("Open in tool window")
      }
      Button {
        center.togglePin(session)
      } label: {
        Image(systemName: session.pinned ? "pin.fill" : "pin")
      }.help(session.pinned ? "Unpin from menu bar" : "Pin process to menu bar")
      Menu {
        if session.pinned { Button("Show menu bar monitor") { center.showPin(session) } }
        Button("Export diagnostics…") { session.export() }
        ForEach(ProcessReportKind.allCases) { kind in
          Button(kind.rawValue) { session.collectReport(kind) }.disabled(
            session.reporting || session.exited)
        }
        Divider()
        Button("Copy PID") { copy(String(session.id.pid)) }
        Button("Quit process…", role: .destructive) { confirmStop = true }.disabled(
          session.exited || session.row.uid != getuid() || session.id.pid <= 1
            || session.id.pid == getpid())
      } label: {
        Image(systemName: "ellipsis")
      }.menuStyle(.borderlessButton).fixedSize().help("Process actions")
      Button(action: close) { Image(systemName: "xmark") }.help(
        toolWindow ? "Close tool window" : "Done")
    }.buttonStyle(MonitorIconButton(theme: theme)).padding(.horizontal, 20).frame(height: 78)
      .background(theme.toolbar)
  }
  private var contentHeader: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(session.tab.rawValue + (session.tab.metric != nil ? " activity" : ""))
          .font(.system(size: 24, weight: .semibold)).tracking(-0.6)
        Text(session.tab.subtitle).font(.system(size: 11)).foregroundStyle(theme.secondary)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      if session.tab.metric != nil {
        DiagnosticRangePicker(selection: $session.range, theme: theme)
      } else if session.tab != .overview && session.tab != .reports {
        TextField("Filter entries", text: $query).textFieldStyle(.roundedBorder).frame(width: 150)
        Button {
          exportSection()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .help("Export table as CSV").buttonStyle(MonitorIconButton(theme: theme))
      }
    }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
  }
  @ViewBuilder private var content: some View {
    if let metric = session.tab.metric {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(alignment: .firstTextBaseline) {
            Text(ProcessActivityPresentation.latest(session, metric: metric)).font(
              .system(size: 32, weight: .medium)
            ).monospacedDigit()
            Text(
              metric == .disk
                ? "read / second"
                : metric == .network
                  ? "received / second"
                  : metric == .energy
                    ? "CPU workload" : metric == .memory ? "physical footprint" : "process usage"
            ).foregroundStyle(theme.secondary)
          }
          TelemetryChart(
            samples: ProcessActivityPresentation.samples(session.histories, metric: metric),
            metric: metric, range: session.range, end: session.histories.last?.date ?? Date(),
            theme: theme, perProcess: true
          ).frame(height: 190)
          Text(ProcessActivityPresentation.note(metric)).font(.system(size: 11)).foregroundStyle(
            theme.secondary
          ).fixedSize(horizontal: false, vertical: true)
          Divider()
          fields(metricFields(metric))
          if metric == .memory { Button("Inspect memory mappings") { session.tab = .maps } }
          if metric == .network {
            Button("Inspect connections & listening ports") { session.tab = .connections }
          }
          if metric == .cpu { Button("Inspect threads") { session.tab = .threads } }
        }.padding(22)
      }
    } else if session.tab == .overview {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          fields(
            [
              .init("Process name", session.row.name),
              .init("Executable name", session.row.executableName ?? session.row.name),
            ] + session.fields)
          Divider()
          fields(
            ProcessColumns.catalog.filter { ["sandbox", "restricted", "ports"].contains($0.id) }.map
            { .init($0.title, ProcessValues.text(session.row, key: $0.id, metric: .cpu)) })
          Text("Related processes").font(.headline)
          ForEach(center.related(to: session)) { row in
            Button {
              center.openWindow(row)
            } label: {
              HStack {
                Text(row.name)
                Spacer()
                Text("PID \(row.id)")
                Image(systemName: "arrow.up.forward")
              }
            }.buttonStyle(.plain)
          }
          if center.related(to: session).isEmpty {
            Text("No parent or child process in the current snapshot.").foregroundStyle(
              theme.secondary)
          }
          Text(
            "Missing values mean macOS denied access or does not expose the counter. Detailed collections refresh every five seconds while this session is live."
          ).font(.system(size: 11)).foregroundStyle(theme.secondary)
        }.padding(22)
      }
    } else if session.tab == .reports {
      reports
    } else {
      VStack(alignment: .leading, spacing: 0) {
        if session.tab == .fileports {
          Text(
            "Fileports are file descriptors exported as Mach send rights. The descriptor type identifies the underlying file, socket, or pipe."
          ).font(.system(size: 11)).foregroundStyle(theme.secondary).padding(14)
        }
        if session.tab == .ports {
          Text(
            "Mach ports: \(session.row.details.ports.map(String.init) ?? "—") total. These are IPC rights, separate from TCP/UDP ports in Connections. macOS may allow a total while restricting enumeration."
          )
          .font(.system(size: 11)).foregroundStyle(theme.secondary).padding(14)
        }
        let section = session.sections[session.tab] ?? DiagnosticSection()
        if section.records.isEmpty {
          ContentUnavailableView(
            session.collecting ? "Collecting details" : "No readable entries",
            systemImage: session.tab.icon, description: Text(section.status)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          DiagnosticTable(
            section: section, query: query, key: session.tab.rawValue, theme: theme,
            persistColumns: persistTableColumns)
        }
        if let date = section.date {
          Text(
            "Snapshot \(date.formatted(date:.omitted,time:.standard)) · Right-click a column header to choose columns"
          ).font(.system(size: 10)).foregroundStyle(theme.secondary).padding(10)
        }
      }
    }
  }
  private func fields(_ values: [DiagnosticField]) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(values.enumerated()), id: \.offset) { index, field in
        HStack(alignment: .top, spacing: 18) {
          Text(field.name).foregroundStyle(theme.secondary).frame(width: 155, alignment: .leading)
          Text(field.value.isEmpty ? "—" : field.value).frame(
            maxWidth: .infinity, alignment: .leading
          ).textSelection(.enabled)
        }.font(.system(size: 12)).padding(.vertical, 8)
          .overlay(alignment: .bottom) { if index < values.count - 1 { Divider().opacity(0.4) } }
      }
    }
  }
  private func metricFields(_ metric: Metric) -> [DiagnosticField] {
    var values = ProcessActivityPresentation.keys(metric).compactMap { key in
      ProcessColumns.catalog.first { $0.id == key }.map {
        DiagnosticField($0.title, ProcessValues.text(session.row, key: key, metric: metric))
      }
    }
    let wanted: Set<String>
    switch metric {
    case .cpu:
      wanted = [
        "User CPU time", "System CPU time", "Priority", "Running threads", "Scheduling policy",
        "Mach messages sent", "Mach messages received", "Mach syscalls", "Unix syscalls",
        "Context switches",
      ]
    case .memory:
      wanted = [
        "Virtual memory", "Page faults", "Page-ins", "Copy-on-write faults", "Wired memory",
        "Peak physical footprint", "Interval peak footprint", "Real private memory",
        "Real shared memory", "Compressed memory", "Purgeable memory",
      ]
    case .energy:
      wanted = Set(
        session.fields.filter {
          $0.name.hasPrefix("Assertion") || $0.name == "Power assertions"
            || $0.name.contains("energy counter") || $0.name.contains("wake-ups")
        }.map(\.name))
    default: wanted = []
    }
    let extra = session.fields.filter { wanted.contains($0.name) }
    values.removeAll { value in extra.contains { $0.name == value.name } }
    values += extra
    if metric == .disk || metric == .network, let latest = session.histories.last {
      let outgoing = metric == .disk ? latest.written : latest.sent
      values.insert(
        .init(
          metric == .disk ? "Write rate" : "Send rate",
          outgoing.map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—"), at: 0)
    }
    return values
  }
  private var reports: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Menu("Collect report") {
          ForEach(ProcessReportKind.allCases) { kind in
            Button(kind.rawValue) { session.collectReport(kind) }
          }
        }.disabled(session.reporting || session.exited)
        if session.reporting {
          ProgressView().controlSize(.small)
          Button("Cancel") { session.cancelReport() }
        }
        Spacer()
        Button("Copy") { copy(session.report?.text ?? "") }.disabled(session.report == nil)
        Button("Save…") {
          do {
            try DiagnosticExport.save(
              Data((session.report?.text ?? "").utf8), name: "Process-\(session.id.pid)-report.txt")
          } catch { exportError = error.localizedDescription }
        }.disabled(session.report == nil)
      }
      if let report = session.report {
        Text("\(report.title) · \(report.status) · \(report.date.formatted())").font(
          .system(size: 11)
        ).foregroundStyle(theme.secondary)
        DiagnosticReportText(text: report.text, theme: theme)
      } else {
        ContentUnavailableView(
          "Process reports", systemImage: "doc.text.magnifyingglass",
          description: Text(
            "Collect a stack sample, open files, virtual memory, launch arguments, environment, or code-signing details. Reports are collected only when requested."
          )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.padding(18)
  }
  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  private func exportSection() {
    guard let section = session.sections[session.tab] else { return }
    let rows = section.records.filter {
      query.isEmpty || $0.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
    }
    let text =
      ([section.columns.map(csvCell).joined(separator: ",")]
      + rows.map { row in
        section.columns.map { csvCell(row.cells[$0] ?? "") }.joined(separator: ",")
      }).joined(separator: "\n")
    do {
      try DiagnosticExport.save(
        Data(text.utf8), name: "Process-\(session.id.pid)-\(session.tab.rawValue).csv")
    } catch { exportError = error.localizedDescription }
  }
}
struct ProcessPinView: View {
  @ObservedObject var session: ProcessDiagnosticSession
  let open: () -> Void
  let unpin: () -> Void
  @AppStorage("appearance") private var appearance = "System"
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    let theme = MonitorTheme(
      dark: appearance == "Dark" || appearance == "System" && scheme == .dark)
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(session.row.name).font(.headline).lineLimit(2)
        Spacer()
        Button(action: unpin) { Image(systemName: "pin.slash") }.help("Unpin process")
      }
      Text("PID \(session.id.pid) · \(session.state)").font(.caption).foregroundStyle(.secondary)
      Picker("Menu bar metric", selection: $session.pinMetric) {
        ForEach(Metric.allCases) { metric in Text(metric.rawValue).tag(metric) }
      }
      Text(ProcessActivityPresentation.latest(session, metric: session.pinMetric)).font(
        .system(size: 27, weight: .medium)
      ).monospacedDigit()
      TelemetryChart(
        samples: ProcessActivityPresentation.samples(session.histories, metric: session.pinMetric),
        metric: session.pinMetric, range: 1, end: session.histories.last?.date ?? Date(),
        theme: theme, perProcess: true
      ).frame(height: 115)
      HStack {
        Button(session.paused ? "Resume" : "Pause") { session.paused.toggle() }.disabled(
          session.exited)
        Spacer()
        Button("Open process monitor", action: open)
      }
    }.padding(18).frame(width: 360).background(theme.window)
      .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
  }
}
struct DiagnosticReportText: NSViewRepresentable {
  let text: String
  let theme: MonitorTheme
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    let view = NSTextView()
    view.isEditable = false
    view.isSelectable = true
    view.isRichText = false
    view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    view.isHorizontallyResizable = true
    view.isVerticallyResizable = true
    view.textContainer?.widthTracksTextView = false
    view.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.autoresizingMask = [.width]
    scroll.documentView = view
    updateNSView(scroll, context: context)
    return scroll
  }
  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let view = scroll.documentView as? NSTextView else { return }
    if view.string != text { view.string = text }
    view.backgroundColor = NSColor(theme.card)
    view.textColor = NSColor(theme.text)
  }
}
