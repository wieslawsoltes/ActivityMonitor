import AppKit
import SwiftUI

struct ContentView: View {
  @Environment(\.colorScheme) var colorScheme
  @EnvironmentObject var monitor: Monitor
  @EnvironmentObject var navigation: MonitorNavigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("showMenuBar") var showMenuBar = false
  @AppStorage("appearance") var appearance = "System"
  private static let machineName = Host.current().localizedName ?? "Mac"
  @StateObject var cpuPresentation = CPUChartPresentation()
  @AppStorage("processViewMode.v1") var processViewMode = ProcessViewMode.list
  @StateObject var processTree = ProcessTreePresentation()
  @State var metric: Metric = .cpu
  @State var range = 1
  @State var query = ""
  @State var filter = "All processes"
  @State var selection: Int32?
  @State var selectedIDs: Set<Int32> = []
  @State private var selectionFilterIDs: Set<Int32> = []
  @State var inspector = false
  @State var sort = "primary"
  @State var descending = true
  @State var stopTargets: [ProcessRow] = []
  @State var showHelp = false
  @State var showGallery = false
  @State private var diagnosticSession: ProcessDiagnosticSession?
  @State var searchExpanded = false
  @State var searchFocused = false
  @FocusState var tableFocused: Bool
  @AppStorage("showThreads") var showThreads = true
  @AppStorage("showUser") var showUser = true
  @AppStorage("showTime") var showTime = true
  @State var hoverDate: Date?
  var selected: ProcessRow? { monitor.rows.first { $0.id == selection } }
  @State private var filtered: [ProcessRow] = []
  private var visibleProcesses: [ProcessRow] {
    processViewMode == .tree ? processTree.entries.map(\.row) : filtered
  }
  private var visibleUsage: [Int32: ProcessSubtreeUsage]? {
    processViewMode == .tree ? processTree.snapshot.usageByID : nil
  }
  private func refreshPresentation(_ rows: [ProcessRow]? = nil) {
    let source = rows ?? monitor.rows
    filtered = processQuery.apply(source)
    if processViewMode == .tree {
      processTree.update(source, query: processQuery, matches: filtered)
    } else {
      processTree.retainIdentities(source)
    }
  }
  private var processQuery: ProcessQuery {
    ProcessQuery(
      metric: metric, query: query, filter: filter, sort: sort, descending: descending,
      selected: selectionFilterIDs)
  }
  private func selectMetric(_ value: Metric) {
    metric = value
    sort = value == .network ? "received" : "primary"
    descending = true
    filter = value == .energy ? "Applications" : "All processes"
  }
  var theme: MonitorTheme {
    MonitorTheme(dark: appearance == "Dark" || appearance == "System" && colorScheme == .dark)
  }
  var heading: String {
    switch metric {
    case .gpu: return "GPU activity"
    case .cpu: return "CPU activity"
    case .memory: return "Memory, in balance."
    case .energy: return "Every bit of energy."
    case .disk: return "Data in motion."
    case .network: return "Stay in the flow."
    }
  }
  var subheading: String {
    switch metric {
    case .gpu: return "Graphics and compute, across your Mac."
    case .cpu: return "A little clarity. A lot of processing power."
    case .memory: return "Understand how your Mac makes room for everything."
    case .energy: return "A closer look at the apps powering your day."
    case .disk: return "Follow every read, every write, and everything in between."
    case .network: return "See what’s coming in. Know what’s going out."
    }
  }
  var body: some View {
    GeometryReader { geometry in
      let layout = MonitorLayout(width: geometry.size.width, height: geometry.size.height)
      VStack(spacing: 0) {
        if layout.scrollsWorkspace {
          GeometryReader { viewport in
            ScrollView {
              workspace(layout, viewportHeight: viewport.size.height)
            }
          }
          // Keep scrolling content inside the workspace's safe-area viewport;
          // the transparent title bar is reserved for native toolbar controls.
          .clipped()
        } else {
          workspace(layout)
        }
        if layout.standard {
          statusbar
        } else {
          HStack {
            Text("\(filtered.count) processes")
            Spacer()
            Label(
              monitor.paused ? "Paused" : "Live",
              systemImage: monitor.paused ? "pause.fill" : "waveform.path.ecg")
            if let last = monitor.lastUpdate {
              Text(last.formatted(date: .omitted, time: .standard))
            }
          }.font(.system(size: 10)).foregroundStyle(theme.secondary).padding(
            .horizontal, layout.gutter
          )
          .frame(height: 32).background(theme.toolbar)
        }
      }
      .overlay(alignment: .trailing) {
        if inspector && !layout.inlineInspector {
          ZStack(alignment: .trailing) {
            Color.black.opacity(0.18).onTapGesture { inspector = false }
            inspectorPanel.frame(width: min(layout.width - 28, 360))
              .background {
                UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
                  .fill(theme.card).shadow(color: .black.opacity(0.18), radius: 18)
              }.padding(14)
              .transition(.move(edge: .trailing).combined(with: .opacity))
          }
        }
      }
      .toolbar { monitorToolbar(layout) }
      .modifier(MonitorWindowBackground(theme: theme))
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: inspector)
      .sheet(isPresented: $showGallery) {
        DesignGallery(
          availableSize: geometry.size,
          select: { view, style in
            selectMetric(view)
            appearance = style
            showGallery = false
          }, close: { showGallery = false }
        ).environmentObject(monitor)
      }
    }.background(theme.window).foregroundStyle(theme.text).font(.system(size: 12))
      .frame(minWidth: 420, minHeight: 480)
      .onReceive(navigation.$request) { request in
        guard let request else { return }
        selectMetric(request.metric)
        range = request.range
        if let pid = request.pid {
          query = ""
          filter = "All processes"
          selection = pid
          inspector = true
          refreshPresentation()
          if processViewMode == .tree { processTree.reveal(pid) }
        }
      }
      .onReceive(monitor.$rows) { rows in
        refreshPresentation(rows)
      }
      .onChange(of: filter) {
        if filter == "Selected processes" {
          selectionFilterIDs = selectedIDs
          refreshPresentation()
        }
      }
      .onChange(of: processQuery) { refreshPresentation() }
      .onChange(of: processViewMode) {
        refreshPresentation()
        if processViewMode == .tree, let selection { processTree.reveal(selection) }
      }
      .focusedSceneValue(
        \.processViewActions,
        ProcessViewActions(
          mode: $processViewMode, hasBranches: processTree.hasBranches,
          expandAll: processTree.expandAll, collapseAll: processTree.collapseAll)
      )
      .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
      .alert(
        stopTargets.count == 1
          ? "Stop \(stopTargets[0].name)?" : "Stop \(stopTargets.count) processes?",
        isPresented: Binding(get: { !stopTargets.isEmpty }, set: { if !$0 { stopTargets = [] } })
      ) {
        Button("Cancel", role: .cancel) { stopTargets = [] }
        Button("Quit", role: .destructive) {
          for p in stopTargets { monitor.terminate(p, force: false) }
          stopTargets = []
        }
        Button("Force Quit", role: .destructive) {
          for p in stopTargets { monitor.terminate(p, force: true) }
          stopTargets = []
        }
      } message: {
        Text(
          "Quit requests a normal exit. Force Quit stops the process immediately and may lose unsaved work."
        )
      }
      .alert(
        "Activity Monitor",
        isPresented: Binding(get: { monitor.error != nil }, set: { if !$0 { monitor.error = nil } })
      ) {
        Button("OK") { monitor.error = nil }
      } message: {
        Text(monitor.error ?? "")
      }
      .sheet(item: $diagnosticSession) { session in
        ProcessDiagnosticsView(
          session: session, center: monitor.diagnostics, close: { diagnosticSession = nil }
        )
        .frame(width: 1000, height: 700)
        .onDisappear { monitor.diagnostics.release(session) }
      }
      .sheet(isPresented: $showHelp) {
        VStack(alignment: .leading, spacing: 18) {
          Text("A clearer view of your Mac").font(.title2.bold())
          Text(
            "⌘1–6  Switch views\n⌘K  Search processes\nSpace  Pause or resume\n⌘⇧E  Export process CSV\nDouble-click a process to inspect it"
          ).lineSpacing(8)
          Text(
            "CPU percentages are measured between samples. A process can exceed 100% when using multiple cores. Disk rates include readable processes; network counters aggregate non-loopback interfaces and can include VPN traffic. Process GPU rates use driver execution-time counters across all reporting devices and can exceed 100% when work overlaps. GPU time is observed during this session. Restricted or unsupported counters appear as —."
          ).foregroundStyle(.secondary)
          Button("Done") { showHelp = false }.keyboardShortcut(.defaultAction)
        }.padding(32).frame(width: min(510, max(360, (NSApp.mainWindow?.frame.width ?? 560) - 48)))
      }
      .background {
        Group {
          Button("") { searchExpanded = true }.keyboardShortcut("k")
          ForEach(Array(Metric.allCases.enumerated()), id: \.offset) { index, item in
            Button("") { selectMetric(item) }.keyboardShortcut(
              KeyEquivalent(Character(String(index + 1))))
          }
        }.hidden()
      }
  }
  @ViewBuilder func workspace(_ layout: MonitorLayout, viewportHeight: CGFloat? = nil) -> some View
  {
    let container =
      viewportHeight.map { AnyLayout(WorkspaceLayout(viewportHeight: $0)) }
      ?? AnyLayout(VStackLayout(spacing: 0))
    container {
      overviewControls(layout)
        .padding(.top, 8)
      MonitorOverview(
        metric: metric, range: range, theme: theme,
        width: layout.width - layout.gutter * 2, expanded: layout.expanded,
        condensed: layout.denseOverview, cpuPresentation: cpuPresentation,
        viewportHeight: viewportHeight ?? max(0, layout.height - 120)
      )
      .padding(.bottom, layout.denseOverview ? 10 : 24)
      HStack(spacing: 16) {
        MonitorProcessTable(
          rows: filtered, metric: metric, theme: theme, query: $query, filter: $filter,
          mode: $processViewMode, tree: processTree, sourceRows: monitor.rows,
          selection: $selection, selectedIDs: $selectedIDs, inspector: $inspector, sort: $sort,
          descending: $descending,
          inspect: { p in
            selection = p.id
            inspector = true
          }, stop: { stopTargets = [$0] }, stopMany: { stopTargets = $0 },
          searchFocus: $searchFocused, searchExpanded: $searchExpanded, diagnose: openDiagnostics)
        if inspector && layout.inlineInspector {
          inspectorPanel.frame(width: layout.inspectorWidth)
        }
      }.frame(maxHeight: .infinity)
    }.padding(.horizontal, layout.gutter)
  }
  var inspectorPanel: some View {
    MonitorInspector(
      process: selected, theme: theme, busy: false, close: { inspector = false },
      sample: sample, files: inspectFiles, reveal: reveal, stop: { stopTargets = [$0] },
      diagnose: openDiagnostics)
  }
  @ToolbarContentBuilder
  func monitorToolbar(_ layout: MonitorLayout) -> some ToolbarContent {
    if MonitorToolbarLayout(width: layout.width).showsBrand {
      ToolbarItem(placement: .navigation) {
        BrandMark(size: 24)
          .help("Activity Monitor · \(Self.machineName) · \(architectureLabel)")
          .accessibilityLabel("Activity Monitor, \(Self.machineName), \(architectureLabel)")
      }
    }
    if #available(macOS 26, *) {
      metricToolbarItem(layout).sharedBackgroundVisibility(.hidden)
    } else {
      metricToolbarItem(layout)
    }
    if #available(macOS 26, *) {
      actionToolbarItem(layout).sharedBackgroundVisibility(.hidden)
    } else {
      actionToolbarItem(layout)
    }
  }
  private func actionToolbarItem(_ layout: MonitorLayout) -> some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      HStack(spacing: 4) {
        Button {
          monitor.paused.toggle()
        } label: {
          Image(systemName: monitor.paused ? "play" : "pause")
        }
        .buttonStyle(MonitorIconButton(theme: theme))
        .help(monitor.paused ? "Resume" : "Pause")
        .accessibilityLabel(monitor.paused ? "Resume monitoring" : "Pause monitoring")
        if MonitorToolbarLayout(width: layout.width).showsExpandedActions {
          Button {
            monitor.export(
              visibleProcesses, includeHierarchy: processViewMode == .tree, usage: visibleUsage)
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .buttonStyle(MonitorIconButton(theme: theme)).help("Export visible processes")
          Button {
            showGallery = true
          } label: {
            Image(systemName: "square.grid.2x2")
          }
          .buttonStyle(MonitorIconButton(theme: theme)).help("All views & themes")
          HStack(spacing: 2) {
            appearanceButton("Light", "sun.max")
            appearanceButton("Dark", "moon")
            appearanceButton("System", "desktopcomputer")
          }
          .padding(3)
          .background(theme.recessed, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.separator, lineWidth: 1))
        }
        Menu {
          settingsMenu
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 14))
            .foregroundStyle(theme.secondary).frame(width: 32, height: 32)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("More").accessibilityLabel("More")
        .accessibilityIdentifier("monitor-settings")
      }
      .frame(height: 34).fixedSize()
      .accessibilityElement(children: .contain)
    }
  }
  private func appearanceButton(_ name: String, _ icon: String) -> some View {
    Button {
      appearance = name
    } label: {
      Image(systemName: icon).font(.system(size: 13))
        .foregroundStyle(appearance == name ? theme.blue : theme.tertiary)
        .frame(width: 28, height: 26)
    }
    .buttonStyle(MonitorSegmentButton(theme: theme, active: appearance == name, radius: 6))
    .help("\(name) appearance").accessibilityLabel("\(name) appearance")
    .accessibilityAddTraits(appearance == name ? .isSelected : [])
  }
  private func metricToolbarItem(_ layout: MonitorLayout) -> some ToolbarContent {
    ToolbarItem(placement: .principal) {
      ToolbarMetricPicker(
        metric: Binding(get: { metric }, set: selectMetric), theme: theme,
        compact: !MonitorToolbarLayout(width: layout.width).showsLabels)
    }
  }
  @ViewBuilder private var settingsMenu: some View {
    Button("Export visible processes…") {
      monitor.export(
        visibleProcesses, includeHierarchy: processViewMode == .tree, usage: visibleUsage)
    }
    Button("Export JSON snapshot…") {
      monitor.exportJSON(visibleProcesses, usage: visibleUsage)
    }
    Button("Export GPU snapshot & history…") {
      monitor.exportGPU(visibleProcesses, usage: visibleUsage)
    }
    Divider()
    Picker("Appearance", selection: $appearance) {
      Text("Light").tag("Light")
      Text("Dark").tag("Dark")
      Text("System").tag("System")
    }
    Toggle("Show monitor in menu bar", isOn: $showMenuBar)
    Picker("Update interval", selection: $monitor.interval) {
      Text("Every second").tag(1.0)
      Text("Every 2 seconds").tag(2.0)
      Text("Every 5 seconds").tag(5.0)
    }
    Divider()
    Button("All views & themes") { showGallery = true }
    UpdateCommands()
    Divider()
    Button("Keyboard shortcuts & data notes") { showHelp = true }
  }
  /// One control row leaves chart and process space unchanged across overview modes.
  func overviewControls(_ layout: MonitorLayout) -> some View {
    HStack(spacing: 8) {
      if metric == .gpu {
        GPUDevicePicker(theme: theme)
      } else {
        Text(metric.rawValue + " activity")
          .font(.system(size: 15, weight: .semibold)).tracking(-0.3).lineLimit(1)
      }
      DiagnosticInfoButton(title: heading, text: subheading, theme: theme)
      Spacer(minLength: 0)
      HStack(spacing: 5) {
        Image(systemName: monitor.paused ? "pause.circle" : "circle.fill")
          .font(.system(size: monitor.paused ? 11 : 6))
        if !layout.compact {
          Text(monitor.paused ? "Paused" : "Live")
            .font(.system(size: 10, weight: .medium))
        }
      }
      .foregroundStyle(monitor.paused ? theme.secondary : theme.green)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(monitor.paused ? "Monitoring paused" : "Live monitoring")
      .help(monitor.paused ? "Monitoring paused" : "Live monitoring")
      HistoryRangePicker(range: $range, theme: theme)
        .fixedSize()
    }.frame(height: 42)
  }
  var statusbar: some View {
    HStack(spacing: 10) {
      Text("\(filtered.count) processes")
      Text("·").foregroundStyle(theme.tertiary)
      Label(
        monitor.paused ? "Snapshot paused" : "Live system data", systemImage: "waveform.path.ecg")
      if metric == .gpu {
        Text("·")
        Text(
          "Process GPU counters across all devices · \(monitor.rows.filter { $0.gpuPercent != nil }.count) reporting"
        )
        .foregroundStyle(theme.tertiary)
      }
      if metric == .network || metric == .energy {
        Text("·")
        Text(
          metric == .network
            ? "Process network updates every 5 sec"
            : "CPU workload shown; Energy Impact unavailable"
        ).foregroundStyle(theme.tertiary)
      }
      Spacer()
      if let last = monitor.lastUpdate { Text(last.formatted(date: .omitted, time: .standard)) }
      Text("·")
      Text("\(architectureLabel) · \(bytes(monitor.system.physical)) memory")
    }.font(.system(size: 10)).foregroundStyle(theme.secondary).padding(.horizontal, 26).frame(
      height: 36
    ).background(theme.toolbar).overlay(alignment: .top) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
  }
  var architectureLabel: String {
    #if arch(arm64)
      return "Apple silicon"
    #else
      return "Intel"
    #endif
  }
  func reveal(_ p: ProcessRow) {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(p.id, &buffer, UInt32(buffer.count)) > 0 else {
      monitor.error = "The executable path is unavailable for this process."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: String(cString: buffer))])
  }
  func openDiagnostics(_ p: ProcessRow, toolWindow: Bool = false) {
    if toolWindow {
      monitor.diagnostics.openWindow(p)
    } else {
      diagnosticSession = monitor.diagnostics.acquire(p)
    }
  }
  func inspectFiles(_ p: ProcessRow) {
    openDiagnostics(p)
    diagnosticSession?.tab = .files
    diagnosticSession?.refreshDetails(force: true)
  }
  func sample(_ p: ProcessRow) {
    openDiagnostics(p)
    diagnosticSession?.collectReport(.sample)
  }
}
