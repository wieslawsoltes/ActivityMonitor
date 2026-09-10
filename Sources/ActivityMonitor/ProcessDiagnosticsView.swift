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
      }
    }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
  }
  @ViewBuilder private var content: some View {
    if let metric = session.tab.metric {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          activityChart(metric)
          DiagnosticPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
              panelTitle("Process counters", icon: metric.icon)
              fields(metricFields(metric))
              if metric == .memory { detailLink("Inspect memory mappings", tab: .maps) }
              if metric == .network {
                detailLink("Inspect connections & listening ports", tab: .connections)
              }
              if metric == .disk { detailLink("Inspect open files", tab: .files) }
              if metric == .cpu { detailLink("Inspect threads", tab: .threads) }
            }
          }
        }.padding(.horizontal, 22).padding(.bottom, 22)
      }
    } else if session.tab == .overview {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          DiagnosticPanel(theme: theme) {
            HStack(spacing: 18) {
              summaryValue(
                "CPU usage", value: ProcessActivityPresentation.latest(session, metric: .cpu))
              Rectangle().fill(theme.border).frame(width: 1)
              summaryValue(
                "Memory", value: ProcessActivityPresentation.latest(session, metric: .memory))
              Rectangle().fill(theme.border).frame(width: 1)
              summaryValue(
                "Threads", value: ProcessValues.text(session.row, key: "threads", metric: .cpu))
            }.frame(height: 58)
          }
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 285), spacing: 16, alignment: .top)],
            alignment: .leading, spacing: 16
          ) {
            ForEach(overviewGroups, id: \.title) { group in
              DiagnosticPanel(theme: theme) {
                VStack(alignment: .leading, spacing: 14) {
                  panelTitle(group.title, icon: group.icon)
                  fields(group.fields, compact: true)
                }
              }
            }
          }
          DiagnosticPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
              panelTitle("Related processes", icon: "point.3.connected.trianglepath.dotted")
              ForEach(center.related(to: session)) { row in
                Button {
                  center.openWindow(row)
                } label: {
                  HStack(spacing: 10) {
                    ProcessIcon(pid: row.id, isApp: row.isApp, start: row.start, size: 24)
                    Text(row.name).lineLimit(1)
                    Spacer()
                    Text("PID \(row.id)").foregroundStyle(theme.secondary)
                    Image(systemName: "arrow.up.forward").foregroundStyle(theme.tertiary)
                  }.font(.system(size: 12)).padding(8)
                }.buttonStyle(MonitorSegmentButton(theme: theme))
              }
              if center.related(to: session).isEmpty {
                Text("No parent or child process in the current snapshot.")
                  .font(.system(size: 12)).foregroundStyle(theme.secondary)
              }
            }
          }
          Text("Unavailable values mean macOS restricts access or does not expose the counter.")
            .font(.system(size: 11)).foregroundStyle(theme.tertiary)
        }.padding(.horizontal, 22).padding(.bottom, 22)
      }
    } else if session.tab == .reports {
      reports
    } else {
      tablePage
    }
  }
  private var tablePage: some View {
    let section = session.sections[session.tab] ?? DiagnosticSection()
    let count = section.records.filter {
      query.isEmpty || $0.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
    }.count
    return DiagnosticPanel(theme: theme, padding: 0) {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Text("Entries").font(.system(size: 13, weight: .semibold))
          Text(count.formatted()).font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.secondary).padding(.horizontal, 6).padding(.vertical, 3)
            .background(theme.subtle, in: RoundedRectangle(cornerRadius: 4))
          Spacer(minLength: 0)
          HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.tertiary)
            TextField("Filter entries", text: $query).textFieldStyle(.plain)
              .accessibilityLabel("Filter entries")
            if !query.isEmpty {
              Button {
                query = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.plain).foregroundStyle(theme.tertiary).help("Clear filter")
            }
          }.font(.system(size: 11)).padding(.horizontal, 10).frame(width: 170, height: 31)
            .background(theme.subtle, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1))
          Button {
            exportSection()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .buttonStyle(MonitorIconButton(theme: theme)).help("Export table as CSV")
          .disabled(section.records.isEmpty)
        }.padding(.horizontal, 16).frame(height: 58)
        Rectangle().fill(theme.border).frame(height: 1)
        if section.records.isEmpty {
          diagnosticEmpty(
            session.collecting ? "Collecting details" : "No readable entries",
            message: section.status, icon: session.tab.icon)
        } else {
          DiagnosticTable(
            section: section, query: query, key: session.tab.rawValue, theme: theme,
            persistColumns: persistTableColumns
          )
          .overlay {
            if count == 0 {
              diagnosticEmpty(
                "No matching entries", message: "Try a different name, path or value.",
                icon: "magnifyingglass"
              )
              .allowsHitTesting(false).padding(.top, 34)
            }
          }
        }
        Rectangle().fill(theme.border).frame(height: 1)
        VStack(alignment: .leading, spacing: 4) {
          Text(section.status).lineLimit(2).help(section.status)
          if let date = section.date {
            Text(
              "Snapshot \(date.formatted(date:.omitted,time:.standard)) · Right-click a header to choose columns"
            )
            .foregroundStyle(theme.tertiary)
          }
        }.font(.system(size: 10)).foregroundStyle(theme.secondary)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(
            .vertical, 10
          )
          .background(theme.subtle)
      }.frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }.padding(.horizontal, 22).padding(.bottom, 22)
  }
  private func diagnosticEmpty(_ title: String, message: String, icon: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(
        theme.tertiary
      )
      .padding(.bottom, 4)
      Text(title).font(.system(size: 16, weight: .semibold))
      Text(message).font(.system(size: 12)).foregroundStyle(theme.secondary)
        .multilineTextAlignment(.center).frame(maxWidth: 330)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.card)
  }
  private func panelTitle(_ title: String, icon: String) -> some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold))
      Spacer()
      Image(systemName: icon).font(.system(size: 15)).foregroundStyle(theme.tertiary)
    }
  }
  private func summaryValue(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(value).font(.system(size: 25, weight: .medium)).tracking(-0.6).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(label).font(.system(size: 11)).foregroundStyle(theme.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func detailLink(_ title: String, tab: DiagnosticTab) -> some View {
    Button {
      session.tab = tab
    } label: {
      HStack {
        Text(title)
        Spacer()
        Image(systemName: "arrow.right")
      }.padding(.horizontal, 12)
    }.buttonStyle(MonitorActionButton(theme: theme))
  }
  private func activityChart(_ metric: Metric) -> some View {
    DiagnosticPanel(theme: theme) {
      VStack(alignment: .leading, spacing: 14) {
        if metric == .disk || metric == .network {
          HStack(spacing: 30) {
            summaryValue(
              metric == .disk ? "Read / second" : "Receiving / second",
              value: ProcessActivityPresentation.latest(session, metric: metric))
            summaryValue(
              metric == .disk ? "Write / second" : "Sending / second",
              value: (metric == .disk
                ? session.histories.last?.written : session.histories.last?.sent)
                .map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—")
          }
        } else {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
              Text(
                metric == .memory
                  ? "Physical footprint"
                  : metric == .energy ? "CPU workload" : "Process \(metric.rawValue) usage"
              )
              .font(.system(size: 12)).foregroundStyle(theme.secondary)
              Text(ProcessActivityPresentation.latest(session, metric: metric))
                .font(.system(size: 34, weight: .medium)).tracking(-1).monospacedDigit()
            }
            Spacer()
            Circle().fill(theme.blue).frame(width: 6, height: 6).padding(.top, 5)
            Text(metric == .energy ? "Workload" : "Process").font(.system(size: 10))
              .foregroundStyle(theme.secondary).padding(.top, 2)
          }
        }
        TelemetryChart(
          samples: ProcessActivityPresentation.samples(session.histories, metric: metric),
          metric: metric, range: session.range, end: session.histories.last?.date ?? Date(),
          theme: theme, perProcess: true
        ).frame(height: 155)
        Text(ProcessActivityPresentation.note(metric)).font(.system(size: 10))
          .foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
  private var overviewGroups: [DiagnosticFieldGroup] {
    let identity = [
      DiagnosticField("Process name", session.row.name),
      DiagnosticField("Executable name", session.row.executableName ?? session.row.name),
    ]
    let security = ProcessColumns.catalog.filter {
      ["sandbox", "restricted", "ports"].contains($0.id)
    }.map {
      DiagnosticField($0.title, ProcessValues.text(session.row, key: $0.id, metric: .cpu))
    }
    return DiagnosticFieldGroup.organize(identity + session.fields + security)
  }
  private func fields(_ values: [DiagnosticField], compact: Bool = false) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(values.enumerated()), id: \.offset) { index, field in
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(field.name).foregroundStyle(theme.secondary).fixedSize()
            Spacer(minLength: 12)
            Text(field.value.isEmpty ? "—" : field.value).fixedSize()
          }
          VStack(alignment: .leading, spacing: 5) {
            Text(field.name).foregroundStyle(theme.secondary)
            Text(field.value.isEmpty ? "—" : field.value).fixedSize(
              horizontal: false, vertical: true)
          }
        }.font(.system(size: 12)).monospacedDigit().textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, compact ? 9 : 10)
          .overlay(alignment: .bottom) {
            if index < values.count - 1 { Rectangle().fill(theme.separator).frame(height: 1) }
          }
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
    DiagnosticPanel(theme: theme, padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Menu {
            ForEach(ProcessReportKind.allCases) { kind in
              Button(kind.rawValue) { session.collectReport(kind) }
            }
          } label: {
            Label("Collect report", systemImage: "doc.badge.plus")
              .font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).frame(height: 32)
              .background(theme.subtle, in: RoundedRectangle(cornerRadius: 7))
          }.menuStyle(.borderlessButton).fixedSize().disabled(session.reporting || session.exited)
          if session.reporting {
            ProgressView().controlSize(.small)
            Button("Cancel") { session.cancelReport() }
              .buttonStyle(MonitorActionButton(theme: theme)).frame(width: 65)
          }
          Spacer(minLength: 4)
          Button {
            copy(session.report?.text ?? "")
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .buttonStyle(MonitorIconButton(theme: theme)).help("Copy report").disabled(
            session.report == nil)
          Button {
            do {
              try DiagnosticExport.save(
                Data((session.report?.text ?? "").utf8),
                name: "Process-\(session.id.pid)-report.txt")
            } catch { exportError = error.localizedDescription }
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .buttonStyle(MonitorIconButton(theme: theme)).help("Save report").disabled(
            session.report == nil)
        }.padding(.horizontal, 16).frame(height: 58)
        Rectangle().fill(theme.border).frame(height: 1)
        if let report = session.report {
          HStack {
            Text(report.title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(report.status).font(.system(size: 10)).foregroundStyle(theme.secondary)
          }.padding(16).background(theme.subtle)
          DiagnosticReportText(text: report.text, theme: theme)
          Rectangle().fill(theme.border).frame(height: 1)
          Text("Collected \(report.date.formatted())").font(.system(size: 10))
            .foregroundStyle(theme.tertiary).padding(12)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              Text("Choose a report").font(.system(size: 15, weight: .semibold))
              Text("Reports are collected on request and can be copied or saved.")
                .font(.system(size: 12)).foregroundStyle(theme.secondary)
              ForEach(ProcessReportKind.allCases) { kind in
                Button {
                  session.collectReport(kind)
                } label: {
                  HStack(spacing: 12) {
                    Image(systemName: "doc.text").foregroundStyle(theme.blue).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                      Text(kind.rawValue).font(.system(size: 12, weight: .medium))
                      Text(kind.summary).font(.system(size: 11)).foregroundStyle(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(theme.tertiary)
                  }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(MonitorSegmentButton(theme: theme))
                  .disabled(session.reporting || session.exited)
              }
            }.padding(20)
          }
        }
      }.frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 14))
    }.padding(.horizontal, 22).padding(.bottom, 22)
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
    view.textContainerInset = NSSize(width: 16, height: 16)
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
