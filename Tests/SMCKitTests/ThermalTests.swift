import XCTest
@testable import SMCKit

final class ThermalReadingTests: XCTestCase {
  private func readings(_ pairs: [(String, Float)]) -> [SensorReading] {
    pairs.map { SensorReading(key: $0.0, celsius: $0.1) }
  }

  func testAveragesOnlyValidKeys() {
    let r = ThermalReading(readings: readings([
      ("Tp01", 50), ("Tp02", 60), ("Tp03", 40), ("Tp04", 5.2), ("Tp05", 130),
      ("Tg01", 45), ("Tg02", 47),
    ]))
    XCTAssertEqual(r.cpu, 55)
    XCTAssertEqual(r.gpu, 46)
    XCTAssertEqual(r.sensorCount, 4)
  }

  func testSampleWithOnlyPlaceholdersHasNoCPU() {
    let r = ThermalReading(readings: readings([("Tp01", 40), ("Tp02", 5.2), ("Tg01", 45)]))
    XCTAssertNil(r.cpu)
    XCTAssertEqual(r.gpu, 45)
  }

  func testDrivingPicksTheHotterChannel() {
    let r = ThermalReading(cpu: 50, gpu: 60, sensorCount: 2)
    XCTAssertEqual(r.driving?.label, "GPU")
    XCTAssertEqual(r.driving(for: .cpu)?.celsius, 50)
  }
}

final class ThermalFilterTests: XCTestCase {
  func testFirstSamplePassesThrough() {
    var f = ThermalFilter()
    XCTAssertEqual(f.update(ThermalReading(cpu: 50, gpu: nil, sensorCount: 1), at: 0).cpu, 50)
  }

  func testHoldsLastValueThroughGapsThenDrops() {
    var f = ThermalFilter(holdSeconds: 30)
    _ = f.update(ThermalReading(cpu: 50, gpu: 45, sensorCount: 2), at: 0)
    let gap = f.update(ThermalReading(cpu: nil, gpu: 45, sensorCount: 1), at: 10)
    XCTAssertEqual(gap.cpu, 50)
    let late = f.update(ThermalReading(cpu: nil, gpu: 45, sensorCount: 1), at: 31)
    XCTAssertNil(late.cpu)
    XCTAssertEqual(late.gpu, 45)
  }

  func testRisesFastAndFallsSlowly() {
    var f = ThermalFilter(riseSeconds: 2, fallSeconds: 20)
    _ = f.update(ThermalReading(cpu: 50, gpu: nil, sensorCount: 1), at: 0)
    let up = f.update(ThermalReading(cpu: 70, gpu: nil, sensorCount: 1), at: 2)
    XCTAssertEqual(up.cpu!, 50 + 20 * Float(1 - exp(-1.0)), accuracy: 0.01)

    var g = ThermalFilter(riseSeconds: 2, fallSeconds: 20)
    _ = g.update(ThermalReading(cpu: 70, gpu: nil, sensorCount: 1), at: 0)
    let down = g.update(ThermalReading(cpu: 50, gpu: nil, sensorCount: 1), at: 2)
    XCTAssertEqual(down.cpu!, 70 - 20 * Float(1 - exp(-0.1)), accuracy: 0.01)
    XCTAssertGreaterThan(down.cpu!, 68)
  }

  func testNoiseLikeTheM4ProStaysSteady() {
    // Recorded pattern: a third of the samples carry no valid CPU key.
    var f = ThermalFilter()
    let cpu: [Float?] = [52, 54, nil, 53, 54, nil, nil, 53, 51, nil, 54, 53]
    var values: [Float] = []
    for (i, c) in cpu.enumerated() {
      values.append(f.update(ThermalReading(cpu: c, gpu: 46, sensorCount: 1), at: Double(i * 2)).cpu!)
    }
    XCTAssertLessThan(values.max()! - values.min()!, 3)
  }
}

final class FanConfigTests: XCTestCase {
  func testInterpolatesAndClampsToTheEnds() {
    let c = FanConfig(points: [CurvePoint(celsius: 40, percent: 20), CurvePoint(celsius: 80, percent: 100)])
    XCTAssertEqual(c.percent(at: 30), 20)
    XCTAssertEqual(c.percent(at: 60), 60)
    XCTAssertEqual(c.percent(at: 90), 100)
  }

  func testClampsOutOfRangePoints() {
    let c = FanConfig(points: [CurvePoint(celsius: 40, percent: -10), CurvePoint(celsius: 80, percent: 150)])
    XCTAssertEqual(c.percent(at: 30), 0)
    XCTAssertEqual(c.percent(at: 90), 100)
  }

  func testUnsortedPointsWork() {
    let c = FanConfig(points: [CurvePoint(celsius: 80, percent: 100), CurvePoint(celsius: 40, percent: 20)])
    XCTAssertEqual(c.percent(at: 60), 60)
  }

  func testOldConfigFilesDecodeWithDefaults() throws {
    let c = try JSONDecoder().decode(FanConfig.self, from: Data(#"{"mode":"curve"}"#.utf8))
    XCTAssertEqual(c.mode, .curve)
    XCTAssertEqual(c.safetyCelsius, 100)
    XCTAssertEqual(c.points, FanConfig.balanced)
  }
}
