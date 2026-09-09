import AppKit
import SwiftUI

@main struct ActivityMonitorApp: App {
  @NSApplicationDelegateAdaptor(MonitorAppDelegate.self) private var appDelegate
  @State private var services = MonitorServices()
  private var monitor: Monitor { services.monitor }
  private var navigation: MonitorNavigation { services.navigation }
  @AppStorage("showMenuBar") var showMenuBar = false
  var body: some Scene {
    Window("Activity Monitor", id: "monitor") {
      ContentView().environmentObject(monitor).environmentObject(navigation)
        .background(TrayLifecycle(services: services, enabled: showMenuBar))
    }.defaultSize(width: 1440, height: 900)
      .windowStyle(.hiddenTitleBar)
      .commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Layout") {
          Button("Compact Window") { resize(width: 520, height: 760) }.keyboardShortcut(
            "1", modifiers: [.command, .option])
          Button("Minimum Window") { resize(width: 420, height: 480) }.keyboardShortcut(
            "2", modifiers: [.command, .option])
          Button("Default Window") { resize(width: 1440, height: 900) }.keyboardShortcut(
            "3", modifiers: [.command, .option])
          Button("Expanded Window") {
            guard let window = NSApp.mainWindow, let screen = window.screen else { return }
            window.setFrame(screen.visibleFrame, display: true, animate: false)
          }
        }

        CommandMenu("Monitor") {
          MonitorPauseCommand(monitor: monitor)
          Button("Show Menu Bar Monitor") {
            showMenuBar = true
            services.tray.setEnabled(true)
            services.tray.togglePopover()
          }.keyboardShortcut("m", modifiers: [.command, .shift])
          Button("Export Processes…") { monitor.export(monitor.rows) }.keyboardShortcut(
            "e", modifiers: [.command, .shift])
        }
      }
  }
  private func resize(width: CGFloat, height: CGFloat) {
    guard let window = NSApp.mainWindow else { return }
    window.setContentSize(NSSize(width: width, height: height))
    window.center()
  }

}

private struct MonitorPauseCommand: View {
  let monitor: Monitor
  @State private var paused = false
  var body: some View {
    Button(paused ? "Resume Monitoring" : "Pause Monitoring") { monitor.paused.toggle() }
      .keyboardShortcut(" ", modifiers: [])
      .onReceive(monitor.$paused.removeDuplicates()) { paused = $0 }
  }
}

@MainActor final class MonitorAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
