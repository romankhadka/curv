import AppKit
import SwiftUI

@main
struct FanCurveApp: App {
  @StateObject private var model = FanModel()

  init() {
    NSApplication.shared.setActivationPolicy(.regular)
  }

  var body: some Scene {
    WindowGroup("Curv") {
      ContentView()
        .environmentObject(model)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
    .windowResizability(.contentSize)
  }
}
