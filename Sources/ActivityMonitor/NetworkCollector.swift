import Darwin
import Foundation

struct ProcessNetworkCounters {
  let received: UInt64
  let sent: UInt64
  var packetsIn: UInt64? = nil
  var packetsOut: UInt64? = nil
}
// nettop is Apple's bundled unprivileged network accounting client. Use its
// machine-readable output, disable DNS, and request named byte and packet columns.
func readProcessNetwork() -> [Int32: ProcessNetworkCounters] {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
  process.arguments = [
    "-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out,packets_in,packets_out",
  ]
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do {
    try process.run()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
      if process.isRunning { process.terminate() }
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
      return [:]
    }
    return parseProcessNetwork(text)
  } catch { return [:] }
}
func parseProcessNetwork(_ text: String) -> [Int32: ProcessNetworkCounters] {
  var result: [Int32: ProcessNetworkCounters] = [:]
  let lines = text.split(separator: "\n")
  guard let header = lines.first else { return [:] }
  var names = header.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
  if names.last == "" { names.removeLast() }
  guard names.count >= 3 else { return [:] }
  let columns = Array(names.dropFirst())
  for line in lines.dropFirst() {
    var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    if fields.last == "" { fields.removeLast() }
    guard fields.count > columns.count else { continue }
    let values = Array(fields.suffix(columns.count))
    let identity = fields.dropLast(columns.count).joined(separator: ",")
    guard let suffix = identity.split(separator: ".").last, let pid = Int32(suffix) else {
      continue
    }
    let counters = Dictionary(zip(columns, values), uniquingKeysWith: { first, _ in first })
    guard let received = counters["bytes_in"].flatMap(UInt64.init),
      let sent = counters["bytes_out"].flatMap(UInt64.init)
    else { continue }
    result[pid] = ProcessNetworkCounters(
      received: received, sent: sent,
      packetsIn: counters["packets_in"].flatMap(UInt64.init),
      packetsOut: counters["packets_out"].flatMap(UInt64.init))
  }
  return result
}

/// Slow nettop work never delays the first process/system snapshot or the one-second sampler.
/// Only one request may run at a time; identity checks keep cached counters safe across PID reuse.
final class ProcessNetworkSampler: @unchecked Sendable {
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "ActivityMonitor.network", qos: .utility)
  private var cache: [Int32: (UInt64, ProcessNetworkCounters)] = [:]
  private var completed = Date.distantPast
  private var inFlight = false
  private let read: () -> [Int32: ProcessNetworkCounters]
  private let identity: (Int32) -> UInt64?

  init(
    read: @escaping () -> [Int32: ProcessNetworkCounters] = readProcessNetwork,
    identity: @escaping (Int32) -> UInt64? = processStartTime
  ) {
    self.read = read
    self.identity = identity
  }

  func collect(identities: [Int32: UInt64], now: Date) -> [Int32: ProcessNetworkCounters] {
    let shouldStart = lock.withLock {
      guard !inFlight, now.timeIntervalSince(completed) >= 5 else { return false }
      inFlight = true
      return true
    }
    if shouldStart {
      queue.async { [self] in
        let counters = read()
        let next = Dictionary(
          uniqueKeysWithValues: counters.compactMap {
            pid, value -> (Int32, (UInt64, ProcessNetworkCounters))? in
            guard let start = identities[pid], identity(pid) == start else { return nil }
            return (pid, (start, value))
          })
        lock.withLock {
          cache = next
          completed = Date()
          inFlight = false
        }
      }
    }
    return lock.withLock {
      Dictionary(
        uniqueKeysWithValues: cache.compactMap { pid, value in
          identities[pid] == value.0 ? (pid, value.1) : nil
        })
    }
  }
}

func processStartTime(_ pid: Int32) -> UInt64? {
  var value = proc_bsdinfo()
  let size = Int32(MemoryLayout<proc_bsdinfo>.size)
  guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &value, size) == size else { return nil }
  return value.pbi_start_tvsec * 1_000_000 + value.pbi_start_tvusec
}
