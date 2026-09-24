import Testing
@testable import OpenHelmChartSaverCore

// Deliberately synthetic timing and geometry, not a navigational light record.
@Suite("Rotating lighthouse sweep")
struct LightSweepTests {
    private let pulses = [Pulse(start: 0, end: 1), Pulse(start: 2, end: 3)]
    private let sectors = [
        LightSector(startBearing: 90, endBearing: 120, colour: .green, rangeNauticalMiles: 10),
        LightSector(startBearing: 120, endBearing: 240, colour: .white, rangeNauticalMiles: 20),
        LightSector(startBearing: 240, endBearing: 270, colour: .red, rangeNauticalMiles: 5),
    ]
    @Test func pairedBladesKeepTheirPhaseAndRepeatWithoutDrift() {
        let sweep = LightSweep(period: 10, pulses: pulses, sectors: sectors)
        let first = sweep.beams(at: 0.5)
        #expect(first.count == 2)
        #expect(abs(first[0].bearingDegrees) < 0.000_001)
        #expect(abs(first[1].bearingDegrees - 288) < 0.000_001)
        let second = sweep.beams(at: 2.5)
        #expect(abs(second[0].bearingDegrees - 72) < 0.000_001)
        #expect(abs(second[1].bearingDegrees) < 0.000_001)
        let repeated = sweep.beams(at: 600_000.5)
        #expect(abs(repeated[0].bearingDegrees - first[0].bearingDegrees) < 0.000_001)
        #expect(abs(repeated[1].bearingDegrees - first[1].bearingDegrees) < 0.000_001)
    }
    @Test func beamsUseTheirCurrentSectorAndVanishOutsideCoverage() {
        let sweep = LightSweep(period: 10, pulses: pulses, sectors: sectors)
        let dark = sweep.beams(at: 0.5)
        #expect(dark.allSatisfy { $0.sector == nil })
        let green = sweep.beams(at: 3)
        #expect(abs(green[0].bearingDegrees - 90) < 0.000_001)
        #expect(green[0].sector?.colour == .green)
        #expect(green[0].sector?.rangeNauticalMiles == 10)
        #expect(green[1].sector == nil)
        let white = sweep.beams(at: 5)
        #expect(abs(white[0].bearingDegrees - 162) < 0.000_001)
        #expect(white[0].sector?.colour == .white)
        #expect(white[0].sector?.rangeNauticalMiles == 20)
    }
    @Test func chartProjectionUsesLiteralWebMercatorScale() {
        let equator = ChartProjection.logicalPoints(forNauticalMiles: 1, latitudeDegrees: 0, zoom: 0)
        #expect(abs(equator - 0.023_661_225_332_470_81) < 0.000_000_000_001)
        let highLatitude = ChartProjection.logicalPoints(forNauticalMiles: 1, latitudeDegrees: 60, zoom: 0)
        #expect(abs(highLatitude - 2 * equator) < 0.000_000_000_001)
        let zoomed = ChartProjection.logicalPoints(forNauticalMiles: 2, latitudeDegrees: 0, zoom: 1)
        #expect(abs(zoomed - 4 * equator) < 0.000_000_000_001)
    }
}
