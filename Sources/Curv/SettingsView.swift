import AppKit
import SMCKit
import SwiftUI

struct SettingsView: View {
  @State private var tab = 0

  var body: some View {
    TabView(selection: $tab) {
      GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(0)
      CurveSettings().tabItem { Label("Curve", systemImage: "chart.xyaxis.line") }.tag(1)
      HelperSettings().tabItem { Label("Helper", systemImage: "lock.shield") }.tag(2)
      AboutSettings().tabItem { Label("About", systemImage: "info.circle") }.tag(3)
    }
    .frame(width: 480, height: 600)
  }
}

struct GeneralSettings: View {
  @AppStorage(Pref.showMenuBar) private var showMenuBar = true
  @AppStorage(Pref.menuBarStyle) private var menuBarStyle = MenuBarStyle.temperature.rawValue
  @AppStorage(Pref.showDockIcon) private var showDockIcon = true
  @AppStorage(Pref.openWindowAtLaunch) private var openWindowAtLaunch = true
  @AppStorage(Pref.fahrenheit) private var fahrenheit = false
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var loginError: String?

  var body: some View {
    Form {
      Section("Startup") {
        Toggle("Launch at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, on in
            do { try LaunchAtLogin.set(on); loginError = nil } catch {
              loginError = error.localizedDescription
              launchAtLogin = LaunchAtLogin.isEnabled
            }
          }
        if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
        Toggle("Open the window at launch", isOn: $openWindowAtLaunch)
          .disabled(!showMenuBar)
        Text(showMenuBar
             ? "Turn this off to start Curv quietly in the menu bar."
             : "The window always opens when there is no menu bar item.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Menu bar") {
        Toggle("Show in menu bar", isOn: $showMenuBar)
        Picker("Menu bar shows", selection: $menuBarStyle) {
          ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .disabled(!showMenuBar)
      }

      Section("Appearance") {
        Toggle("Show Dock icon", isOn: $showDockIcon)
          .onChange(of: showDockIcon) { _, on in
            NSApp.setActivationPolicy(on ? .regular : .accessory)
            NSApp.activate(ignoringOtherApps: true)
          }
          .disabled(!showMenuBar)
        Picker("Temperature unit", selection: $fahrenheit) {
          Text("Celsius").tag(false)
          Text("Fahrenheit").tag(true)
        }
        .pickerStyle(.segmented)
      }
    }
    .formStyle(.grouped)
    .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
  }
}

struct CurveSettings: View {
  @EnvironmentObject var model: FanModel
  @AppStorage(Pref.fahrenheit) private var fahrenheit = false

  var body: some View {
    Form {
      Section("Sensor") {
        Picker("Drive the curve with", selection: $model.config.sensor) {
          ForEach(SensorSource.allCases) { Text($0.label).tag($0) }
        }
        Text("CPU is the average of the CPU-die sensors; GPU is the average of the GPU sensors. Single cores spike well above either.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Safety") {
        LabeledContent("Force 100% at") {
          HStack {
            Slider(value: $model.config.safetyCelsius, in: 85...105, step: 1)
            Text(Temperature.format(model.config.safetyCelsius, fahrenheit: fahrenheit))
              .monospacedDigit().frame(width: 56, alignment: .trailing)
          }
        }
        Text("Above this temperature the helper ignores the curve and runs the fans flat out. macOS keeps throttling regardless.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("Helper") {
        LabeledContent("Re-apply every") {
          HStack {
            Slider(value: $model.config.intervalSeconds, in: 1...10, step: 1)
            Text("\(Int(model.config.intervalSeconds)) s").monospacedDigit().frame(width: 56, alignment: .trailing)
          }
        }
        Text("Shorter is more responsive; longer is quieter on the sensors. The helper picks the change up on its next tick.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

struct HelperSettings: View {
  @EnvironmentObject var model: FanModel

  var body: some View {
    Form {
      Section("Status") {
        LabeledContent("Helper", value: model.helperSummary)
        if let d = model.daemon, model.daemonAlive {
          LabeledContent("Last applied", value: d.mode == .auto
            ? "Automatic control at \(Temperature.format(d.celsius))"
            : "\(Int(d.percent))% at \(Temperature.format(d.celsius)) (\(d.sensor))")
        }
        HStack {
          if model.helperInstalled {
            if model.helperOutdated { Button("Update helper…") { model.installHelper() } }
            Button("Restart") { model.restartHelper() }
            Button("Uninstall…", role: .destructive) { model.uninstallHelper() }
          } else {
            Button("Install helper…") { model.installHelper() }
          }
          Spacer()
        }
      }

      Section("Inspect") {
        HStack {
          Button("Open Log") { NSWorkspace.shared.open(URL(fileURLWithPath: Helper.logPath)) }
            .disabled(!FileManager.default.fileExists(atPath: Helper.logPath))
          Button("Reveal Config in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.configURL]) }
            .disabled(!FileManager.default.fileExists(atPath: model.configURL.path))
          Spacer()
        }
      }

      Section("Files") {
        LabeledContent("Daemon", value: Helper.binary)
        LabeledContent("LaunchDaemon", value: Helper.plist)
        LabeledContent("Config", value: model.configURL.path)
        LabeledContent("Log", value: Helper.logPath)
      }
      .font(.callout)

      Section {
        Text("The helper runs as root because writing a fan target through the SMC requires it. It reads one file and writes fan targets; nothing else. Uninstall stops it and returns the fans to macOS.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

struct AboutSettings: View {
  @EnvironmentObject var model: FanModel

  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
      Text("Curv").font(.title.bold())
      Text("Version \(Updater.currentVersion)").foregroundStyle(.secondary)
      Text("Your fans, your curve.").italic().foregroundStyle(.secondary)

      HStack {
        Button("Website") { NSWorkspace.shared.open(URL(string: "https://curv.romn.dev")!) }
        Button("Source on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/romankhadka/curv")!) }
        Button("Check for Updates…") { Task { await model.updater.checkAndPresent() } }
          .disabled(model.updater.state == .checking)
      }
      .padding(.top, 4)

      Text("MIT License · © 2026 Roman Khadka").font(.caption).foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
  }
}
