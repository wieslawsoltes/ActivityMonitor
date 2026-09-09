import Foundation
import SystemBridge

/// System capacity and process execution time intentionally use different percentage scales.
enum CPUAccounting {
  static let systemHelp =
    "Total CPU capacity across all logical processors. User + System + Idle = 100%. Process percentages use a different scale: 100% is one logical processor."
  static let processHelp =
    "CPU execution time: 100% is one logical processor, so a process using several processors can exceed 100%."

  static func processPercent(current: AMProcess, previous: AMProcess?, elapsed: TimeInterval)
    -> Double
  {
    guard let previous, current.accessible != 0, previous.accessible != 0,
      current.start == previous.start, current.cpu >= previous.cpu,
      elapsed.isFinite, elapsed > 0
    else { return 0 }
    return Double(current.cpu - previous.cpu) / 1e9 / elapsed * 100
  }

  static func systemPercent(current: AMSystem, previous: AMSystem) -> (
    user: Double, system: Double, idle: Double
  ) {
    func delta(_ current: UInt64, _ previous: UInt64) -> Double {
      Double(UInt32(truncatingIfNeeded: current) &- UInt32(truncatingIfNeeded: previous))
    }
    let user = delta(current.user, previous.user)
    let system = delta(current.system, previous.system)
    let idle = delta(current.idle, previous.idle)
    let total = max(1, user + system + idle)
    return (user / total * 100, system / total * 100, idle / total * 100)
  }
}
