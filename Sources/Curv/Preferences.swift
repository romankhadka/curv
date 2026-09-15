import AppKit
import Foundation
import ServiceManagement

enum Pref {
  static let showMenuBar = "showMenuBar"
  static let menuBarStyle = "menuBarStyle"
  static let showDockIcon = "showDockIcon"
  static let openWindowAtLaunch = "openWindowAtLaunch"
  static let fahrenheit = "fahrenheit"

  static func registerDefaults() {
    UserDefaults.standard.register(defaults: [
      showMenuBar: true,
      menuBarStyle: MenuBarStyle.temperature.rawValue,
      showDockIcon: true,
      openWindowAtLaunch: true,
      fahrenheit: false,
    ])
  }

  static var showsMenuBar: Bool { UserDefaults.standard.bool(forKey: showMenuBar) }
  static var showsDockIcon: Bool { UserDefaults.standard.bool(forKey: showDockIcon) }
  static var opensWindowAtLaunch: Bool { UserDefaults.standard.bool(forKey: openWindowAtLaunch) }
  static var usesFahrenheit: Bool { UserDefaults.standard.bool(forKey: fahrenheit) }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
  case icon, temperature, rpm

  var id: String { rawValue }

  var label: String {
    switch self {
    case .icon: return "Icon only"
    case .temperature: return "Icon and temperature"
    case .rpm: return "Icon and fan speed"
    }
  }
}

enum LaunchAtLogin {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ enabled: Bool) throws {
    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
  }
}

enum Temperature {
  static func format(_ celsius: Float?, fahrenheit: Bool = Pref.usesFahrenheit, unit: Bool = true) -> String {
    guard let c = celsius else { return "–" }
    let value = fahrenheit ? c * 9 / 5 + 32 : c
    let suffix = unit ? (fahrenheit ? " °F" : " °C") : "°"
    return "\(Int(value.rounded()))\(suffix)"
  }

  static func format(_ celsius: Double, fahrenheit: Bool = Pref.usesFahrenheit, unit: Bool = true) -> String {
    format(Float(celsius), fahrenheit: fahrenheit, unit: unit)
  }
}

/// Checks the latest GitHub release against the running bundle version.
@MainActor
final class Updater: ObservableObject {
  enum State: Equatable {
    case idle, checking, upToDate, available(String, URL), failed(String)
  }

  @Published var state: State = .idle

  static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  private let endpoint = URL(string: "https://api.github.com/repos/romankhadka/curv/releases/latest")!

  func check() async {
    state = .checking
    do {
      var request = URLRequest(url: endpoint)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      let (data, _) = try await URLSession.shared.data(for: request)
      struct Release: Decodable { let tag_name: String; let html_url: URL }
      let release = try JSONDecoder().decode(Release.self, from: data)
      let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
      state = Self.isNewer(latest, than: Self.currentVersion) ? .available(latest, release.html_url) : .upToDate
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func checkAndPresent() async {
    await check()
    let alert = NSAlert()
    switch state {
    case .available(let version, let url):
      alert.messageText = "Curv \(version) is available"
      alert.informativeText = "You have \(Self.currentVersion). Download the new version from GitHub."
      alert.addButton(withTitle: "Open Download Page")
      alert.addButton(withTitle: "Later")
      NSApp.activate(ignoringOtherApps: true)
      if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
      return
    case .upToDate:
      alert.messageText = "Curv is up to date"
      alert.informativeText = "\(Self.currentVersion) is the latest version."
    case .failed(let message):
      alert.messageText = "Could not check for updates"
      alert.informativeText = message
    default:
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }

  static func isNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ v: String) -> [Int] { v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? [] }
    let a = parts(candidate), b = parts(current)
    for i in 0..<max(a.count, b.count) {
      let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
      if x != y { return x > y }
    }
    return false
  }
}
