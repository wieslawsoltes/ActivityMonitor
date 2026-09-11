import Foundation

/// Preserve integer counters as JSON integers, including values above Double's exact range.
enum ProcessUsageExportNumber: Codable {
  case integer(UInt64)
  case number(Double)

  init?(_ value: ProcessSortValue?) {
    switch value {
    case .integer(let value): self = .integer(value)
    case .number(let value): self = .number(value)
    default: return nil
    }
  }

  var csvValue: String {
    switch self {
    case .integer(let value): return String(value)
    case .number(let value): return String(value)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let integer = try? container.decode(UInt64.self) {
      self = .integer(integer)
    } else {
      self = .number(try container.decode(Double.self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    }
  }
}

struct ProcessUsageExportCounter: Codable {
  var value: ProcessUsageExportNumber?
  var reportedProcesses: Int
  var status: String
  var unit: String

  init(_ total: ProcessUsageTotal, processCount: Int, metric: ProcessUsageMetric) {
    value = ProcessUsageExportNumber(total.value)
    reportedProcesses = total.reportedProcesses
    status =
      total.value == nil
      ? "unavailable"
      : total.overflowed
        ? "overflow"
        : total.isPartial(processCount: processCount) ? "partial" : "complete"
    unit = metric.unit
  }
}

struct ProcessUsageExport: Codable {
  var processCount: Int
  var residentFallbackCount: Int
  var counters: [String: ProcessUsageExportCounter]

  init(_ usage: ProcessSubtreeUsage) {
    processCount = usage.processCount
    residentFallbackCount = usage.residentFallbackCount
    counters = Dictionary(
      uniqueKeysWithValues: ProcessUsageMetric.allCases.map { metric in
        (
          metric.rawValue,
          ProcessUsageExportCounter(usage[metric], processCount: usage.processCount, metric: metric)
        )
      })
  }
}

struct ProcessTreeExportRecord: Codable {
  var process: ProcessRow
  var subtree: ProcessUsageExport?
}

struct ProcessTreeExportSnapshot: Codable {
  var schemaVersion = 1
  var scope = "process-and-current-descendants"
  var accounting =
    ProcessSubtreeUsage.scopeHelp
    + " Memory is a sum of reported process counters, not unique physical RAM. Identity and state fields describe the named process."
  var rows: [ProcessTreeExportRecord]
}

func processJSON(_ rows: [ProcessRow], usage: [Int32: ProcessSubtreeUsage]? = nil) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  if let usage {
    return try encoder.encode(
      ProcessTreeExportSnapshot(
        rows: rows.map { row in
          ProcessTreeExportRecord(process: row, subtree: usage[row.id].map(ProcessUsageExport.init))
        }))
  }
  return try encoder.encode(rows)
}

extension ProcessUsageMetric {
  var unit: String {
    switch self {
    case .cpu: return "percent-of-one-logical-processor"
    case .gpu: return "percent-of-reported-GPU-execution-time"
    case .time, .gpuTime: return "seconds"
    case .wakeups: return "wakeups-per-second"
    case .threads, .ports, .packetsIn, .packetsOut: return "count"
    default: return "bytes"
    }
  }

  var exportTitle: String {
    switch self {
    case .cpu: return "CPU %"
    case .time: return "CPU seconds"
    case .gpu: return "GPU %"
    case .gpuTime: return "Observed GPU seconds"
    case .threads: return "Threads"
    case .memory: return "Memory bytes"
    case .resident: return "Resident bytes"
    case .read: return "Bytes read"
    case .written: return "Bytes written"
    case .received: return "Network bytes received"
    case .sent: return "Network bytes sent"
    case .packetsIn: return "Received packets"
    case .packetsOut: return "Sent packets"
    case .ports: return "Ports"
    case .privateMemory: return "Private memory bytes"
    case .sharedMemory: return "Shared memory bytes"
    case .purgeable: return "Purgeable bytes"
    case .compressed: return "Compressed bytes"
    case .wakeups: return "Idle wakeups per second"
    }
  }
}
