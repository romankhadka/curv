import Foundation

/// Turns raw `ThermalReading` samples into a steady signal for the curve.
///
/// - A channel with no valid sample keeps its last value for `holdSeconds`,
///   then goes to nil.
/// - Rises follow quickly (`riseSeconds` time constant) so the fans react to
///   load. Falls follow slowly (`fallSeconds`) so short idle gaps between
///   bursts do not make the fans hunt.
public struct ThermalFilter {
  public var holdSeconds: Double
  public var riseSeconds: Double
  public var fallSeconds: Double

  private var cpu = Channel()
  private var gpu = Channel()
  private var sensorCount = 0

  public init(holdSeconds: Double = 30, riseSeconds: Double = 2, fallSeconds: Double = 20) {
    self.holdSeconds = holdSeconds
    self.riseSeconds = riseSeconds
    self.fallSeconds = fallSeconds
  }

  public mutating func update(_ sample: ThermalReading, at time: TimeInterval) -> ThermalReading {
    cpu.update(sample.cpu, at: time, self)
    gpu.update(sample.gpu, at: time, self)
    if sample.sensorCount > 0 { sensorCount = sample.sensorCount }
    return ThermalReading(cpu: cpu.value, gpu: gpu.value, sensorCount: sensorCount)
  }

  private struct Channel {
    var value: Float?
    var lastSample: TimeInterval = 0
    var lastUpdate: TimeInterval = 0

    mutating func update(_ sample: Float?, at time: TimeInterval, _ filter: ThermalFilter) {
      defer { lastUpdate = time }
      guard let sample else {
        if time - lastSample > filter.holdSeconds { value = nil }
        return
      }
      lastSample = time
      guard let current = value else {
        value = sample
        return
      }
      let tau = sample > current ? filter.riseSeconds : filter.fallSeconds
      let alpha = Float(1 - exp(-max(time - lastUpdate, 0) / tau))
      value = current + alpha * (sample - current)
    }
  }
}
