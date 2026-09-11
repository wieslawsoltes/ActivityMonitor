import SwiftUI

/// Shared surfaces keep process workspaces in the same visual family as the main monitor.
struct DiagnosticPanel<Content: View>: View {
  let theme: MonitorTheme
  var padding: CGFloat = 18
  @ViewBuilder var content: Content
  var body: some View {
    content.frame(maxWidth: .infinity, alignment: .leading).padding(padding)
      .background(theme.card, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1))
  }
}
struct DiagnosticSidebar: View {
  @Binding var selection: DiagnosticTab
  let theme: MonitorTheme
  @FocusState private var focused: DiagnosticTab?
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 5) {
          group("Activity", tabs: Array(DiagnosticTab.allCases.prefix(7)))
          group("Diagnostics", tabs: Array(DiagnosticTab.allCases.dropFirst(7)))
        }.padding(12)
      }
      .onChange(of: focused) { _, tab in
        if let tab { proxy.scrollTo(tab) }
      }
    }.frame(width: 174).background(theme.window)
  }
  private func group(_ title: String, tabs: [DiagnosticTab]) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.1)
        .foregroundStyle(theme.tertiary).padding(.leading, 10).padding(.top, 12).padding(.bottom, 6)
      ForEach(tabs) { tab in
        Button {
          selection = tab
          focused = tab
        } label: {
          HStack(spacing: 10) {
            Image(systemName: tab.icon).font(.system(size: 13))
              .foregroundStyle(selection == tab ? theme.blue : theme.secondary).frame(width: 18)
            Text(tab.rawValue).font(
              .system(size: 12, weight: selection == tab ? .semibold : .regular))
            Spacer(minLength: 0)
          }.padding(.horizontal, 10).frame(height: 33)
        }.buttonStyle(MonitorSegmentButton(theme: theme, active: selection == tab))
          .accessibilityAddTraits(selection == tab ? .isSelected : [])
          .focusable()
          .focused($focused, equals: tab).id(tab)
          .onKeyPress(.downArrow) { move(from: tab, offset: 1) }
          .onKeyPress(.upArrow) { move(from: tab, offset: -1) }
      }
    }
  }
  private func move(from tab: DiagnosticTab, offset: Int) -> KeyPress.Result {
    let tabs = DiagnosticTab.allCases
    guard let index = tabs.firstIndex(of: tab), tabs.indices.contains(index + offset) else {
      return .handled
    }
    selection = tabs[index + offset]
    focused = selection
    return .handled
  }
}
struct DiagnosticRangePicker: View {
  @Binding var selection: Int
  let theme: MonitorTheme
  var body: some View {
    HStack(spacing: 3) {
      ForEach([1, 5, 15], id: \.self) { range in
        Button {
          selection = range
        } label: {
          Text("\(range) min").font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 11).frame(height: 28)
        }.buttonStyle(MonitorSegmentButton(theme: theme, active: selection == range, radius: 6))
          .accessibilityAddTraits(selection == range ? .isSelected : [])
      }
    }.padding(4).background(theme.recessed, in: RoundedRectangle(cornerRadius: 9))
      .accessibilityElement(children: .contain).accessibilityLabel("History range")
  }
}
extension DiagnosticTab {
  var subtitle: String {
    switch self {
    case .overview: return "Identity, resources and related processes."
    case .cpu: return "Execution time, threads and scheduling."
    case .memory: return "Physical footprint and memory allocation."
    case .energy: return "CPU workload, wake-ups and power assertions."
    case .disk: return "Read and write activity for this process."
    case .network: return "Traffic, connections and listening ports."
    case .gpu: return "Graphics activity and device memory across reporting devices."
    case .threads: return "Thread activity, CPU time and scheduling."
    case .files: return "Open descriptors and their underlying resources."
    case .connections: return "Network endpoints, socket state and queues."
    case .ports: return "Mach IPC names and rights, separate from network ports."
    case .fileports: return "File descriptors exported as Mach send rights."
    case .maps: return "Virtual address ranges, protection and resident pages."
    case .images: return "Executable files mapped into the process."
    case .reports: return "Collect and export a detailed process report."
    }
  }
}

struct DiagnosticFieldGroup {
  let title: String
  let icon: String
  var fields: [DiagnosticField]
  static func organize(_ fields: [DiagnosticField]) -> [Self] {
    let categories: [(String, String, Set<String>)] = [
      (
        "Identity & paths", "app.badge",
        [
          "Process name", "Executable name", "Executable", "Working directory", "Root directory",
          "Started", "Parent PID", "Process group",
        ]
      ),
      (
        "Access & security", "lock.shield",
        [
          "Effective UID / GID", "Real UID / GID", "Saved UID / GID", "Sandbox", "Sandboxed",
          "Restricted", "Ports", "Process flags",
        ]
      ),
      (
        "CPU & scheduling", "cpu",
        [
          "State", "Nice", "User CPU time", "System CPU time", "Priority", "Running threads",
          "Scheduling policy", "Instructions", "CPU cycles", "Context switches",
        ]
      ),
      (
        "Memory", "memorychip",
        [
          "Virtual memory", "Resident memory", "Wired memory", "Peak physical footprint",
          "Interval peak footprint", "Page faults", "Page-ins", "Copy-on-write faults",
          "Child page-ins", "Real private memory", "Real shared memory", "Compressed memory",
          "Purgeable memory",
        ]
      ),
      (
        "Files & system calls", "arrow.left.arrow.right",
        [
          "Open descriptors", "Logical writes", "Mach messages sent", "Mach messages received",
          "Mach syscalls", "Unix syscalls",
        ]
      ),
    ]
    var remaining = fields
    var result: [Self] = []
    for (title, icon, names) in categories {
      let group = remaining.filter { names.contains($0.name) }
      remaining.removeAll { names.contains($0.name) }
      if !group.isEmpty { result.append(.init(title: title, icon: icon, fields: group)) }
    }
    if !remaining.isEmpty {
      result.append(
        .init(title: "Resource accounting", icon: "waveform.path.ecg", fields: remaining))
    }
    return result
  }
}

extension ProcessReportKind {
  var summary: String {
    switch self {
    case .sample: return "Thread stacks and a brief execution sample."
    case .files: return "Open files, descriptors and network endpoints."
    case .memory: return "Virtual memory regions and allocation details."
    case .arguments: return "The arguments used to launch this process."
    case .environment: return "Environment variables; may contain sensitive values."
    case .signature: return "Signing identity, requirements and executable integrity."
    case .entitlements: return "Capabilities declared by the executable."
    }
  }
}
