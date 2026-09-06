import AppKit
import SwiftUI

struct ContentView: View {
  @Environment(\.colorScheme) var colorScheme
  @EnvironmentObject var monitor: Monitor
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
    case .cpu: return "CPU activity"
    case .memory: return "Memory, in balance."
    case .energy: return "Every bit of energy."
    case .disk: return "Data in motion."
    case .network: return "Stay in the flow."
    }
  }
  var subheading: String {
    switch metric {
    case .cpu: return "A little clarity. A lot of processing power."
    case .memory: return "Understand how your Mac makes room for everything."
    case .energy: return "A closer look at the apps powering your day."
    case .disk: return "Follow every read, every write, and everything in between."
    case .network: return "See what’s coming in. Know what’s going out."
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      titlebar
      VStack(spacing: 0) {
        sectionHeading.padding(.top, 23).padding(.bottom, 20)
        MonitorOverview(metric: metric, range: range, theme: theme).environmentObject(monitor)
          .padding(.bottom, 24)
        HStack(spacing: 16) {
          MonitorProcessTable(
            rows: filtered, metric: metric, theme: theme, query: $query, filter: $filter,
            selection: $selection, inspector: $inspector, sort: $sort, descending: $descending,
            inspect: { p in
              selection = p.id
              inspector = true
            }, stop: { stopTarget = $0 }, searchFocus: $searchFocused)
          if inspector {
            MonitorInspector(
              process: selected, theme: theme, busy: sampling, close: { inspector = false },
              sample: sample, files: inspectFiles, reveal: reveal, stop: { stopTarget = $0 }
            ).frame(width: 298)
          }
        }.frame(maxHeight: .infinity)
      }.padding(.horizontal, 26)
      statusbar
    }.background(theme.window).foregroundStyle(theme.text).font(.system(size: 12)).frame(
      minWidth: 1120, minHeight: 700
    ).ignoresSafeArea(.container, edges: .top)
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
      .sheet(isPresented: $showGallery) {
        DesignGallery(
          select: { view, style in
            selectMetric(view)
            appearance = style
            showGallery = false
          }, close: { showGallery = false }
        ).environmentObject(monitor)
      }
      .sheet(isPresented: $showHelp) {
        VStack(alignment: .leading, spacing: 18) {
          Text("A clearer view of your Mac").font(.title2.bold())
          Text(
            "⌘1–5  Switch views\n⌘K  Search processes\nSpace  Pause or resume\n⌘⇧E  Export process CSV\nDouble-click a process to inspect it"
          ).lineSpacing(8)
          Text(
            "CPU percentages are measured between samples. A process can exceed 100% when using multiple cores. Disk rates include readable processes; network counters aggregate non-loopback interfaces and can include VPN traffic. Restricted process counters may be unavailable."
          ).foregroundStyle(.secondary)
          Button("Done") { showHelp = false }.keyboardShortcut(.defaultAction)
        }.padding(32).frame(width: 510)
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
      }.padding(24).frame(width: 850, height: 600)
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
  var titlebar: some View {
    ZStack {
      WindowChrome()
      HStack(spacing: 0) {
        HStack(spacing: 22) {
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
        Spacer(minLength: 0)
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
            Toggle("Show CPU in menu bar", isOn: $showMenuBar)
            Button("Export JSON snapshot…") { monitor.exportJSON(filtered) }
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
      HStack(spacing: 3) {
        ForEach(Metric.allCases) { item in
          Button {
            selectMetric(item)
          } label: {
            HStack(spacing: 7) {
              Image(systemName: item.icon).font(.system(size: 13)).foregroundStyle(
                item == metric ? theme.blue : theme.secondary)
              Text(item.rawValue).font(.system(size: 13, weight: .medium))
            }.padding(.horizontal, 15).frame(height: 34)
          }.buttonStyle(MonitorSegmentButton(theme: theme, active: item == metric))
            .accessibilityAddTraits(item == metric ? .isSelected : []).help(
              "\(item.rawValue) · ⌘\(Metric.allCases.firstIndex(of:item)!+1)")
        }
      }.padding(4).background(theme.recessed, in: RoundedRectangle(cornerRadius: 11)).overlay(
        RoundedRectangle(cornerRadius: 11).stroke(theme.separator, lineWidth: 1))
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
