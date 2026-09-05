// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ActivityMonitor", platforms: [.macOS(.v14)], products: [.executable(name: "ActivityMonitor", targets: ["ActivityMonitor"])], targets: [.target(name: "SystemBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]), .executableTarget(name: "ActivityMonitor", dependencies: ["SystemBridge"], linkerSettings: [.linkedFramework("AppKit")]), .testTarget(name: "ActivityMonitorTests", dependencies: ["ActivityMonitor"])])
