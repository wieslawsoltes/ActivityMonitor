import SwiftUI

/// Existing column choices and order are the default for each perspective.
enum ProcessColumns {
  static func defaults(_ metric: Metric) -> [ProcessColumn] {
    let values: [ProcessColumn]
    switch metric {
    case .gpu:
      values = [
        .init(id: "primary", title: "% GPU", weight: 0.85),
        .init(id: "gpuTime", title: "GPU time", weight: 1.35),
        .init(id: "cpu", title: "% CPU", weight: 0.8),
        .init(id: "memory", title: "Memory", weight: 1.1),
        .init(id: "kind", title: "Kind", weight: 0.8),
        .init(id: "pid", title: "PID", weight: 0.8),
        .init(id: "user", title: "User", weight: 1.1),
      ]
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
    return values
  }
  static func canonical(_ key: String, metric: Metric) -> String {
    if key == "secondary" { return "read" }
    if key != "primary" { return key }
    switch metric {
    case .cpu, .energy: return "cpu"
    case .memory: return "memory"
    case .disk: return "written"
    case .gpu: return "gpu"
    case .network: return "received"
    }
  }
  static let catalog: [ProcessColumn] = [
    .init(id: "pid", title: "PID", weight: 0.8),
    .init(id: "user", title: "User", weight: 1.1),
    .init(id: "cpu", title: "% CPU", weight: 0.85),
    .init(id: "time", title: "CPU time", weight: 1.2),
    .init(id: "gpu", title: "% GPU", weight: 0.8),
    .init(id: "gpuTime", title: "GPU time", weight: 1.35),
    .init(id: "threads", title: "Threads", weight: 0.8),
    .init(id: "ports", title: "Ports", weight: 0.8),
    .init(id: "resident", title: "Real memory", weight: 1.1),
    .init(id: "privateMemory", title: "Real private memory", weight: 1.6),
    .init(id: "sharedMemory", title: "Real shared memory", weight: 1.6),
    .init(id: "kind", title: "Kind", weight: 0.8),
    .init(id: "suddenTermination", title: "Sudden termination", weight: 1.6),
    .init(id: "sandbox", title: "Sandbox", weight: 1.1),
    .init(id: "restricted", title: "Restricted", weight: 1.1),
    .init(id: "wakeups", title: "Idle wake-ups", weight: 1.2),
    .init(id: "energyImpact", title: "Energy impact", weight: 1.2),
    .init(id: "nap", title: "App nap", weight: 1.1),
    .init(id: "sent", title: "Sent bytes", weight: 1.1),
    .init(id: "packetsOut", title: "Sent packets", weight: 1.2),
    .init(id: "received", title: "Received bytes", weight: 1.1),
    .init(id: "packetsIn", title: "Received packets", weight: 1.2),
    .init(id: "purgeable", title: "Purgeable memory", weight: 1.5),
    .init(id: "memory", title: "Memory", weight: 1.1),
    .init(id: "compressed", title: "Compressed memory", weight: 1.6),
    .init(id: "written", title: "Bytes written", weight: 1.4),
    .init(id: "read", title: "Bytes read", weight: 1.4),
    .init(id: "sleep", title: "Preventing sleep", weight: 1.5),
  ]
  static func available(_ metric: Metric) -> [ProcessColumn] {
    let defaults = defaults(metric)
    let keys = Set(defaults.map { canonical($0.id, metric: metric) })
    return defaults + catalog.filter { !keys.contains($0.id) }
  }
  static func unavailableReason(_ key: String) -> String? {
    switch key {
    case "energyImpact": return "Apple’s Energy Impact score is not exposed to third-party apps."
    case "nap": return "macOS does not expose reliable App Nap state through public process APIs."
    case "suddenTermination":
      return
        "macOS does not expose the live sudden-termination counter through public process APIs."
    default: return nil
    }
  }
}

/// Overrides are isolated by perspective. Missing keys retain the previous defaults.
struct ProcessColumnPreferences {
  var overrides: [String: [String: Bool]]
  init(_ json: String = "{}") {
    overrides =
      (try? JSONDecoder().decode([String: [String: Bool]].self, from: Data(json.utf8))) ?? [:]
  }
  var json: String { (try? String(data: JSONEncoder().encode(overrides), encoding: .utf8)) ?? "{}" }
  func isVisible(
    _ key: String, metric: Metric, showTime: Bool = true, showThreads: Bool = true,
    showUser: Bool = true
  ) -> Bool {
    if let value = overrides[metric.rawValue]?[key] { return value }
    return ProcessColumns.defaults(metric).contains { $0.id == key }
      && (key != "threads" || showThreads) && (key != "user" || showUser)
      && (!["time", "gpuTime"].contains(key) || showTime)
  }
  mutating func set(_ key: String, metric: Metric, visible: Bool) {
    overrides[metric.rawValue, default: [:]][key] = visible
  }
  mutating func restore(_ metric: Metric) {
    let defaults = Set(ProcessColumns.defaults(metric).map(\.id))
    overrides[metric.rawValue] = Dictionary(
      uniqueKeysWithValues:
        ProcessColumns.available(metric).map { ($0.id, defaults.contains($0.id)) })
  }
  func explicitlyEnabled(_ metric: Metric) -> Set<String> {
    let defaults = Set(ProcessColumns.defaults(metric).map(\.id))
    return Set(
      (overrides[metric.rawValue] ?? [:]).filter { $0.value && !defaults.contains($0.key) }.map(
        \.key))
  }
}
