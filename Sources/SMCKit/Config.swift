import Foundation

public struct CurvePoint: Codable, Equatable, Identifiable {
  public var id = UUID()
  public var celsius: Double
  public var percent: Double

  enum CodingKeys: String, CodingKey { case celsius, percent }

  public init(celsius: Double, percent: Double) {
    self.celsius = celsius
    self.percent = percent
  }
}

public enum FanMode: String, Codable, CaseIterable, Identifiable {
  case auto, curve, max

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .auto: return "Automatic"
    case .curve: return "Custom curve"
    case .max: return "Max"
    }
  }
}

public enum SensorSource: String, Codable, CaseIterable, Identifiable {
  case auto, cpu, gpu

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .auto: return "Hotter of CPU and GPU"
    case .cpu: return "CPU only"
    case .gpu: return "GPU only"
    }
  }
}

/// Shared between the app (writer) and the daemon (reader).
public struct FanConfig: Codable, Equatable {
  public var mode: FanMode
  public var points: [CurvePoint]
  /// At or above this temperature the daemon forces 100% regardless of the curve.
  public var safetyCelsius: Double
  public var sensor: SensorSource
  /// How often the daemon re-reads the sensors and re-applies the curve.
  public var intervalSeconds: Double

  public init(
    mode: FanMode = .auto, points: [CurvePoint] = FanConfig.balanced, safetyCelsius: Double = 100,
    sensor: SensorSource = .auto, intervalSeconds: Double = 2
  ) {
    self.mode = mode
    self.points = points
    self.safetyCelsius = safetyCelsius
    self.sensor = sensor
    self.intervalSeconds = intervalSeconds
  }

  enum CodingKeys: String, CodingKey { case mode, points, safetyCelsius, sensor, intervalSeconds }

  /// Every key is optional on read so older config files keep working.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    mode = try c.decodeIfPresent(FanMode.self, forKey: .mode) ?? .auto
    points = try c.decodeIfPresent([CurvePoint].self, forKey: .points) ?? FanConfig.balanced
    safetyCelsius = try c.decodeIfPresent(Double.self, forKey: .safetyCelsius) ?? 100
    sensor = try c.decodeIfPresent(SensorSource.self, forKey: .sensor) ?? .auto
    intervalSeconds = try c.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? 2
  }

  public static let quiet = [
    CurvePoint(celsius: 40, percent: 0), CurvePoint(celsius: 60, percent: 20),
    CurvePoint(celsius: 75, percent: 45), CurvePoint(celsius: 85, percent: 70),
    CurvePoint(celsius: 95, percent: 100),
  ]
  public static let balanced = [
    CurvePoint(celsius: 35, percent: 10), CurvePoint(celsius: 55, percent: 30),
    CurvePoint(celsius: 70, percent: 55), CurvePoint(celsius: 80, percent: 80),
    CurvePoint(celsius: 90, percent: 100),
  ]
  public static let aggressive = [
    CurvePoint(celsius: 30, percent: 30), CurvePoint(celsius: 50, percent: 60),
    CurvePoint(celsius: 65, percent: 85), CurvePoint(celsius: 75, percent: 100),
  ]

  /// Linear interpolation between points, flat beyond the ends.
  public func percent(at celsius: Double) -> Double {
    let pts = points.sorted { $0.celsius < $1.celsius }
    guard let first = pts.first, let last = pts.last else { return 100 }
    if celsius <= first.celsius { return first.percent }
    if celsius >= last.celsius { return last.percent }
    for (a, b) in zip(pts, pts.dropFirst()) where celsius >= a.celsius && celsius <= b.celsius {
      let span = b.celsius - a.celsius
      if span <= 0 { return Swift.max(a.percent, b.percent) }
      return a.percent + (b.percent - a.percent) * (celsius - a.celsius) / span
    }
    return last.percent
  }

  public static func defaultURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/FanCurve/config.json")
  }

  public static func load(from url: URL) throws -> FanConfig {
    try JSONDecoder().decode(FanConfig.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}

/// Heartbeat the daemon writes every tick so the app can show what it applied.
public struct DaemonStatus: Codable {
  public static let path = "/tmp/fancurved.status.json"

  public var updatedAt: TimeInterval
  public var mode: FanMode
  public var celsius: Double
  public var sensor: String
  public var percent: Double
  public var targets: [Double]

  public init(updatedAt: TimeInterval, mode: FanMode, celsius: Double, sensor: String, percent: Double, targets: [Double]) {
    self.updatedAt = updatedAt
    self.mode = mode
    self.celsius = celsius
    self.sensor = sensor
    self.percent = percent
    self.targets = targets
  }

  public var isFresh: Bool { Date().timeIntervalSince1970 - updatedAt < 10 }

  public static func load() -> DaemonStatus? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(DaemonStatus.self, from: data)
  }

  public func save() throws {
    try JSONEncoder().encode(self).write(to: URL(fileURLWithPath: Self.path), options: .atomic)
  }
}
