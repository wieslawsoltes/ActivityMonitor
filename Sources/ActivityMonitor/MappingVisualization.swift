import Charts
import SwiftUI

/// Values describe readable mappings in this snapshot, not the process's physical footprint.
struct MappingPlotItem: Identifiable {
  let id: String
  let label: String
  let detail: String
  let value: Double
  var start: UInt64? = nil
  var end: UInt64? = nil
}
enum MappingMeasure: String, CaseIterable {
  case resident = "Resident"
  case virtual = "Virtual size"
  var key: String { self == .resident ? "Resident" : "Size" }
}
enum MappingPlotKind: String, CaseIterable {
  case protection = "By protection"
  case addresses = "Address ranges"
}
struct MappingPlotData {
  var items: [MappingPlotItem] = []
  var total = 0.0
  var omitted = 0
  var count = 0
  var base: UInt64 = 0
  var span = 1.0
  static func number(_ record: DiagnosticRecord, _ key: String) -> Double? {
    guard let value = record.numbers[key], value.isFinite, value >= 0, value <= Double(UInt64.max)
    else { return nil }
    return value
  }
  static func byteLabel(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "—" }
    if value == 0 { return "0 B" }
    return bytes(value >= Double(UInt64.max) ? UInt64.max : UInt64(value))
  }
  static func make(
    records: [DiagnosticRecord], images: Bool, measure: MappingMeasure,
    kind: MappingPlotKind, limit: Int = 8
  ) -> Self {
    var result = Self(count: records.count)
    if kind == .addresses && !images {
      let ranges = records.compactMap { record -> MappingPlotItem? in
        guard let text = record.cells["Address"], text.hasPrefix("0x"),
          let start = UInt64(text.dropFirst(2), radix: 16),
          let size = number(record, "Size"), size > 0, size < Double(UInt64.max)
        else {
          result.omitted += 1
          return nil
        }
        let (end, overflow) = start.addingReportingOverflow(UInt64(size))
        guard !overflow, end > start else {
          result.omitted += 1
          return nil
        }
        return .init(
          id: record.id, label: text,
          detail:
            "\(text)–\(String(format: "0x%016llX", end)) · \(record.path ?? "Anonymous mapping") · \(record.cells["Protection"] ?? "Unknown protection")",
          value: size, start: start, end: end)
      }.sorted { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }
      result.items = Array(ranges.prefix(max(1, limit))).sorted { $0.start! < $1.start! }
      result.base = result.items.compactMap(\.start).min() ?? 0
      // Subtract integers before converting to floating point to retain nearby address precision.
      result.span = max(
        1, Double((result.items.compactMap(\.end).max() ?? result.base) - result.base))
      result.total = ranges.reduce(0) { $0 + $1.value }
      return result
    }
    var groups: [String: (value: Double, count: Int)] = [:]
    for record in records {
      guard let value = number(record, measure.key) else {
        result.omitted += 1
        continue
      }
      let key =
        images
        ? record.path ?? record.cells["Path"]?.nonempty ?? "Unknown image"
        : record.cells["Protection"]?.nonempty ?? "Unknown"
      groups[key, default: (0, 0)].value += value
      groups[key, default: (0, 0)].count += 1
      result.total += value
    }
    let sorted = groups.sorted {
      $0.value.value == $1.value.value ? $0.key < $1.key : $0.value.value > $1.value.value
    }
    result.items = sorted.prefix(max(1, limit)).map { key, item in
      .init(
        id: key, label: images ? (key as NSString).lastPathComponent : key,
        detail: "\(key) · \(item.count) mapping\(item.count == 1 ? "" : "s")", value: item.value)
    }
    let remainder = sorted.dropFirst(max(1, limit))
    if !remainder.isEmpty {
      result.items.append(
        .init(
          id: "\u{0}other", label: "Other (\(remainder.count))",
          detail: "All remaining \(images ? "images" : "protection groups")",
          value: remainder.reduce(0) { $0 + $1.value.value }))
    }
    result.span = max(1, result.items.map(\.value).max() ?? 0)
    return result
  }
}

struct MappingVisualization: View {
  let section: DiagnosticSection
  let query: String
  let images: Bool
  let theme: MonitorTheme
  @State private var measure: MappingMeasure = .resident
  @State var kind: MappingPlotKind = .protection
  @State private var selected: String?
  @FocusState private var focused: Bool
  private var records: [DiagnosticRecord] {
    section.records.filter {
      query.isEmpty || $0.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
    }
  }
  var body: some View {
    let data = MappingPlotData.make(records: records, images: images, measure: measure, kind: kind)
    let addressMode = kind == .addresses && !images
    let inspected = data.items.first { $0.id == selected }
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            images
              ? "Mapped image sizes"
              : addressMode ? "Virtual address ranges" : "Memory by protection"
          ).font(
            .system(size: 12, weight: .semibold))
          Text(
            "\(section.status.localizedCaseInsensitiveContains("partial") ? "Partial · " : "")\(MappingPlotData.byteLabel(data.total)) · \(data.count) filtered mappings\(data.omitted > 0 ? " · \(data.omitted) unavailable" : "")"
          )
          .font(.system(size: 10)).foregroundStyle(theme.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
        if !images {
          Picker("Visualization", selection: $kind) {
            ForEach(MappingPlotKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.labelsHidden().frame(width: 132)
        }
        if !addressMode {
          Picker("Measurement", selection: $measure) {
            ForEach(MappingMeasure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.labelsHidden().frame(width: 110)
        }
      }.controlSize(.small)
      if data.items.isEmpty {
        VStack(spacing: 5) {
          Text(
            records.isEmpty
              ? (query.isEmpty ? "No readable mappings" : "No matching mappings")
              : "No readable mapping sizes")
          Text(section.status).lineLimit(2)
        }.font(.system(size: 11)).foregroundStyle(theme.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        plot(data, addresses: addressMode)
          .focusable().focused($focused)
          .onKeyPress(.downArrow) {
            moveSelection(data, by: 1)
            return .handled
          }
          .onKeyPress(.upArrow) {
            moveSelection(data, by: -1)
            return .handled
          }
      }
      Text(
        inspected.map { "\($0.detail) · \(MappingPlotData.byteLabel($0.value))" }
          ?? (addressMode
            ? "Largest 8 virtual ranges · offsets from \(String(format: "0x%016llX", data.base)) · gaps included"
            : images
              ? "Largest 8 images + Other · hover or select a bar for its path"
              : "Grouped by protection · r read / w write / x execute / − no access")
      )
      .font(.system(size: 9)).foregroundStyle(theme.secondary).lineLimit(1)
      .help(
        inspected?.detail
          ?? "Mapped resident bytes may include shared pages and differ from process footprint. Snapshot totals may be partial."
      )
      .accessibilityLabel(inspected?.detail ?? "Chart scope")
      Text(
        addressMode
          ? "Range lengths show virtual size, not resident memory."
          : "\(measure.rawValue) bytes in this snapshot\(images ? "; not full image or on-disk file sizes" : "; shared pages may be counted more than once")."
      )
      .font(.system(size: 9)).foregroundStyle(theme.tertiary).lineLimit(1)
    }.padding(14).background(theme.window).foregroundStyle(theme.text)
      .preferredColorScheme(theme.dark ? .dark : .light)
      .onChange(of: kind) { selected = nil }.onChange(of: measure) { selected = nil }
      .onChange(of: query) { selected = nil }
      .onChange(of: data.items.map(\.id)) { _, ids in
        if let selected, !ids.contains(selected) { self.selected = nil }
      }
  }
  private func moveSelection(_ data: MappingPlotData, by offset: Int) {
    guard !data.items.isEmpty else { return }
    let index =
      selected.flatMap { id in data.items.firstIndex { $0.id == id } }
      ?? (offset > 0 ? -1 : data.items.count)
    selected = data.items[min(data.items.count - 1, max(0, index + offset))].id
  }
  private func plot(_ data: MappingPlotData, addresses: Bool) -> some View {
    Chart(data.items) { item in
      BarMark(
        xStart: .value(
          addresses ? "Address offset" : "Bytes", addresses ? Double(item.start! - data.base) : 0),
        xEnd: .value(
          addresses ? "Address offset" : "Bytes",
          addresses ? Double(item.end! - data.base) : item.value),
        y: .value("Mapping", item.id), height: .fixed(8)
      )
      .foregroundStyle(
        item.id == "\u{0}other" ? theme.tertiary : theme.blue
      ).opacity(selected == nil || selected == item.id ? 1 : 0.35)
      .cornerRadius(2)
      .accessibilityLabel(item.detail)
      .accessibilityValue(MappingPlotData.byteLabel(item.value))
    }
    .chartXScale(domain: 0...data.span)
    .chartYScale(domain: data.items.map(\.id))
    .chartYAxis {
      AxisMarks(preset: .aligned, position: .leading, values: data.items.map(\.id)) { axis in
        AxisValueLabel(anchor: .trailing, collisionResolution: .disabled) {
          if let id = axis.as(String.self), let item = data.items.first(where: { $0.id == id }) {
            Text(item.label).font(.system(size: 9)).foregroundStyle(theme.secondary)
              .lineLimit(1).truncationMode(.middle).frame(
                width: images || addresses ? 135 : 54, alignment: .trailing
              ).fixedSize()
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks(position: .bottom, values: .automatic(desiredCount: addresses ? 3 : 4)) { value in
        AxisGridLine().foregroundStyle(theme.border)
        AxisValueLabel {
          if let value = value.as(Double.self) {
            Text((addresses ? "+" : "") + MappingPlotData.byteLabel(value))
              .font(.system(size: 8)).foregroundStyle(theme.tertiary)
          }
        }
      }
    }
    .chartYSelection(value: $selected)
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
          guard let frame = proxy.plotFrame.map({ geometry[$0] }) else { return }
          switch phase {
          case .active(let point):
            if frame.contains(point) {
              selected = proxy.value(atY: point.y - frame.minY, as: String.self)
            }
          case .ended: if !focused { selected = nil }
          }
        }.gesture(
          SpatialTapGesture().onEnded { event in
            guard let frame = proxy.plotFrame.map({ geometry[$0] }), frame.contains(event.location)
            else { return }
            selected = proxy.value(atY: event.location.y - frame.minY, as: String.self)
          }
        ).accessibilityHidden(true)
      }
    }
    .accessibilityLabel(
      images
        ? "Mapped image size ranking"
        : addresses ? "Virtual address ranges" : "Memory by protection")
  }
}
