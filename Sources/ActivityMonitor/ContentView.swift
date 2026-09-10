import AppKit
import SwiftUI

struct ContentView: View {
  @Environment(\.colorScheme) var colorScheme
  @EnvironmentObject var monitor: Monitor
  @EnvironmentObject var navigation: MonitorNavigation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("showMenuBar") var showMenuBar = false
  @AppStorage("appearance") var appearance = "System"
  @State var metric: Metric = .cpu
  @State var range = 1
  @State var query = ""
  @State var filter = "All processes"
  @State var selection: Int32?
  @State var inspector = false
  @State var sort = "primary"
  @State var descending = true
  @State var stopTarget: ProcessRow?
  @State var showHelp = false
  @State var showGallery = false
  @State var sampling = false
  @State var sampleText: String?
  @FocusState var searchFocused: Bool
  @FocusState var tableFocused: Bool
  @AppStorage("showThreads") var showThreads = true
  @AppStorage("showUser") var showUser = true
  @AppStorage("showTime") var showTime = true
  @State var hoverDate: Date?
  var selected: ProcessRow? { monitor.rows.first { $0.id == selection } }
  @State private var filtered: [ProcessRow] = []
  private func refreshPresentation(_ rows: [ProcessRow]? = nil) {
    filtered = processQuery.apply(rows ?? monitor.rows)
  }
  private var processQuery: ProcessQuery {
    ProcessQuery(metric: metric, query: query, filter: filter, sort: sort, descending: descending)
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
          ScrollView {
            workspace(layout, scrolling: true)
          }
        } else {
          workspace(layout, scrolling: false)
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
              .padding(14).shadow(color: .black.opacity(0.18), radius: 18)
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
        }
      }
      .onReceive(monitor.$rows) { rows in
        refreshPresentation(rows)
      }
      .onChange(of: processQuery) { refreshPresentation() }
      .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
      .alert(
        "Stop \(stopTarget?.name ?? "process")?",
        isPresented: Binding(get: { stopTarget != nil }, set: { if !$0 { stopTarget = nil } })
      ) {
        Button("Cancel", role: .cancel) { stopTarget = nil }
        Button("Quit", role: .destructive) {
          if let p = stopTarget { monitor.terminate(p, force: false) }
          stopTarget = nil
        }
        Button("Force Quit", role: .destructive) {
          if let p = stopTarget { monitor.terminate(p, force: true) }
          stopTarget = nil
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
      .sheet(isPresented: Binding(get: { sampleText != nil }, set: { if !$0 { sampleText = nil } }))
    {
      VStack {
        HStack {
          Text("Process sample").font(.headline)
          Spacer()
          Button("Save…") { saveSample() }
          Button("Done") { sampleText = nil }
        }
        ScrollView {
          Text(sampleText ?? "").font(.system(size: 11, design: .monospaced)).textSelection(
            .enabled
          ).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(24).frame(
        width: min(850, max(360, (NSApp.mainWindow?.frame.width ?? 900) - 48)),
        height: min(600, max(360, (NSApp.mainWindow?.frame.height ?? 700) - 60)))
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
  @ViewBuilder func workspace(_ layout: MonitorLayout, scrolling: Bool) -> some View {
    VStack(spacing: 0) {
      if !layout.denseOverview {
        sectionHeading.padding(.top, 23).padding(.bottom, 20)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(metric.rawValue + " activity")
              .font(.system(size: 18, weight: .semibold)).tracking(-0.4)
            Spacer(minLength: 4)
            HistoryRangePicker(range: $range, theme: theme)
          }
          if metric == .gpu { GPUDevicePicker(theme: theme) }
        }.padding(.vertical, 6)
      }
      MonitorOverview(
        metric: metric, range: range, theme: theme,
        width: layout.width - layout.gutter * 2, expanded: layout.expanded,
        condensed: layout.denseOverview
      )
      .padding(.bottom, layout.denseOverview ? 10 : 24)
      HStack(spacing: 16) {
        MonitorProcessTable(
          rows: filtered, metric: metric, theme: theme, query: $query, filter: $filter,
          selection: $selection, inspector: $inspector, sort: $sort, descending: $descending,
          inspect: { p in
            selection = p.id
            inspector = true
          }, stop: { stopTarget = $0 }, searchFocus: $searchFocused)
        if inspector && layout.inlineInspector {
          inspectorPanel.frame(width: layout.inspectorWidth)
        }
      }.frame(height: scrolling ? max(340, layout.height - 430) : nil)
        .frame(maxHeight: scrolling ? nil : .infinity)
    }.padding(.horizontal, layout.gutter)
  }
  var inspectorPanel: some View {
    MonitorInspector(
      process: selected, theme: theme, busy: sampling, close: { inspector = false },
      sample: sample, files: inspectFiles, reveal: reveal, stop: { stopTarget = $0 })
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
            Menu {
              Button("Export visible processes…") { monitor.export(filtered) }
              Button("Export JSON snapshot…") { monitor.exportJSON(filtered) }
              Button("Export GPU snapshot & history…") { monitor.exportGPU(filtered) }
              Divider()
              Picker("Appearance", selection: $appearance) {
                ForEach(["Light", "Dark", "System"], id: \.self) { Text($0).tag($0) }
              }
              Toggle("Show monitor in menu bar", isOn: $showMenuBar)
              Picker("Update interval", selection: $monitor.interval) {
                Text("Every second").tag(1.0)
                Text("Every 2 seconds").tag(2.0)
                Text("Every 5 seconds").tag(5.0)
              }
              Divider()
              Button("All views & themes") { showGallery = true }
              Button("Keyboard shortcuts & data notes") { showHelp = true }
            } label: {
              Image(systemName: "ellipsis").frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
          }.padding(.horizontal, layout.gutter)
        }.frame(height: 44)
        MetricSwitcher(
          metric: Binding(get: { metric }, set: selectMetric), theme: theme, compact: layout.compact
        )
        .padding(.horizontal, layout.gutter).padding(.bottom, 4)
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
              Text("\(Host.current().localizedName ?? "Mac") · \(architectureLabel)").font(
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
            monitor.export(filtered)
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
          Menu {
            Toggle("Show monitor in menu bar", isOn: $showMenuBar)
            Button("Export JSON snapshot…") { monitor.exportJSON(filtered) }
            Button("Export GPU snapshot & history…") { monitor.exportGPU(filtered) }
            Divider()
            Picker("Update interval", selection: $monitor.interval) {
              Text("Every second").tag(1.0)
              Text("Every 2 seconds").tag(2.0)
              Text("Every 5 seconds").tag(5.0)
            }
            Button("Keyboard shortcuts & data notes") { showHelp = true }
          } label: {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(theme.secondary)
              .frame(width: 32, height: 32)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
      }.padding(.horizontal, 23)

    }.frame(height: 78).background(theme.toolbar).overlay(alignment: .bottom) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
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
  func inspectFiles(_ p: ProcessRow) {
    guard processStillMatches(p) else {
      monitor.error = "The process has exited."
      return
    }
    sampling = true
    Task {
      sampleText = await runDiagnostic("/usr/sbin/lsof", ["-n", "-P", "-p", String(p.id)])
      sampling = false
    }
  }
  func sample(_ p: ProcessRow) {
    guard processStillMatches(p) else {
      monitor.error = "The process has exited."
      return
    }
    sampling = true
    Task {
      let result = await runDiagnostic("/usr/bin/sample", [String(p.id), "1", "10"])
      sampleText = result
      sampling = false
    }
  }
  func runDiagnostic(_ executable: String, _ arguments: [String]) async -> String {
    await Task.detached(priority: .utility) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      do {
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
          if process.isRunning { process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.isEmpty
          ? "No output. The process may have exited or macOS may have denied access." : output
      } catch { return error.localizedDescription }
    }.value
  }
  func saveSample() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Process-Sample.txt"
    if panel.runModal() == .OK, let url = panel.url {
      do { try (sampleText ?? "").write(to: url, atomically: true, encoding: .utf8) } catch {
        monitor.error = error.localizedDescription
      }
    }
  }
}
