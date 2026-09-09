// Compile with GPUCollector.swift; see docs/GPU_VALIDATION.md. No elevated privileges.
import Foundation
import Metal

@main struct GPUWorkload {
  static func main() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw NSError(
        domain: "GPUWorkload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
    }
    let library = try device.makeLibrary(
      source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void work(device float *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
          float x = float(i) * 0.0001f;
          for (uint j = 0; j < 40000; ++j) { x = sin(x) + 1.001f; }
          out[i] = x;
        }
        """, options: nil)
    let pipeline = try device.makeComputePipelineState(
      function: library.makeFunction(name: "work")!)
    let buffer = device.makeBuffer(length: 262144 * 4, options: .storageModeShared)!
    let reader = GPUHardwareReader()
    func counter() -> UInt64 {
      reader.read().clients.filter { $0.pid == getpid() }.reduce(0) { $0 + $1.nanoseconds }
    }
    func submit() throws -> Double {
      let command = queue.makeCommandBuffer()!
      let encoder = command.makeComputeCommandEncoder()!
      encoder.setComputePipelineState(pipeline)
      encoder.setBuffer(buffer, offset: 0, index: 0)
      encoder.dispatchThreads(
        MTLSize(width: 262144, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
      encoder.endEncoding()
      command.commit()
      command.waitUntilCompleted()
      guard command.status == .completed else {
        throw command.error ?? NSError(domain: "GPUWorkload", code: 2)
      }
      return command.gpuEndTime - command.gpuStartTime
    }
    _ = try submit()
    Thread.sleep(forTimeInterval: 1)
    let before = counter()
    var commandSeconds = 0.0
    for _ in 0..<100 { commandSeconds += try submit() }
    Thread.sleep(forTimeInterval: 1)
    let after = counter()
    guard after > before else {
      throw NSError(
        domain: "GPUWorkload", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Driver did not report advancing GPU counters"])
    }
    print("PID: \(getpid()); device: \(device.name)")
    print("Metal command-buffer elapsed seconds: \(commandSeconds)")
    print("Driver GPU nanoseconds: \(after); driver GPU seconds: \(Double(after) / 1e9)")
    print("Observed driver GPU seconds: \(Double(after - before) / 1e9)")
    print("Compare total driver seconds with Apple Activity Monitor's GPU Time column.")
    fflush(stdout)
    if CommandLine.arguments.contains("--hold") { Thread.sleep(forTimeInterval: 120) }
  }
}
