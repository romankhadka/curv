import SMCKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject var model: FanModel
  @AppStorage(Pref.fahrenheit) private var fahrenheit = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      liveSection
      curveSection
      helperSection
      if let error = model.lastError {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .padding(20)
    .frame(width: 680)
  }

  private var header: some View {
    HStack {
      Text("Curv").font(.title2.bold())
      Spacer()
      Picker("Mode", selection: $model.config.mode) {
        ForEach(FanMode.allCases) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 320)
    }
  }

  private var liveSection: some View {
    GroupBox("Live") {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Temperature")
          Spacer()
          if let th = model.thermal, let hot = th.driving(for: model.config.sensor) {
            Text(Temperature.format(hot.celsius, fahrenheit: fahrenheit)).monospacedDigit().bold()
            Text("driving: \(hot.label) · CPU \(Temperature.format(th.cpu, fahrenheit: fahrenheit, unit: false)) · GPU \(Temperature.format(th.gpu, fahrenheit: fahrenheit, unit: false)) · \(th.sensorCount) sensors")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("n/a").foregroundStyle(.secondary)
          }
        }
        ForEach(model.fans) { fan in
          HStack {
            Text("Fan \(fan.id)")
            Spacer()
            Text("\(Int(fan.actual)) rpm").monospacedDigit().bold()
            Text("target \(Int(fan.target)) · range \(Int(fan.min))–\(Int(fan.max)) · \(fan.manual ? "manual" : "auto")")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if !model.smcAvailable {
          Text("Cannot open AppleSMC on this Mac.").foregroundStyle(.red)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var curveSection: some View {
    GroupBox("Curve") {
      VStack(spacing: 10) {
        CurveEditor(
          points: $model.config.points,
          currentTemp: model.thermal?.driving(for: model.config.sensor).map { Double($0.celsius) },
          fahrenheit: fahrenheit,
          onCommit: { model.sortPoints() }
        )
        .frame(height: 240)

        HStack {
          Text("Presets").foregroundStyle(.secondary)
          Button("Quiet") { model.applyPreset(FanConfig.quiet) }
          Button("Balanced") { model.applyPreset(FanConfig.balanced) }
          Button("Aggressive") { model.applyPreset(FanConfig.aggressive) }
          Spacer()
          Button("Add point") { model.addPoint() }
        }

        VStack(spacing: 4) {
          ForEach($model.config.points) { $point in
            HStack(spacing: 8) {
              Text(Temperature.format(point.celsius, fahrenheit: fahrenheit)).monospacedDigit().frame(width: 54, alignment: .trailing)
              Slider(value: $point.celsius, in: 30...110, step: 1)
              Text("\(Int(point.percent)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
              Slider(value: $point.percent, in: 0...100, step: 1)
              Button { model.removePoint(point.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .disabled(model.config.points.count <= 2)
            }
          }
        }

        Text("Percent maps onto each fan's own min–max RPM. At \(Temperature.format(model.config.safetyCelsius, fahrenheit: fahrenheit)) and above the helper forces 100%. macOS thermal throttling still applies.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .opacity(model.config.mode == .curve ? 1 : 0.55)
  }

  private var helperSection: some View {
    GroupBox("Helper") {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Circle().fill(statusColor).frame(width: 10, height: 10)
          Text(statusText)
          Spacer()
          if model.helperInstalled {
            if model.helperOutdated { Button("Update helper…") { model.installHelper() } }
            Button("Restart") { model.restartHelper() }
            Button("Uninstall", role: .destructive) { model.uninstallHelper() }
          } else {
            Button("Install…") { model.installHelper() }
          }
        }
        if let d = model.daemon, model.daemonAlive {
          Text("Applied \(Int(d.percent))% at \(Temperature.format(d.celsius, fahrenheit: fahrenheit)) (\(d.sensor)) · \(d.mode.label) · targets \(d.targets.map { String(Int($0)) }.joined(separator: ", ")) rpm")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text("The helper is a LaunchDaemon that runs as root and applies this window's settings, even when the app is closed. Installing asks for your password once. Log: \(Helper.logPath)")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var statusText: String {
    if !model.helperInstalled { return "Not installed. Fans stay under macOS control." }
    let base = model.daemonAlive ? "Running" : model.helperLoaded ? "Loaded, waiting for first report" : "Installed, not running"
    return model.helperOutdated ? "\(base) · this app has a newer helper" : base
  }

  private var statusColor: Color {
    if !model.helperInstalled { return .gray }
    if model.helperOutdated { return .yellow }
    return model.daemonAlive ? .green : .orange
  }
}
