import AppKit
import SwiftUI

struct ProcessColumn: Identifiable {
  let id: String
  let title: String
  let weight: CGFloat
}
struct MonitorProcessTable: View {
  let rows: [ProcessRow]
  let metric: Metric
  let theme: MonitorTheme
  @Binding var query: String
  @Binding var filter: String
  @Binding var selection: Int32?
  @Binding var inspector: Bool
  @Binding var sort: String
  @Binding var descending: Bool
  let inspect: (ProcessRow) -> Void
  let stop: (ProcessRow) -> Void
  let searchFocus: FocusState<Bool>.Binding
  @AppStorage("showThreads") var showThreads = true
  @AppStorage("showUser") var showUser = true
  @AppStorage("showTime") var showTime = true
  @State var hovered: Int32?
  @FocusState var focused: Bool
  var columns: [ProcessColumn] {
    var values: [ProcessColumn]
    switch metric {
    case .cpu:
      values = [
        .init(id: "primary", title: "% CPU", weight: 0.85),
        .init(id: "time", title: "CPU time", weight: 1.2),
        .init(id: "threads", title: "Threads", weight: 0.8),
        .init(id: "memory", title: "Memory", weight: 1.1),
        .init(id: "kind", title: "Kind", weight: 0.8),
        .init(id: "gpu", title: "% GPU", weight: 0.8), .init(id: "pid", title: "PID", weight: 0.8),
        .init(id: "user", title: "User", weight: 1.1),
      ]
    case .memory:
      values = [
        .init(id: "primary", title: "Memory", weight: 1.1),
        .init(id: "threads", title: "Threads", weight: 0.7),
        .init(id: "ports", title: "Ports", weight: 0.7),
        .init(id: "cpu", title: "% CPU", weight: 0.7),
        .init(id: "kind", title: "Kind", weight: 0.7),
        .init(id: "gpu", title: "% GPU", weight: 0.7),
        .init(id: "resident", title: "Real memory", weight: 1.1),
        .init(id: "pid", title: "PID", weight: 0.7), .init(id: "user", title: "User", weight: 1),
      ]
    case .energy:
      values = [
        .init(id: "primary", title: "CPU workload", weight: 1.1),
        .init(id: "time", title: "CPU time", weight: 1.1),
        .init(id: "nap", title: "App nap", weight: 1.1),
        .init(id: "sleep", title: "Preventing sleep", weight: 1.1),
        .init(id: "user", title: "User", weight: 1.2),
      ]
    case .disk:
      values = [
        .init(id: "primary", title: "Bytes written", weight: 1.4),
        .init(id: "secondary", title: "Bytes read", weight: 1.4),
        .init(id: "pid", title: "PID", weight: 0.8), .init(id: "user", title: "User", weight: 1.8),
      ]
    case .network:
      values = [
        .init(id: "received", title: "Received bytes", weight: 1.1),
        .init(id: "sent", title: "Sent bytes", weight: 1.1),
        .init(id: "packetsOut", title: "Sent packets", weight: 1),
        .init(id: "packetsIn", title: "Received packets", weight: 1.2),
        .init(id: "pid", title: "PID", weight: 0.7), .init(id: "user", title: "User", weight: 1.2),
      ]
    }
    return values.filter {
      ($0.id != "threads" || showThreads) && ($0.id != "user" || showUser)
        && ($0.id != "time" || showTime)
    }
  }
  var minTableWidth: CGFloat { metric == .disk ? 720 : metric == .energy ? 850 : 1000 }
  var body: some View {
    GeometryReader { g in
      VStack(spacing: 0) {
        toolbar.frame(height: 61)
        Rectangle().fill(theme.separator).frame(height: 1)
        let width = max(minTableWidth, g.size.width)
        ScrollView(.horizontal) {
          VStack(spacing: 0) {
            header(width).frame(height: 36).background(theme.subtle)
            Rectangle().fill(theme.separator).frame(height: 1)
            ScrollViewReader { proxy in
              ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                  ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, index, width).id(row.id)
                  }
                  if rows.isEmpty { ContentUnavailableView.search(text: query).frame(height: 240) }
                }
              }.onChange(of: selection) { if let selection { proxy.scrollTo(selection) } }
                .focusable().focusEffectDisabled().focused($focused)
                .onKeyPress(.upArrow) {
                  move(-1)
                  return .handled
                }.onKeyPress(.downArrow) {
                  move(1)
                  return .handled
                }
                .onKeyPress(.return) {
                  if let p = rows.first(where: { $0.id == selection }) { inspect(p) }
                  return .handled
                }
                .onKeyPress(.escape) {
                  inspector = false
                  return .handled
                }
            }
          }.frame(width: width, height: max(100, g.size.height - 62))
        }.scrollIndicators(.automatic)
      }.background(theme.card).clipShape(
        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
      ).overlay(
        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).stroke(
          theme.border, lineWidth: 1))
    }
  }
  var toolbar: some View {
    HStack(spacing: 9) {
      Text(metric == .energy ? "Applications" : "Processes").font(
        .system(size: 13, weight: .semibold)
      ).foregroundStyle(theme.text)
      Text(rows.count.formatted()).font(.system(size: 10)).foregroundStyle(theme.secondary).padding(
        .horizontal, 6
      ).padding(.vertical, 2).background(theme.subtle, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
      Spacer(minLength: 6)
      Menu {
        ForEach(["All processes", "My processes", "System processes", "Applications"], id: \.self) {
          item in
          Button {
            filter = item
          } label: {
            if filter == item { Label(item, systemImage: "checkmark") } else { Text(item) }
          }
        }
      } label: {
        HStack(spacing: 14) {
          Text(filter)
          Image(systemName: "chevron.down").font(.system(size: 8))
        }.font(.system(size: 11)).foregroundStyle(theme.secondary).frame(
          width: 128, alignment: .trailing)
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.tertiary)
        TextField("Search processes", text: $query).textFieldStyle(.plain).font(.system(size: 11))
          .foregroundStyle(theme.text).focused(searchFocus)
        if query.isEmpty {
          Text("⌘ K").font(.system(size: 9)).foregroundStyle(theme.tertiary).padding(.horizontal, 4)
            .padding(.vertical, 1).overlay(
              RoundedRectangle(cornerRadius: 3).stroke(theme.border, lineWidth: 1))
        } else {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(
              theme.tertiary)
          }.buttonStyle(.plain)
        }
      }.padding(.horizontal, 10).frame(width: 230, height: 31).background(
        theme.subtle, in: RoundedRectangle(cornerRadius: 7)
      ).overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border, lineWidth: 1)).padding(
        .leading, 8)
      Rectangle().fill(theme.border).frame(width: 1, height: 18).padding(.horizontal, 3)
      Button {
        if let row = rows.first(where: { $0.id == selection }) { stop(row) }
      } label: {
        Image(systemName: "xmark.octagon")
      }.buttonStyle(MonitorIconButton(theme: theme)).disabled(!canStop).help(
        "Quit selected process")
      Button {
        inspector.toggle()
      } label: {
        Image(systemName: "info.circle")
      }.buttonStyle(MonitorIconButton(theme: theme, active: inspector)).help("Process details")
      Menu {
        Toggle("CPU time", isOn: $showTime)
        Toggle("Threads", isOn: $showThreads)
        Toggle("User", isOn: $showUser)
        Divider()
        Button("Restore columns") {
          showTime = true
          showThreads = true
          showUser = true
        }
        Divider()
        Text("— means the metric is unavailable.")
      } label: {
        Image(systemName: "rectangle.split.3x1").font(.system(size: 13)).foregroundStyle(
          theme.secondary
        ).frame(width: 30, height: 32)
      }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose columns")
    }.padding(.horizontal, 18)
  }
  var canStop: Bool {
    guard let row = rows.first(where: { $0.id == selection }) else { return false }
    return row.uid == getuid() && row.id > 1 && row.id != getpid()
  }
  func nameWidth(_ width: CGFloat) -> CGFloat {
    metric == .disk ? width * 0.39 : metric == .energy ? width * 0.30 : width * 0.27
  }
  func cellWidth(_ column: ProcessColumn, _ width: CGFloat) -> CGFloat {
    (width - nameWidth(width)) * column.weight / columns.reduce(0) { $0 + $1.weight }
  }
  func header(_ width: CGFloat) -> some View {
    HStack(spacing: 0) {
      headerButton(metric == .energy ? "App name" : "Process name", "name", alignment: .leading)
        .frame(width: nameWidth(width))
      ForEach(columns) { c in
        headerButton(c.title, c.id, alignment: c.id == "user" ? .leading : .trailing).frame(
          width: cellWidth(c, width))
      }
    }
  }
  func headerButton(_ title: String, _ key: String, alignment: Alignment) -> some View {
    Button {
      if sort == key {
        descending.toggle()
      } else {
        sort = key
        descending = key != "name" && key != "user"
      }
    } label: {
      HStack(spacing: 5) {
        Text(title)
        if sort == key {
          Image(systemName: descending ? "chevron.down" : "chevron.up").font(.system(size: 7))
        }
      }.font(.system(size: 10, weight: sort == key ? .semibold : .regular)).foregroundStyle(
        sort == key ? theme.text : theme.secondary
      ).frame(maxWidth: .infinity, alignment: alignment).padding(.horizontal, 16)
    }.buttonStyle(.plain).help(
      unavailableColumn(key)
        ? "This metric is not exposed by public macOS APIs." : "Sort by \(title)"
    ).disabled(unavailableColumn(key))
  }
  func rowView(_ row: ProcessRow, _ index: Int, _ width: CGFloat) -> some View {
    Button {
      selection = row.id
      focused = true
    } label: {
      HStack(spacing: 0) {
        HStack(spacing: 10) {
          ProcessIcon(pid: row.id, isApp: row.isApp).frame(width: 24, height: 24)
          Text(row.name).font(.system(size: 12)).foregroundStyle(theme.text).lineLimit(1)
            .truncationMode(.middle)
        }.padding(.horizontal, 17).frame(width: nameWidth(width), alignment: .leading)
        ForEach(columns) { c in cell(row, c).frame(width: cellWidth(c, width)) }
      }.frame(height: 41).background(
        selection == row.id
          ? theme.selected
          : hovered == row.id ? theme.hover : index % 2 == 1 ? theme.stripe : Color.clear
      ).overlay(alignment: .leading) {
        if selection == row.id { Rectangle().fill(theme.blue).frame(width: 2) }
      }.overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
        .contentShape(Rectangle())
    }.buttonStyle(.plain).focusEffectDisabled().onHover { hovered = $0 ? row.id : nil }
      .simultaneousGesture(TapGesture(count: 2).onEnded { inspect(row) }).contextMenu {
        Button("Inspect") { inspect(row) }
        Button("Copy PID") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(String(row.id), forType: .string)
        }
        Button("Quit…", role: .destructive) { stop(row) }.disabled(
          row.uid != getuid() || row.id <= 1 || row.id == getpid())
      }.accessibilityLabel("\(row.name), PID \(row.id)").accessibilityValue(
        columns.map { $0.title + ": " + text(row, $0.id) }.joined(separator: ", ")
      ).accessibilityAction(named: "Inspect") {
        inspect(row)
      }
  }
  func cell(_ p: ProcessRow, _ c: ProcessColumn) -> some View {
    let primary = c.id == "primary"
    let highlighted = primary && (metric == .cpu || metric == .memory)
    return Text(text(p, c.id)).font(
      .system(size: c.id == "user" ? 11 : 12, weight: primary ? .medium : .regular)
    ).monospacedDigit().foregroundStyle(
      highlighted ? theme.blue : primary ? theme.text : theme.secondary
    ).lineLimit(1).padding(.horizontal, highlighted ? 7 : 0).padding(.vertical, highlighted ? 4 : 0)
      .background(
        highlighted ? theme.blue.opacity(0.095) : Color.clear, in: RoundedRectangle(cornerRadius: 3)
      ).frame(maxWidth: .infinity, alignment: c.id == "user" ? .leading : .trailing).padding(
        .horizontal, 16)
  }
  func text(_ p: ProcessRow, _ key: String) -> String {
    switch key {
    case "primary":
      if metric == .disk { return p.ioAccessible ? bytes(p.written) : "—" }
      return !p.accessible
        ? "—" : metric == .memory ? bytes(p.memory) : String(format: "%.1f", p.cpu)
    case "secondary": return p.ioAccessible ? bytes(p.read) : "—"
    case "cpu": return p.accessible ? String(format: "%.1f", p.cpu) : "—"
    case "time": return p.accessible ? duration(p.cpuTime) : "—"
    case "memory": return p.accessible ? bytes(p.memory) : "—"
    case "resident": return p.accessible ? bytes(p.resident) : "—"
    case "threads": return p.accessible ? String(p.threads) : "—"
    case "received": return p.networkReceived.map(bytes) ?? "—"
    case "sent": return p.networkSent.map(bytes) ?? "—"
    case "kind": return p.kind
    case "pid": return String(p.id)
    case "user": return p.user
    default: return "—"
    }
  }
  func unavailableColumn(_ key: String) -> Bool {
    ["gpu", "ports", "nap", "sleep", "packetsIn", "packetsOut"].contains(key)
  }
  func move(_ delta: Int) {
    guard !rows.isEmpty else { return }
    let index = rows.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : rows.count)
    selection = rows[min(max(index + delta, 0), rows.count - 1)].id
  }
}
