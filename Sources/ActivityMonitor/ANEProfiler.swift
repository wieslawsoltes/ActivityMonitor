import Foundation
import Darwin

/// A short, user-initiated Instruments recording. Its intervals describe system-wide
/// ANE activity during the recording, not per-process or per-core utilization.
struct ANEProfileResult: Equatable {
  let recordedAt: Date
  let durationSeconds: Double
  let activeSeconds: Double
  let predictionCount: Int
  let averagePredictionMilliseconds: Double?

  var observedActivityPercent: Double {
    guard durationSeconds > 0 else { return 0 }
    return min(100, max(0, activeSeconds / durationSeconds * 100))
  }
}

enum ANEProfileError: LocalizedError {
  case instrumentsUnavailable
  case timedOut
  case commandFailed(String)
  case unsupportedExport

  var errorDescription: String? {
    switch self {
    case .instrumentsUnavailable:
      return "Instruments is unavailable. Install Xcode to record ANE activity."
    case .timedOut:
      return "Instruments did not finish the recording in time."
    case .commandFailed(let message):
      return message.isEmpty ? "Instruments could not record ANE activity." : message
    case .unsupportedExport:
      return "This Instruments version does not export ANE activity intervals."
    }
  }
}

/// The Instruments XML export contains ID references for repeated labels and states.
/// Keep this parser separate from the recorder so format changes fail visibly.
enum ANETraceParser {
  static func parse(toc: Data, intervals: Data, recordedAt: Date = Date()) throws
    -> ANEProfileResult
  {
    let tocDocument = try XMLDocument(data: toc)
    guard let durationText = try tocDocument.nodes(
      forXPath: "/trace-toc/run[1]/info/summary/duration").first?.stringValue,
      let duration = Double(durationText), duration.isFinite, duration > 0
    else { throw ANEProfileError.unsupportedExport }

    let document = try XMLDocument(data: intervals)
    guard let schema = try document.nodes(
      forXPath: "/trace-query-result/node/schema").first as? XMLElement,
      schema.attribute(forName: "name")?.stringValue == "ane-hw-intervals-internal"
    else { throw ANEProfileError.unsupportedExport }

    var labels: [String: String] = [:]
    var states: [String: String] = [:]
    var depths: [String: String] = [:]
    var startValues: [String: String] = [:]
    var durationValues: [String: String] = [:]
    var activeRanges: [(Double, Double)] = []
    var predictionDurations: [Double] = []
    for case let row as XMLElement in try document.nodes(
      forXPath: "/trace-query-result/node/row")
    {
      func text(_ name: String, references: inout [String: String]) -> String? {
        guard let element = row.elements(forName: name).first else { return nil }
        if let reference = element.attribute(forName: "ref")?.stringValue {
          return references[reference]
        }
        let value = element.attribute(forName: "fmt")?.stringValue ?? element.stringValue
        if let id = element.attribute(forName: "id")?.stringValue, let value {
          references[id] = value
        }
        return value
      }
      func raw(_ name: String, references: inout [String: String]) -> String? {
        guard let element = row.elements(forName: name).first else { return nil }
        if let reference = element.attribute(forName: "ref")?.stringValue {
          return references[reference]
        }
        let value = element.stringValue
        if let id = element.attribute(forName: "id")?.stringValue, let value {
          references[id] = value
        }
        return value
      }
      let label = text("formatted-label", references: &labels) ?? ""
      let depth = text("metal-nesting-level", references: &depths) ?? "0"
      let state = text("gpu-state", references: &states)
      guard let startText = raw("start-time", references: &startValues),
        let durationText = raw("duration", references: &durationValues),
        let startNanos = Double(startText), let durationNanos = Double(durationText),
        startNanos.isFinite, durationNanos.isFinite, durationNanos > 0,
        state == "Active"
      else { continue }
      let start = max(0, startNanos / 1e9)
      let end = min(duration, (startNanos + durationNanos) / 1e9)
      guard end > start else { continue }
      activeRanges.append((start, end))
      if depth == "0", label.localizedCaseInsensitiveContains("Prediction") {
        predictionDurations.append(durationNanos / 1e6)
      }
    }

    activeRanges.sort { $0.0 < $1.0 }
    var activeSeconds = 0.0
    var mergedEnd = 0.0
    for (start, end) in activeRanges {
      activeSeconds += max(0, end - max(start, mergedEnd))
      mergedEnd = max(mergedEnd, end)
    }
    return ANEProfileResult(
      recordedAt: recordedAt, durationSeconds: duration,
      activeSeconds: activeSeconds, predictionCount: predictionDurations.count,
      averagePredictionMilliseconds: predictionDurations.isEmpty ? nil
        : predictionDurations.reduce(0, +) / Double(predictionDurations.count))
  }
}

final class ANEInstrumentsProfiler {
  func capture() throws -> ANEProfileResult {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(
      "ActivityMonitor-ANE-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    defer { try? manager.removeItem(at: directory) }

    let tool: String
    do {
      tool = try command(
        ["--find", "xctrace"], in: directory, output: "find.txt", timeout: 10)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { throw ANEProfileError.instrumentsUnavailable }
    guard !tool.isEmpty, manager.isExecutableFile(atPath: tool) else {
      throw ANEProfileError.instrumentsUnavailable
    }
    let trace = directory.appendingPathComponent("neural-engine.trace")
    _ = try command(
      ["xctrace", "record", "--template", "Core ML", "--all-processes",
       "--time-limit", "5s", "--output", trace.path],
      in: directory, output: "record.txt", timeout: 180)
    let toc = try command(
      ["xctrace", "export", "--input", trace.path, "--toc"],
      in: directory, output: "toc.xml", timeout: 60)
    let intervals = try command(
      ["xctrace", "export", "--input", trace.path, "--xpath",
       "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"ane-hw-intervals-internal\"]"],
      in: directory, output: "intervals.xml", timeout: 60)
    guard let tocData = toc.data(using: .utf8), let intervalData = intervals.data(using: .utf8),
      intervalData.count <= 30_000_000 else { throw ANEProfileError.unsupportedExport }
    return try ANETraceParser.parse(toc: tocData, intervals: intervalData)
  }

  private func command(_ arguments: [String], in directory: URL,
    output: String, timeout: Double) throws -> String
  {
    let outputURL = directory.appendingPathComponent(output)
    let errorURL = directory.appendingPathComponent(output + ".err")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer { try? outputHandle.close(); try? errorHandle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() }
    catch { throw ANEProfileError.instrumentsUnavailable }
    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      if finished.wait(timeout: .now() + 5) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        _ = finished.wait(timeout: .now() + 5)
      }
      throw ANEProfileError.timedOut
    }
    guard process.terminationStatus == 0 else {
      let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
      throw ANEProfileError.commandFailed(String(message.suffix(500))
        .trimmingCharacters(in: .whitespacesAndNewlines))
    }
    let size = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int
      ?? 0
    guard size <= 30_000_000 else { throw ANEProfileError.unsupportedExport }
    return try String(contentsOf: outputURL, encoding: .utf8)
  }
}

@MainActor final class ANEProfileController: ObservableObject {
  @Published private(set) var isCapturing = false
  @Published private(set) var result: ANEProfileResult?
  @Published private(set) var error: String?

  func capture() {
    guard !isCapturing else { return }
    isCapturing = true
    result = nil
    error = nil
    Task {
      do {
        result = try await Task.detached(priority: .userInitiated) {
          try ANEInstrumentsProfiler().capture()
        }.value
      } catch {
        self.error = error.localizedDescription
      }
      isCapturing = false
    }
  }
}
