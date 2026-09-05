import AppKit
import SwiftUI

@main struct ActivityMonitorApp: App {
  @StateObject private var monitor = Monitor()
  @AppStorage("showMenuBar") var showMenuBar = false
  var body: some Scene {
    WindowGroup { ContentView().environmentObject(monitor) }.defaultSize(width: 1440, height: 900)
      .windowStyle(.hiddenTitleBar)
      .commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Monitor") {
          Button(monitor.paused ? "Resume Monitoring" : "Pause Monitoring") {
            monitor.paused.toggle()
          }.keyboardShortcut(" ", modifiers: [])
          Button("Export Processes…") { monitor.export(monitor.rows) }.keyboardShortcut(
            "e", modifiers: [.command, .shift])
        }
      }
    MenuBarExtra(isInserted: $showMenuBar) {
      Text("CPU \(String(format:"%.1f%%",monitor.userCPU+monitor.systemCPU))")
      Text("Memory \(bytes(monitor.system.active+monitor.system.wired+monitor.system.compressed))")
      Divider()
      Button("Show Activity Monitor") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
      }
      Button(monitor.paused ? "Resume" : "Pause") { monitor.paused.toggle() }
      Button("Quit") { NSApp.terminate(nil) }
    } label: {
      Label(
        String(format: "%.0f%%", monitor.userCPU + monitor.systemCPU),
        systemImage: "waveform.path.ecg")
    }

  }
}
