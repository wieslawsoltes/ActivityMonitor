import Foundation

/// Small value caches used by rendering. Keys include every input; callers retain
/// ordinary values, never views or process objects. All access is synchronized.
final class BoundedCache<Key: Hashable, Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Key: Value] = [:]
  let capacity: Int
  init(capacity: Int) { self.capacity = max(1, capacity) }
  var count: Int { lock.withLock { values.count } }
  func value(for key: Key, create: () -> Value) -> Value {
    if let cached = lock.withLock({ values[key] }) { return cached }
    let value = create()
    lock.withLock {
      if values.count >= capacity { values.removeAll(keepingCapacity: true) }
      values[key] = value
    }
    return value
  }
}
