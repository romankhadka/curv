import SMCKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject var model: FanModel

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
          if let th = model.thermal, let hot = th.driving {
            Text("\(hot.celsius, specifier: "%.0f") °C").monospacedDigit().bold()
            Text("driving: \(hot.label) · CPU \(th.cpu.map { String(format: "%.0f", $0) } ?? "-") · GPU \(th.gpu.map { String(format: "%.0f", $0) } ?? "-") · \(th.sensorCount) sensors")
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
          currentTemp: model.thermal?.driving.map { Double($0.celsius) },
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
              Text("\(Int(point.celsius)) °C").monospacedDigit().frame(width: 50, alignment: .trailing)
              Slider(value: $point.celsius, in: 30...110, step: 1)
              Text("\(Int(point.percent)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
              Slider(value: $point.percent, in: 0...100, step: 1)
              Button { model.removePoint(point.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .disabled(model.config.points.count <= 2)
            }
          }
        }

        Text("Percent maps onto each fan's own min–max RPM. At \(Int(model.config.safetyCelsius)) °C and above the helper forces 100%. macOS thermal throttling still applies.")
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
            Button("Restart") { model.restartHelper() }
            Button("Uninstall", role: .destructive) { model.uninstallHelper() }
          } else {
            Button("Install…") { model.installHelper() }
          }
        }
        if let d = model.daemon, model.daemonAlive {
          Text("Applied \(Int(d.percent))% at \(Int(d.celsius)) °C (\(d.sensor)) · \(d.mode.label) · targets \(d.targets.map { String(Int($0)) }.joined(separator: ", ")) rpm")
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
    if model.daemonAlive { return "Running" }
    if model.helperLoaded { return "Loaded, waiting for first report" }
    return "Installed, not running"
  }

  private var statusColor: Color {
    if !model.helperInstalled { return .gray }
    return model.daemonAlive ? .green : .orange
  }
}
