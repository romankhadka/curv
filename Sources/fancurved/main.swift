// fancurved: root daemon. Reads the app's config file, reads the hottest SMC
// sensor, and sets every fan's target RPM from the curve. Restores automatic
// control on exit.
import Foundation
import SMCKit

var configPath = FanConfig.defaultURL().path
var interval: UInt32 = 2
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
  switch a {
  case "--config": configPath = args.popFirst() ?? configPath
  case "--interval": interval = UInt32(args.popFirst() ?? "") ?? interval
  case "--sensors":
    guard let smc = try? SMC() else { exit(1) }
    for s in smc.temperatures().sorted(by: { $0.celsius > $1.celsius }) { print(s.key, String(format: "%.1f", s.celsius)) }
    let th = smc.thermal()
    print("CPU avg \(th.cpu.map { String(format: "%.1f", $0) } ?? "-")  GPU avg \(th.gpu.map { String(format: "%.1f", $0) } ?? "-")")
    exit(0)
  default:
    fputs("usage: fancurved [--config path] [--interval seconds]\n", stderr)
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

log("started: \(fanCount) fans, config \(configPath), interval \(interval)s")
smc.discoverSensors()

var lastMode: FanMode?
var lastPercent = -1.0

while !stopping {
  let config = (try? FanConfig.load(from: URL(fileURLWithPath: configPath))) ?? FanConfig()
  let hot = smc.thermal().driving
  let temp = Double(hot?.celsius ?? 0)

  // percent < 0 means "hand control back to macOS".
  var percent: Double
  switch config.mode {
  case .auto: percent = -1
  case .max: percent = 100
  case .curve: percent = hot == nil ? -1 : config.percent(at: temp)
  }
  if config.mode != .auto, temp >= config.safetyCelsius { percent = 100 }

  var targets: [Double] = []
  if percent < 0 {
    if lastMode != .auto {
      restoreAuto()
      log("automatic control")
    }
  } else {
    for i in 0..<fanCount {
      guard let fan = smc.fan(i) else { continue }
      let rpm = fan.min + Float(percent / 100) * (fan.max - fan.min)
      do {
        try smc.setFanManual(i, true)
        try smc.setFanTarget(i, rpm: rpm)
        targets.append(Double(rpm.rounded()))
      } catch {
        log("fan \(i): \(error.localizedDescription)")
      }
    }
    if abs(percent - lastPercent) >= 1 {
      log("\(config.mode.rawValue): \(Int(percent))% at \(Int(temp))°C (\(hot?.label ?? "-")) -> \(targets.map { Int($0) })")
    }
  }
  lastMode = percent < 0 ? .auto : config.mode
  lastPercent = percent

  let status = DaemonStatus(
    updatedAt: Date().timeIntervalSince1970, mode: percent < 0 ? .auto : config.mode,
    celsius: temp, sensor: hot?.label ?? "", percent: Swift.max(percent, 0), targets: targets
  )
  try? status.save()
  sleep(interval)
}

restoreAuto()
log("stopped, fans automatic")
