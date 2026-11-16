import Foundation
import ServiceManagement

/// Installs `fancurved` as a LaunchDaemon. Every privileged step runs through
/// one `osascript ... with administrator privileges` call, so macOS shows a
/// single password prompt.
enum Helper {
  static let label = "com.romn.fancurved"
  static let binary = "/Library/PrivilegedHelperTools/com.romn.fancurved"
  static let plist = "/Library/LaunchDaemons/\(label).plist"
  static let logPath = "/tmp/fancurved.log"

  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static var bundledDaemon: URL? {
    if let url = Bundle.main.url(forResource: "fancurved", withExtension: nil) { return url }
    guard let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("fancurved"),
          FileManager.default.isExecutableFile(atPath: sibling.path) else { return nil }
    return sibling
  }

  static func isInstalled() -> Bool { FileManager.default.fileExists(atPath: plist) }

  static func isLoaded() -> Bool { run("/bin/launchctl", ["print", "system/\(label)"]).status == 0 }

  /// True when the "Allow in the Background" switch for the daemon is off in
  /// System Settings > General > Login Items & Extensions. launchd then does
  /// not load the daemon at boot.
  static func needsApproval() -> Bool {
    SMAppService.statusForLegacyPlist(at: URL(fileURLWithPath: plist)) == .requiresApproval
  }

  static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

  /// Size and modification date of the installed daemon: changes on every
  /// install. nil when it is missing.
  static func installedStamp() -> String? {
    guard let a = try? FileManager.default.attributesOfItem(atPath: binary),
          let size = a[.size] as? Int, let date = a[.modificationDate] as? Date else { return nil }
    return "\(size)-\(date.timeIntervalSince1970)"
  }

  /// nil when nothing is installed or the bundled daemon cannot be read.
  static func installedMatchesBundle() -> Bool? {
    guard isInstalled(), let source = bundledDaemon,
          let bundled = try? Data(contentsOf: source),
          let installed = FileManager.default.contents(atPath: binary) else { return nil }
    return bundled == installed
  }

  static func install(configPath: String) throws {
    guard let source = bundledDaemon else {
      throw Failure(message: "fancurved binary not found in the app bundle. Build with build.sh.")
    }
    let plistXML = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key><string>\(label)</string>
        <key>ProgramArguments</key>
        <array>
          <string>\(binary)</string>
          <string>--config</string>
          <string>\(xml(configPath))</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        <key>StandardOutPath</key><string>\(logPath)</string>
        <key>StandardErrorPath</key><string>\(logPath)</string>
      </dict>
      </plist>
      """
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("\(label).plist")
    try plistXML.write(to: staged, atomically: true, encoding: .utf8)

    let script = [
      "mkdir -p /Library/PrivilegedHelperTools",
      "launchctl bootout system/\(label) 2>/dev/null || true",
      "cp \(q(source.path)) \(q(binary))",
      "chown root:wheel \(q(binary))",
      "chmod 755 \(q(binary))",
      "cp \(q(staged.path)) \(q(plist))",
      "chown root:wheel \(q(plist))",
      "chmod 644 \(q(plist))",
      "launchctl bootstrap system \(q(plist))",
    ].joined(separator: " && ")
    try runPrivileged(script)
  }

  static func uninstall() throws {
    try runPrivileged("launchctl bootout system/\(label) 2>/dev/null || true; rm -f \(q(plist)) \(q(binary))")
  }

  /// kickstart needs a loaded service. After a reboot with the daemon
  /// disallowed, or after a manual bootout, load it instead.
  static func restart() throws {
    try runPrivileged(isLoaded() ? "launchctl kickstart -k system/\(label)" : "launchctl bootstrap system \(q(plist))")
  }

  // MARK: Plumbing

  private static func q(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func xml(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private static func runPrivileged(_ shell: String) throws {
    let escaped = shell
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let result = run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    guard result.status == 0 else {
      throw Failure(message: result.output.isEmpty ? "Cancelled" : result.output)
    }
  }

  private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
