import Foundation

struct ProcessNetworkCounters {
  let received: UInt64
  let sent: UInt64
}
// nettop is Apple's bundled unprivileged network accounting client. Use its
// machine-readable output, disable DNS, and request only the two known columns.
func readProcessNetwork() -> [Int32: ProcessNetworkCounters] {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
  process.arguments = ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"]
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
  for line in text.split(separator: "\n").dropFirst() {
    // Parse from the right so commas and dots in process names are harmless.
    var fields = line.split(separator: ",", omittingEmptySubsequences: false)
    if fields.last?.isEmpty == true { fields.removeLast() }
    guard fields.count >= 3, let sent = UInt64(fields.removeLast()),
      let received = UInt64(fields.removeLast()),
      let identity = fields.joined(separator: ",").split(separator: ".").last,
      let pid = Int32(identity)
    else { continue }
    result[pid] = ProcessNetworkCounters(received: received, sent: sent)
  }
  return result
}
