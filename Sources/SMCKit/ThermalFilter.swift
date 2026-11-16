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

  private struct Channel {
    var value: Float?
    var lastSample: TimeInterval = 0
  }

  private var cpu = Channel()
  private var gpu = Channel()
  private var lastTime: TimeInterval?
  private var sensorCount = 0

  public init(holdSeconds: Double = 30, riseSeconds: Double = 2, fallSeconds: Double = 20) {
    self.holdSeconds = holdSeconds
    self.riseSeconds = riseSeconds
    self.fallSeconds = fallSeconds
  }

  public mutating func update(_ sample: ThermalReading, at time: TimeInterval) -> ThermalReading {
    let dt = lastTime.map { max(time - $0, 0) } ?? 0
    lastTime = time
    cpu = step(cpu, sample.cpu, at: time, dt: dt)
    gpu = step(gpu, sample.gpu, at: time, dt: dt)
    if sample.sensorCount > 0 { sensorCount = sample.sensorCount }
    return ThermalReading(cpu: cpu.value, gpu: gpu.value, sensorCount: sensorCount)
  }

  private func step(_ channel: Channel, _ sample: Float?, at time: TimeInterval, dt: TimeInterval) -> Channel {
    var c = channel
    guard let sample else {
      if time - c.lastSample > holdSeconds { c.value = nil }
      return c
    }
    c.lastSample = time
    if let current = c.value {
      let tau = sample > current ? riseSeconds : fallSeconds
      c.value = current + Float(1 - exp(-dt / tau)) * (sample - current)
    } else {
      c.value = sample
    }
    return c
  }
}
