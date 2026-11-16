import CSMC
import Foundation

public enum SMCError: Error, LocalizedError {
  case openFailed
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case .openFailed: return "Cannot open AppleSMC"
    case .writeFailed(let key): return "SMC write to \(key) failed (root required)"
    }
  }
}

public struct FanReading: Identifiable, Equatable {
  public let id: Int
  public let actual: Float
  public let target: Float
  public let min: Float
  public let max: Float
  public let manual: Bool
}

public struct SensorReading: Identifiable, Equatable {
  public var id: String { key }
  public let key: String
  public let celsius: Float

  public init(key: String, celsius: Float) {
    self.key = key
    self.celsius = celsius
  }
}

/// Apple Silicon SMC fan and temperature access.
/// Fan keys: FNum, F<n>Ac (actual), F<n>Tg (target), F<n>Mn/Mx (limits), F<n>Md (0 auto, 1 manual).
public final class SMC {
  private var sensorKeys: [String] = []
  /// The CPU-die (Tp*) and GPU (Tg*) keys: the only ones `thermal()` reads.
  private var thermalKeys: [String] = []

  public init() throws {
    guard smc_open() == 0 else { throw SMCError.openFailed }
  }

  deinit { smc_close() }

  public func readFloat(_ key: String) -> Float? {
    var v: Float = 0
    return smc_read_float(key, &v) == 0 ? v : nil
  }

  public func readU8(_ key: String) -> UInt8? {
    var v: UInt8 = 0
    return smc_read_u8(key, &v) == 0 ? v : nil
  }

  public func writeFloat(_ key: String, _ value: Float) throws {
    guard smc_write_float(key, value) == 0 else { throw SMCError.writeFailed(key) }
  }

  public func writeU8(_ key: String, _ value: UInt8) throws {
    guard smc_write_u8(key, value) == 0 else { throw SMCError.writeFailed(key) }
  }

  // MARK: Fans

  public var fanCount: Int { Int(readU8("FNum") ?? 0) }

  public func fans() -> [FanReading] { (0..<fanCount).compactMap(fan) }

  public func fan(_ i: Int) -> FanReading? {
    guard let actual = readFloat("F\(i)Ac"),
          let min = readFloat("F\(i)Mn"),
          let max = readFloat("F\(i)Mx") else { return nil }
    return FanReading(
      id: i, actual: actual, target: readFloat("F\(i)Tg") ?? 0,
      min: min, max: max, manual: readU8("F\(i)Md") == 1
    )
  }

  public func setFanManual(_ i: Int, _ manual: Bool) throws {
    try writeU8("F\(i)Md", manual ? 1 : 0)
  }

  public func setFanTarget(_ i: Int, rpm: Float) throws {
    try writeFloat("F\(i)Tg", rpm)
  }

  // MARK: Keys and sensors

  public func allKeys() -> [String] {
    var count: UInt32 = 0
    guard smc_key_count(&count) == 0 else { return [] }
    var keys: [String] = []
    keys.reserveCapacity(Int(count))
    var buf = [CChar](repeating: 0, count: 5)
    for i in 0..<count where smc_key_at_index(i, &buf) == 0 {
      keys.append(buf.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
    }
    return keys
  }

  public func keyType(_ key: String) -> String? {
    var size: UInt32 = 0
    var type = [CChar](repeating: 0, count: 5)
    guard smc_key_info(key, &size, &type) == 0 else { return nil }
    return type.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
  }

  /// Every float-typed key starting with "T" is treated as a temperature
  /// sensor. Discovery checks the type, so later reads skip the key-info call.
  public func discoverSensors() {
    sensorKeys = allKeys().filter { $0.hasPrefix("T") && keyType($0) == "flt " }
    thermalKeys = sensorKeys.filter { $0.hasPrefix("Tp") || $0.hasPrefix("Tg") }
  }

  /// Every temperature key, for listing. The curve needs only `thermal()`.
  public func temperatures() -> [SensorReading] {
    if sensorKeys.isEmpty { discoverSensors() }
    return read(sensorKeys).filter { $0.celsius > 5 && $0.celsius < 120 }
  }

  /// One raw CPU and GPU sample. A quarter of the keys is enough for the
  /// curve, so this reads far fewer keys than `temperatures()`.
  public func thermal() -> ThermalReading {
    if sensorKeys.isEmpty { discoverSensors() }
    return ThermalReading(readings: read(thermalKeys))
  }

  private func read(_ keys: [String]) -> [SensorReading] {
    keys.compactMap { key in
      var v: Float = 0
      return smc_read_float_known(key, &v) == 0 ? SensorReading(key: key, celsius: v) : nil
    }
  }
}

public struct ThermalReading: Equatable {
  public let cpu: Float?
  public let gpu: Float?
  public let sensorCount: Int

  public init(cpu: Float?, gpu: Float?, sensorCount: Int) {
    self.cpu = cpu
    self.gpu = gpu
    self.sensorCount = sensorCount
  }

  /// CPU-die average (Tp* keys) and GPU average (Tg* keys). Single core keys
  /// spike well above the package temperature, so averages drive the curve.
  ///
  /// On Apple Silicon, power-gated cores report exactly 40.0 °C, and in some
  /// samples every Tp key reads 40.0 or about 5 °C. An average over those
  /// values swings by tens of degrees from one second to the next, so they
  /// are dropped. A sample with no valid key gives nil; `ThermalFilter` then
  /// holds the last value.
  public init(readings: [SensorReading]) {
    let valid = readings.filter { Self.isValid($0.celsius) }
    func average(prefix: String) -> Float? {
      let values = valid.filter { $0.key.hasPrefix(prefix) }.map(\.celsius)
      return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }
    self.init(cpu: average(prefix: "Tp"), gpu: average(prefix: "Tg"), sensorCount: valid.count)
  }

  static let placeholderCelsius: Float = 40

  static func isValid(_ celsius: Float) -> Bool {
    celsius >= 20 && celsius < 115 && celsius != placeholderCelsius
  }

  public func driving(for source: SensorSource) -> (label: String, celsius: Float)? {
    switch source {
    case .auto: return driving
    case .cpu: return cpu.map { ("CPU", $0) }
    case .gpu: return gpu.map { ("GPU", $0) }
    }
  }

  /// The reading that drives the curve: the hotter of CPU and GPU.
  public var driving: (label: String, celsius: Float)? {
    switch (cpu, gpu) {
    case let (c?, g?): return c >= g ? ("CPU", c) : ("GPU", g)
    case let (c?, nil): return ("CPU", c)
    case let (nil, g?): return ("GPU", g)
    default: return nil
    }
  }
}
