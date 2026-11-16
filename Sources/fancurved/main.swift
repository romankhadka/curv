// fancurved: root daemon. Reads the app's config file, reads the hottest SMC
// sensor, and sets every fan's target RPM from the curve. Restores automatic
// control on exit.
import Foundation
import SMCKit

var configPath = FanConfig.defaultURL().path
var intervalOverride: UInt32?
var dryRun = false
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
  switch a {
  case "--config": configPath = args.popFirst() ?? configPath
  case "--interval": intervalOverride = UInt32(args.popFirst() ?? "")
  case "--dry-run": dryRun = true
  case "--sensors":
    guard let smc = try? SMC() else { exit(1) }
    for s in smc.temperatures().sorted(by: { $0.celsius > $1.celsius }) { print(s.key, String(format: "%.1f", s.celsius)) }
    let th = smc.thermal()
    print("CPU avg \(th.cpu.map { String(format: "%.1f", $0) } ?? "-")  GPU avg \(th.gpu.map { String(format: "%.1f", $0) } ?? "-")")
    exit(0)
  default:
    fputs("usage: fancurved [--config path] [--interval seconds] [--dry-run] | --sensors\n", stderr)
    exit(2)
  }
}

func log(_ message: String) {
  print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
  fflush(stdout)
}

guard let smc = try? SMC() else {
  fputs("cannot open AppleSMC\n", stderr)
  exit(1)
}
let fanCount = smc.fanCount
guard fanCount > 0 else {
  fputs("SMC reports no fans\n", stderr)
  exit(1)
}

var stopping = false
signal(SIGTERM) { _ in stopping = true }
signal(SIGINT) { _ in stopping = true }
signal(SIGHUP) { _ in stopping = true }

func restoreAuto() {
  for i in 0..<fanCount { try? smc.setFanManual(i, false) }
}

log("started: \(fanCount) fans, config \(configPath)\(dryRun ? ", dry run: no SMC or status writes" : "")")
smc.discoverSensors()

var filter = ThermalFilter()
var lastMode: FanMode?
var loggedPercent = -1.0

while !stopping {
  let config = (try? FanConfig.load(from: URL(fileURLWithPath: configPath))) ?? FanConfig()
  let thermal = filter.update(smc.thermal(), at: Date().timeIntervalSince1970)
  let hot = thermal.driving(for: config.sensor)
  let temp = Double(hot?.celsius ?? 0)

  // percent < 0 means "hand control back to macOS".
  var percent: Double
  switch config.mode {
  case .auto: percent = -1
  case .max: percent = 100
  case .curve: percent = hot == nil ? -1 : Swift.min(Swift.max(config.percent(at: temp), 0), 100)
  }
  if config.mode != .auto, temp >= config.safetyCelsius { percent = 100 }

  var targets: [Double] = []
  if percent < 0 {
    if lastMode != .auto {
      if !dryRun { restoreAuto() }
      log("automatic control")
    }
  } else {
    for i in 0..<fanCount {
      guard let fan = smc.fan(i) else { continue }
      let rpm = (fan.min + Float(percent / 100) * (fan.max - fan.min)).rounded()
      targets.append(Double(rpm))
      if dryRun { continue }
      // Write only on change, so an unchanged curve costs no SMC writes.
      // The read-back also catches macOS taking the fan back.
      do {
        if !fan.manual { try smc.setFanManual(i, true) }
        if !fan.manual || abs(fan.target - rpm) >= 1 { try smc.setFanTarget(i, rpm: rpm) }
      } catch {
        log("fan \(i): \(error.localizedDescription)")
      }
    }
    // Log steps of 5% or more, so slow decays do not log every tick.
    if lastMode != config.mode || abs(percent - loggedPercent) >= 5 {
      log("\(config.mode.rawValue): \(Int(percent))% at \(Int(temp))°C (\(hot?.label ?? "-")) -> \(targets.map { Int($0) })")
      loggedPercent = percent
    }
  }
  lastMode = percent < 0 ? .auto : config.mode
  if percent < 0 { loggedPercent = -1 }

  let status = DaemonStatus(
    updatedAt: Date().timeIntervalSince1970, mode: percent < 0 ? .auto : config.mode,
    celsius: temp, sensor: hot?.label ?? "", percent: Swift.max(percent, 0), targets: targets
  )
  if !dryRun { try? status.save() }
  sleep(intervalOverride ?? UInt32(min(max(config.intervalSeconds, 1), 10)))
}

if !dryRun { restoreAuto() }
log("stopped, fans automatic")
