import AppKit
import SMCKit
import SwiftUI

struct MenuBarLabel: View {
  @ObservedObject var model: FanModel
  @AppStorage(Pref.menuBarStyle) private var style = MenuBarStyle.temperature.rawValue
  @AppStorage(Pref.fahrenheit) private var fahrenheit = false

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: model.daemonAlive && model.config.mode != .auto ? "fan.fill" : "fan")
      if let text { Text(text).monospacedDigit() }
    }
  }

  private var text: String? {
    switch MenuBarStyle(rawValue: style) ?? .temperature {
    case .icon: return nil
    case .temperature:
      return model.thermal?.driving(for: model.config.sensor).map { Temperature.format($0.celsius, fahrenheit: fahrenheit, unit: false) }
    case .rpm:
      guard let rpm = model.fans.map(\.actual).max() else { return nil }
      return "\(Int(rpm))"
    }
  }
}

struct MenuBarMenu: View {
  @EnvironmentObject var model: FanModel
  @Environment(\.openWindow) private var openWindow
  @AppStorage(Pref.fahrenheit) private var fahrenheit = false

  var body: some View {
    if let th = model.thermal {
      Text("CPU \(Temperature.format(th.cpu, fahrenheit: fahrenheit)) · GPU \(Temperature.format(th.gpu, fahrenheit: fahrenheit))")
    }
    ForEach(model.fans) { fan in
      Text("Fan \(fan.id): \(Int(fan.actual)) rpm")
    }
    Text(model.helperSummary)

    Divider()

    Picker("Mode", selection: $model.config.mode) {
      ForEach(FanMode.allCases) { Text($0.label).tag($0) }
    }
    .pickerStyle(.inline)

    Menu("Preset") {
      Button("Quiet") { model.applyPreset(FanConfig.quiet) }
      Button("Balanced") { model.applyPreset(FanConfig.balanced) }
      Button("Aggressive") { model.applyPreset(FanConfig.aggressive) }
    }

    Divider()

    Button("Open Curv") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    .keyboardShortcut("o")

    SettingsLink { Text("Settings…") }
      .keyboardShortcut(",")

    Button("Check for Updates…") { Task { await model.updater.checkAndPresent() } }

    Divider()

    Button("Quit Curv") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
