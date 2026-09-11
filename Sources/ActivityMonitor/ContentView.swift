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
  @FocusState var searchFocused: Bool
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
        adaptiveTitlebar(layout)
        if layout.scrollsWorkspace {
          GeometryReader { viewport in
            ScrollView {
              workspace(layout, viewportHeight: viewport.size.height)
            }
          }
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
      .frame(minWidth: 420, minHeight: 480).ignoresSafeArea(.container, edges: .top)
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
          Button("") { searchFocused = true }.keyboardShortcut("k")
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
      if !layout.denseOverview {
        sectionHeading.padding(.top, 23).padding(.bottom, 20)
      } else {
        HStack(spacing: 8) {
          if metric == .gpu {
            GPUDevicePicker(theme: theme)
          } else {
            Text(metric.rawValue + " activity")
              .font(.system(size: 18, weight: .semibold)).tracking(-0.4)
          }
          Spacer(minLength: 4)
          HistoryRangePicker(range: $range, theme: theme)
        }.padding(.vertical, 6)
      }
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
          searchFocus: $searchFocused, diagnose: openDiagnostics)
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
  @ViewBuilder func adaptiveTitlebar(_ layout: MonitorLayout) -> some View {
    if layout.width >= 1350 {
      titlebar
    } else {
      VStack(spacing: 0) {
        ZStack {
          WindowChrome()
          HStack(spacing: 12) {
            TrafficLights()
            Text("Activity Monitor").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Button {
              monitor.paused.toggle()
            } label: {
              Image(systemName: monitor.paused ? "play" : "pause")
            }
            .buttonStyle(MonitorIconButton(theme: theme)).help(monitor.paused ? "Resume" : "Pause")
            SettingsMenuButton { settingsMenu(compact: true) }
              .frame(width: 32, height: 32)
          }.padding(.horizontal, layout.gutter)
          if layout.standard {
            MetricSwitcher(metric: Binding(get: { metric }, set: selectMetric), theme: theme)
          }
        }.frame(height: layout.standard ? 78 : 44)
        if !layout.standard {
          MetricSwitcher(
            metric: Binding(get: { metric }, set: selectMetric), theme: theme,
            compact: layout.compact
          )
          .padding(.horizontal, layout.gutter).padding(.bottom, 4)
        }
      }.background(theme.toolbar).overlay(alignment: .bottom) {
        Rectangle().fill(theme.border).frame(height: 1)
      }
    }
  }
  var titlebar: some View {
    ZStack {
      WindowChrome()
      HStack(spacing: 0) {
        HStack(spacing: 14) {
          TrafficLights()
          HStack(spacing: 10) {
            BrandMark()
            VStack(alignment: .leading, spacing: 2) {
              Text("Activity Monitor").font(.system(size: 13, weight: .semibold))
              Text("\(Self.machineName) · \(architectureLabel)").font(
                .system(size: 10)
              ).foregroundStyle(theme.secondary)
            }
          }
        }
        Spacer(minLength: 12)
        HStack(spacing: 3) {
          ForEach(Metric.allCases) { item in
            Button {
              selectMetric(item)
            } label: {
              HStack(spacing: 7) {
                Image(systemName: item.icon).font(.system(size: 13)).foregroundStyle(
                  item == metric ? theme.blue : theme.secondary)
                Text(item.rawValue).font(.system(size: 13, weight: .medium))
              }.padding(.horizontal, 10).frame(height: 34)
            }.buttonStyle(MonitorSegmentButton(theme: theme, active: item == metric))
              .accessibilityAddTraits(item == metric ? .isSelected : []).help(
                "\(item.rawValue) · ⌘\(Metric.allCases.firstIndex(of:item)!+1)")
          }
        }.padding(4).background(theme.recessed, in: RoundedRectangle(cornerRadius: 11)).overlay(
          RoundedRectangle(cornerRadius: 11).stroke(theme.separator, lineWidth: 1))
        Spacer(minLength: 12)
        HStack(spacing: 5) {
          Button {
            monitor.paused.toggle()
          } label: {
            Image(systemName: monitor.paused ? "play" : "pause")
          }.buttonStyle(MonitorIconButton(theme: theme)).help(monitor.paused ? "Resume" : "Pause")
          Button {
            monitor.export(
              visibleProcesses, includeHierarchy: processViewMode == .tree, usage: visibleUsage)
          } label: {
            Image(systemName: "square.and.arrow.up")
          }.buttonStyle(MonitorIconButton(theme: theme)).help("Export visible processes")
          Button {
            showGallery = true
          } label: {
            Image(systemName: "square.grid.2x2")
          }.buttonStyle(MonitorIconButton(theme: theme)).help("All views & themes")
          Rectangle().fill(theme.border).frame(width: 1, height: 20).padding(.horizontal, 6)
          HStack(spacing: 2) {
            appearanceButton("Light", "sun.max")
            appearanceButton("Dark", "moon")
            appearanceButton("System", "desktopcomputer")
          }.padding(3).overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border, lineWidth: 1))
          SettingsMenuButton { settingsMenu(compact: false) }
            .frame(width: 32, height: 32)
        }
      }.padding(.horizontal, 23)

    }.frame(height: 78).background(theme.toolbar).overlay(alignment: .bottom) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
  }
  private func settingsMenu(compact: Bool) -> NSMenu {
    let menu = NSMenu()
    if compact {
      menu.addSettingsAction("Export visible processes…") {
        monitor.export(
          visibleProcesses, includeHierarchy: processViewMode == .tree, usage: visibleUsage)
      }
    }
    menu.addSettingsAction("Export JSON snapshot…") {
      monitor.exportJSON(visibleProcesses, usage: visibleUsage)
    }
    menu.addSettingsAction("Export GPU snapshot & history…") {
      monitor.exportGPU(visibleProcesses, usage: visibleUsage)
    }
    menu.addItem(.separator())
    if compact { menu.addAppearance($appearance) }
    menu.addSettingsToggle("Show monitor in menu bar", selection: $showMenuBar)
    menu.addUpdateInterval($monitor.interval)
    if compact { menu.addItem(.separator()) }
    if compact { menu.addSettingsAction("All views & themes") { showGallery = true } }
    menu.addSettingsAction("Keyboard shortcuts & data notes") { showHelp = true }
    return menu
  }
  func appearanceButton(_ name: String, _ icon: String) -> some View {
    Button {
      appearance = name
    } label: {
      Image(systemName: icon).font(.system(size: 13)).foregroundStyle(
        appearance == name ? theme.blue : theme.tertiary
      ).frame(width: 28, height: 26)
    }.buttonStyle(MonitorSegmentButton(theme: theme, active: appearance == name, radius: 6)).help(
      "\(name) appearance"
    ).accessibilityLabel("\(name) appearance")
      .accessibilityAddTraits(appearance == name ? .isSelected : [])
  }
  var sectionHeading: some View {
    HStack {
      VStack(alignment: .leading, spacing: 6) {
        Text(heading).font(.system(size: 27, weight: .semibold)).tracking(-0.85)
        Text(subheading).font(.system(size: 13)).foregroundStyle(theme.secondary)
      }
      Spacer()
      if metric == .gpu {
        Menu {
          if monitor.gpuDevices.isEmpty { Text("No GPU detected") }
          ForEach(monitor.gpuDevices) { device in
            Button {
              monitor.selectedGPU = device.id
            } label: {
              if monitor.gpuDevice?.id == device.id {
                Label(
                  device.name + (device.connected ? "" : " · disconnected"),
                  systemImage: "checkmark")
              } else {
                Text(device.name + (device.connected ? "" : " · disconnected"))
              }
            }
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "square.3.layers.3d")
            Text(monitor.gpuDevice?.name ?? "No GPU detected").lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8))
          }.font(.system(size: 11)).foregroundStyle(theme.secondary).padding(.horizontal, 10).frame(
            height: 28
          )
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(
          "Choose GPU for the overview; process counters include all reporting devices")
      }
      HStack(spacing: 6) {
        Circle().fill(monitor.paused ? theme.secondary : theme.green).frame(width: 5, height: 5)
        Text(monitor.paused ? "Monitoring paused" : "Live monitoring").font(
          .system(size: 10, weight: .medium)
        ).foregroundStyle(monitor.paused ? theme.secondary : theme.green)
      }.padding(.horizontal, 10).frame(height: 28).background(
        monitor.paused ? theme.recessed : theme.green.opacity(0.1),
        in: RoundedRectangle(cornerRadius: 6)
      ).padding(.trailing, 8)
      HStack(spacing: 2) {
        ForEach([1, 5, 15], id: \.self) { value in
          Button {
            range = value
          } label: {
            Text("\(value) min").font(.system(size: 10)).frame(width: 44, height: 24)
          }.buttonStyle(MonitorSegmentButton(theme: theme, active: range == value, radius: 5))
            .accessibilityAddTraits(range == value ? .isSelected : [])
        }
      }.padding(3).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
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
