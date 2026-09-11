import Foundation

/// Only additive counters belong here. Identity and boolean process state stay local.
enum ProcessUsageMetric: String, CaseIterable {
  case cpu, time, gpu, gpuTime, threads, memory, resident, read, written
  case received, sent, packetsIn, packetsOut, ports
  case privateMemory, sharedMemory, purgeable, compressed, wakeups

  static func resolve(_ key: String, metric: Metric) -> Self? {
    Self(rawValue: ProcessColumns.canonical(key, metric: metric))
  }

  var help: String {
    switch self {
    case .cpu:
      return "Sum of sampled CPU execution-time rates. 100% is one logical processor."
    case .time:
      return "Sum of current members' own lifetime CPU time; excludes exited-child accounting."
    case .gpu, .gpuTime:
      return
        "Sum of reported GPU execution across devices, using each process's observed counters. Concurrent work can exceed 100%."
    case .memory:
      return
        "Sum of reported process memory footprints, with resident fallback where footprint is unavailable. Shared mappings can overlap; this is not unique physical RAM."
    case .resident, .privateMemory, .sharedMemory, .purgeable, .compressed:
      return
        "Sum of this process memory counter. Shared mappings can overlap between processes; this is not unique physical RAM."
    case .read, .written:
      return
        "Sum of current members' cumulative disk bytes, not bytes per second. Totals can decrease when processes exit."
    case .received, .sent, .packetsIn, .packetsOut:
      return
        "Sum of current members' observed network counters, not a rate or machine-wide traffic."
    case .ports:
      return "Sum of per-process Mach port counts, not distinct global port objects."
    case .threads: return "Sum of current members' thread counts."
    case .wakeups: return "Sum of sampled idle wake-up rates."
    }
  }
}

struct ProcessUsageTotal: Equatable {
  private(set) var value: ProcessSortValue?
  private(set) var reportedProcesses: Int
  private(set) var overflowed = false

  init(_ value: ProcessSortValue?) {
    switch value {
    case .integer:
      self.value = value
    case .number(let number) where number.isFinite && number >= 0:
      self.value = value
    default:
      self.value = nil
    }
    reportedProcesses = self.value == nil ? 0 : 1
  }

  mutating func add(_ other: Self) {
    reportedProcesses += other.reportedProcesses
    overflowed = overflowed || other.overflowed
    switch (value, other.value) {
    case (nil, _): value = other.value
    case (_, nil): break
    case (.integer(let a), .integer(let b)):
      let result = a.addingReportingOverflow(b)
      value = .integer(result.overflow ? .max : result.partialValue)
      overflowed = overflowed || result.overflow
    case (.number(let a), .number(let b)):
      let sum = a + b
      value = .number(sum.isFinite ? sum : .greatestFiniteMagnitude)
      overflowed = overflowed || !sum.isFinite
    default:
      // A metric always has one numeric representation in ProcessValues.
      assertionFailure("Mismatched process metric types")
    }
  }

  func isPartial(processCount: Int) -> Bool {
    value != nil && (reportedProcesses < processCount || overflowed)
  }
}

/// Immutable after the forest's postorder pass; never replaces a process's own row.
struct ProcessSubtreeUsage: Equatable {
  private(set) var processCount = 1
  private(set) var residentFallbackCount: Int
  private var totals: [ProcessUsageTotal]

  init(_ row: ProcessRow) {
    residentFallbackCount = row.accessible && row.memoryUsesResidentFallback == true ? 1 : 0
    totals = ProcessUsageMetric.allCases.map {
      ProcessUsageTotal(ProcessValues.value(row, key: $0.rawValue, metric: .cpu))
    }
  }

  subscript(_ metric: ProcessUsageMetric) -> ProcessUsageTotal {
    totals[Self.indices[metric]!]
  }

  private static let indices = Dictionary(
    uniqueKeysWithValues: ProcessUsageMetric.allCases.enumerated().map { ($0.element, $0.offset) })

  mutating func add(_ other: Self) {
    processCount += other.processCount
    residentFallbackCount += other.residentFallbackCount
    for index in totals.indices { totals[index].add(other.totals[index]) }
  }

  static let scopeHelp =
    "Σ includes the process and all current descendants, even when hidden by search or collapse. ≥ marks a partial subtotal; — means no available counters. Parent and child totals overlap."

  var description: String {
    "Subtree: \(processCount) \(processCount == 1 ? "process" : "processes"), including this process. "
      + Self.scopeHelp
  }

  func coverage(_ metric: ProcessUsageMetric) -> String {
    let total = self[metric]
    var text = "\(total.reportedProcesses) of \(processCount) processes reported"
    if total.overflowed { text += "; arithmetic limit reached" }
    if metric == .memory && residentFallbackCount > 0 {
      text += "; \(residentFallbackCount) use resident memory fallback"
    }
    return text
  }
}
