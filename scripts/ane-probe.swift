import Foundation

@main struct ANEProbe {
  static func main() {
    let sample = ANEHardwareReader().read()
    print("ANE detected: \(sample.available)")
    print("Devices: \(sample.engineCount.map(String.init) ?? "unavailable")")
    print("Cores: \(sample.coreCount.map(String.init) ?? "unavailable")")
    print("Direct connections: \(sample.connectionCount.map(String.init) ?? "unavailable")")
    print("Processes with direct connections: \(sample.processCount.map(String.init) ?? "unavailable")")
  }
}
