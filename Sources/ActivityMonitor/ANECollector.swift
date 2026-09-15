import Foundation
import IOKit

/// These are open direct-path driver connections, not ANE execution or utilization.
struct ANEHardwareSnapshot: Equatable {
  var available: Bool
  var engineCount: Int?
  var coreCount: Int?
  var connections: [Int32: Int]
  var connectionsReadable = false
  var connectionCount: Int? { connectionsReadable ? connections.values.reduce(0, +) : nil }
  var processCount: Int? { connectionsReadable ? connections.count : nil }
}

enum ANERegistryParser {
  static func positiveCount(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let count = Int(number.stringValue), (1...1024).contains(count)
    else { return nil }
    return count
  }
  static func deviceCount(_ properties: [String: Any], key: String) -> Int? {
    positiveCount((properties["DeviceProperties"] as? [String: Any])?[key])
  }
  static func directClientPID(className: String, properties: [String: Any]) -> Int32? {
    guard className == "H1xANELoadBalancerDirectPathClient",
      let creator = properties["IOUserClientCreator"] as? String,
      creator.hasPrefix("pid "),
      let pid = Int32(creator.dropFirst(4).split(separator: ",", maxSplits: 1).first ?? ""),
      pid > 0
    else { return nil }
    return pid
  }
}

/// Read-only public IOKit registry access. Driver properties can vary by Mac and OS.
final class ANEHardwareReader {
  func read() -> ANEHardwareSnapshot {
    var snapshot = ANEHardwareSnapshot(
      available: false, engineCount: nil, coreCount: nil, connections: [:])
    var traversedLoadBalancer = false
    var clientsReadable = true
    visit("H1xANELoadBalancer") { entry, properties in
      snapshot.available = true
      snapshot.engineCount = ANERegistryParser.deviceCount(
        properties, key: "ANEDevicePropertyNumANEs")
      var children: io_iterator_t = 0
      guard IORegistryEntryCreateIterator(
        entry, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children)
        == KERN_SUCCESS else {
        clientsReadable = false
        return
      }
      traversedLoadBalancer = true
      defer { IOObjectRelease(children) }
      while case let child = IOIteratorNext(children), child != 0 {
        defer { IOObjectRelease(child) }
        let className = IOObjectCopyClass(child)?.takeRetainedValue() as String? ?? ""
        guard className == "H1xANELoadBalancerDirectPathClient" else { continue }
        if let pid = ANERegistryParser.directClientPID(
          className: className, properties: Self.properties(child)) {
          snapshot.connections[pid, default: 0] += 1
        } else {
          clientsReadable = false
        }
      }
    }
    visit("H11ANEIn") { _, properties in
      snapshot.available = true
      snapshot.coreCount = ANERegistryParser.deviceCount(
        properties, key: "ANEDevicePropertyNumANECores")
    }
    snapshot.connectionsReadable = traversedLoadBalancer && clientsReadable
    return snapshot
  }
  private func visit(_ service: String, body: (io_registry_entry_t, [String: Any]) -> Void) {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching(service), &iterator) == KERN_SUCCESS
    else { return }
    defer { IOObjectRelease(iterator) }
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      body(entry, Self.properties(entry))
    }
  }
  private static func properties(_ entry: io_registry_entry_t) -> [String: Any] {
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(
      entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS
    else { return [:] }
    return properties?.takeRetainedValue() as? [String: Any] ?? [:]
  }
}
