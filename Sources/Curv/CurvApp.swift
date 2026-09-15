import AppKit
import SwiftUI

@main
struct CurvApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = FanModel()
  @AppStorage(Pref.showMenuBar) private var showMenuBar = true

  init() {
    Pref.registerDefaults()
    NSApplication.shared.setActivationPolicy(Pref.showsDockIcon ? .regular : .accessory)
  }

  var body: some Scene {
    Window("Curv", id: "main") {
      ContentView()
        .environmentObject(model)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
    .windowResizability(.contentSize)
    .defaultLaunchBehavior(Pref.opensWindowAtLaunch || !Pref.showsMenuBar ? .presented : .suppressed)
    .restorationBehavior(.disabled)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { Task { await model.updater.checkAndPresent() } }
      }
    }

    Settings {
      SettingsView().environmentObject(model)
    }

    MenuBarExtra(isInserted: $showMenuBar) {
      MenuBarMenu().environmentObject(model)
    } label: {
      MenuBarLabel(model: model)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  /// With a menu bar item the app stays alive after its last window closes.
  /// Without one, quitting on close is the only way the user can reach it again.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !Pref.showsMenuBar
  }
}
