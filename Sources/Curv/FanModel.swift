import Foundation
import SMCKit

enum HelperState {
  case notInstalled, needsApproval, notLoaded, loaded, running
}

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
  @Published var helperNeedsApproval = false
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
    helperNeedsApproval = helperInstalled && !helperLoaded && Helper.needsApproval()
  }

  var helperState: HelperState {
    if !helperInstalled { return .notInstalled }
    if daemonAlive { return .running }
    if helperLoaded { return .loaded }
    return helperNeedsApproval ? .needsApproval : .notLoaded
  }

  /// Short status for the window, the menu bar menu and Settings.
  var helperStatus: String {
    let base: String
    switch helperState {
    case .notInstalled: return "Not installed. Fans stay under macOS control."
    case .needsApproval: base = "Blocked by macOS"
    case .notLoaded: base = "Installed, not running"
    case .loaded: base = "Loaded, waiting for first report"
    case .running: base = "Running"
    }
    return helperOutdated ? "\(base) · this app has a newer helper" : base
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

  static let approvalHint =
    "macOS blocks the helper. In Login Items & Extensions, turn on \"Allow in the Background\" for com.romn.fancurved, then click Restart."

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
    if Helper.needsApproval() {
      Helper.openLoginItems()
      refreshHelper()
      return
    }
    do {
      try Helper.restart()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    refreshHelper()
  }
}
