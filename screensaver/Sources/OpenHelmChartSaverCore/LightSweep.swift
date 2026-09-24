import Foundation

public struct LightBeamState: Equatable, Sendable {
    public let bearingDegrees: Double
    public let sector: LightSector?

    public init(bearingDegrees: Double, sector: LightSector?) {
        self.bearingDegrees = bearingDegrees
        self.sector = sector
    }
}

public struct LightSweep: Equatable, Sendable {
    public let period: Double
    public let pulses: [Pulse]
    public let sectors: [LightSector]

    public init(period: Double, pulses: [Pulse], sectors: [LightSector]) {
        self.period = period
        self.pulses = pulses
        self.sectors = sectors
    }

    public init(light: LightSpec) {
        self.init(period: light.periodSeconds, pulses: light.pulses, sectors: light.sectors)
    }

    public func beams(at uptime: TimeInterval) -> [LightBeamState] {
        guard uptime.isFinite, period.isFinite, period > 0, let first = pulses.first else {
            return []
        }
        let referenceCenter = (first.start + first.end) / 2
        var elapsed = (uptime - referenceCenter).truncatingRemainder(dividingBy: period)
        if elapsed < 0 { elapsed += period }
        let baseBearing = elapsed / period * 360

        return pulses.map { pulse in
            let center = (pulse.start + pulse.end) / 2
            let offset = (center - referenceCenter) / period * 360
            var bearing = (baseBearing - offset).truncatingRemainder(dividingBy: 360)
            if bearing < 0 { bearing += 360 }
            let sector = sectors.first {
                bearing >= $0.startBearing && bearing < $0.endBearing
            }
            return LightBeamState(bearingDegrees: bearing, sector: sector)
        }
    }
}

public enum ChartProjection {
    private static let webMercatorCircumferenceMetres = 2 * Double.pi * 6_378_137
    private static let nauticalMileMetres = 1_852.0
    private static let mapLibreTilePoints = 512.0

    public static func logicalPoints(
        forNauticalMiles nauticalMiles: Double,
        latitudeDegrees: Double,
        zoom: Double
    ) -> Double {
        guard nauticalMiles.isFinite, nauticalMiles >= 0,
              latitudeDegrees.isFinite, zoom.isFinite else { return 0 }
        let cosine = cos(latitudeDegrees * Double.pi / 180)
        guard cosine > 0 else { return 0 }
        let worldPoints = mapLibreTilePoints * pow(2, zoom)
        return nauticalMiles * nauticalMileMetres * worldPoints /
            (webMercatorCircumferenceMetres * cosine)
    }
}
