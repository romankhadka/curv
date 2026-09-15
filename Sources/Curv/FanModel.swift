import Foundation
import SMCKit

@MainActor
final class FanModel: ObservableObject {
  @Published var config: FanConfig {
    didSet { if config != oldValue { scheduleSave() } }
  }
  @Published var fans: [FanReading] = []
  @Published var thermal: ThermalReading?
  @Published var helperInstalled = false
  @Published var helperLoaded = false
  @Published var helperOutdated = false
  @Published var daemon: DaemonStatus?
  @Published var lastError: String?
  @Published var smcAvailable = true

  let configURL = FanConfig.defaultURL()
  let updater = Updater()
  private var smc: SMC?
  private var timer: Timer?
  private var saveTask: Task<Void, Never>?
  private var tick = 0

  init() {
    config = (try? FanConfig.load(from: configURL)) ?? FanConfig()
    smc = try? SMC()
    smcAvailable = smc != nil
    smc?.discoverSensors()
    refresh()
    refreshHelper()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  var daemonAlive: Bool { daemon?.isFresh ?? false }

  func refresh() {
    guard let smc else { return }
    fans = smc.fans()
    thermal = smc.thermal()
    daemon = DaemonStatus.load()
    tick += 1
    if tick % 5 == 0 { refreshHelper() }
  }

  func refreshHelper() {
    helperInstalled = Helper.isInstalled()
    helperLoaded = helperInstalled && Helper.isLoaded()
    helperOutdated = Helper.installedMatchesBundle() == false
  }

  var helperSummary: String {
    if !helperInstalled { return "Helper not installed" }
    if helperOutdated { return daemonAlive ? "Helper running, update available" : "Helper installed, update available" }
    if daemonAlive { return "Helper running" }
    if helperLoaded { return "Helper loaded, waiting for first report" }
    return "Helper installed, not running"
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      do {
        try config.save(to: configURL)
        lastError = nil
      } catch {
        lastError = "Cannot save config: \(error.localizedDescription)"
      }
    }
  }

  // MARK: Curve edits

  func applyPreset(_ points: [CurvePoint]) { config.points = points }

  func sortPoints() { config.points.sort { $0.celsius < $1.celsius } }

  func addPoint() {
    var pts = config.points.sorted { $0.celsius < $1.celsius }
    guard pts.count >= 2 else {
      pts.append(CurvePoint(celsius: 70, percent: 50))
      config.points = pts
      return
    }
    var best = (index: 0, gap: -1.0)
    for i in 0..<(pts.count - 1) {
      let gap = pts[i + 1].celsius - pts[i].celsius
      if gap > best.gap { best = (i, gap) }
    }
    let a = pts[best.index], b = pts[best.index + 1]
    pts.insert(
      CurvePoint(celsius: ((a.celsius + b.celsius) / 2).rounded(), percent: ((a.percent + b.percent) / 2).rounded()),
      at: best.index + 1
    )
    config.points = pts
  }

  func removePoint(_ id: UUID) {
    guard config.points.count > 2 else { return }
    config.points.removeAll { $0.id == id }
  }

  // MARK: Helper

  func installHelper() {
    do {
      try config.save(to: configURL)
      try Helper.install(configPath: configURL.path)
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    refreshHelper()
  }

  func uninstallHelper() {
    do {
      try Helper.uninstall()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    refreshHelper()
  }

  func restartHelper() {
    do {
      try Helper.restart()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    refreshHelper()
  }
}
