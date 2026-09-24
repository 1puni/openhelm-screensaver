import Foundation

private let maximumJavaScriptSafeInteger = 9_007_199_254_740_991

public struct GeoCoordinate: Codable, Equatable, Sendable {
    public let longitude: Double
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        longitude = try values.decode(Double.self)
        latitude = try values.decode(Double.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: values,
                debugDescription: "coordinate must have two values"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(longitude)
        try values.encode(latitude)
    }
}

public struct ChartSpec: Codable, Equatable, Sendable {
    public let center: GeoCoordinate
    public let zoom: Double
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let deviceScaleFactor: Int
    public let asset: String
    public let lightVisibilityAsset: String

    public var physicalWidth: Int {
        let (width, overflow) = logicalWidth.multipliedReportingOverflow(by: deviceScaleFactor)
        precondition(!overflow, "chart physical width overflow")
        precondition(
            width > 0 && width <= maximumJavaScriptSafeInteger,
            "chart physical width exceeds JavaScript safe integer range"
        )
        return width
    }

    public var physicalHeight: Int {
        let (height, overflow) = logicalHeight.multipliedReportingOverflow(by: deviceScaleFactor)
        precondition(!overflow, "chart physical height overflow")
        precondition(
            height > 0 && height <= maximumJavaScriptSafeInteger,
            "chart physical height exceeds JavaScript safe integer range"
        )
        return height
    }

    public init(
        center: GeoCoordinate,
        zoom: Double,
        logicalWidth: Int,
        logicalHeight: Int,
        deviceScaleFactor: Int,
        asset: String,
        lightVisibilityAsset: String
    ) {
        self.center = center
        self.zoom = zoom
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.deviceScaleFactor = deviceScaleFactor
        self.asset = asset
        self.lightVisibilityAsset = lightVisibilityAsset
    }
}

public struct UnitAnchor: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Pulse: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public enum LightColour: String, Codable, Equatable, Sendable {
    case white
    case red
    case green
}

public struct LightSector: Codable, Equatable, Sendable {
    public let startBearing: Double
    public let endBearing: Double
    public let colour: LightColour
    public let rangeNauticalMiles: Double

    public init(
        startBearing: Double,
        endBearing: Double,
        colour: LightColour,
        rangeNauticalMiles: Double
    ) {
        self.startBearing = startBearing
        self.endBearing = endBearing
        self.colour = colour
        self.rangeNauticalMiles = rangeNauticalMiles
    }
}

public struct LightSpec: Codable, Equatable, Sendable {
    public let name: String
    public let coordinate: GeoCoordinate
    public let character: String
    public let periodSeconds: Double
    public let pulses: [Pulse]
    public let anchor: UnitAnchor
    public let sectors: [LightSector]

    public init(
        name: String,
        coordinate: GeoCoordinate,
        character: String,
        periodSeconds: Double,
        pulses: [Pulse],
        anchor: UnitAnchor,
        sectors: [LightSector] = []
    ) {
        self.name = name
        self.coordinate = coordinate
        self.character = character
        self.periodSeconds = periodSeconds
        self.pulses = pulses
        self.anchor = anchor
        self.sectors = sectors
    }
}

public enum SceneValidationError: Error, Equatable, Sendable {
    case invalid(String)
}

public struct SaverScene: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let chart: ChartSpec
    public let light: LightSpec

    public init(id: String, title: String, chart: ChartSpec, light: LightSpec) {
        self.id = id
        self.title = title
        self.chart = chart
        self.light = light
    }

    public static func decode(_ data: Data) throws -> SaverScene {
        try JSONDecoder().decode(SaverScene.self, from: data).validated()
    }

    @discardableResult
    public func validated() throws -> SaverScene {
        func require(_ condition: @autoclosure () -> Bool, _ field: String) throws {
            if !condition() {
                throw SceneValidationError.invalid(field)
            }
        }

        try require(
            !id.isEmpty && id.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil,
            "id"
        )
        try require(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "title")
        try require(chart.center.longitude.isFinite && (-180...180).contains(chart.center.longitude), "chart.center[0]")
        try require(chart.center.latitude.isFinite && (-90...90).contains(chart.center.latitude), "chart.center[1]")
        try require(chart.zoom.isFinite, "chart.zoom")
        try require(
            chart.logicalWidth > 0 && chart.logicalWidth <= maximumJavaScriptSafeInteger &&
                chart.logicalHeight > 0 && chart.logicalHeight <= maximumJavaScriptSafeInteger &&
                chart.deviceScaleFactor > 0 && chart.deviceScaleFactor <= maximumJavaScriptSafeInteger,
            "chart.dimensions"
        )
        let (physicalWidth, widthOverflow) = chart.logicalWidth.multipliedReportingOverflow(by: chart.deviceScaleFactor)
        let (physicalHeight, heightOverflow) = chart.logicalHeight.multipliedReportingOverflow(by: chart.deviceScaleFactor)
        try require(
            !widthOverflow && !heightOverflow &&
                physicalWidth <= maximumJavaScriptSafeInteger && physicalHeight <= maximumJavaScriptSafeInteger,
            "chart.dimensions"
        )
        try require(
            chart.asset.range(of: #"^[A-Za-z0-9.@_-]+\.png$"#, options: .regularExpression) != nil,
            "chart.asset"
        )
        try require(
            chart.lightVisibilityAsset != chart.asset &&
                chart.lightVisibilityAsset.range(
                    of: #"^[A-Za-z0-9.@_-]+\.png$"#,
                    options: .regularExpression
                ) != nil,
            "chart.lightVisibilityAsset"
        )
        try require(
            light.coordinate.longitude.isFinite && (-180...180).contains(light.coordinate.longitude),
            "light.coordinate[0]"
        )
        try require(
            light.coordinate.latitude.isFinite && (-90...90).contains(light.coordinate.latitude),
            "light.coordinate[1]"
        )
        try require(!light.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "light.name")
        try require(!light.character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "light.character")
        try require(light.periodSeconds.isFinite && light.periodSeconds > 0, "light.periodSeconds")
        try require(light.anchor.x.isFinite && (0...1).contains(light.anchor.x), "light.anchor.x")
        try require(light.anchor.y.isFinite && (0...1).contains(light.anchor.y), "light.anchor.y")
        try require(!light.pulses.isEmpty, "light.pulses")

        var priorEnd = -Double.infinity
        var hasDarkGap = (light.pulses.first?.start ?? 0) > 0
        for pulse in light.pulses {
            try require(pulse.start.isFinite && pulse.end.isFinite, "light.pulses")
            try require(
                pulse.start >= 0 && pulse.end > pulse.start && pulse.end <= light.periodSeconds,
                "light.pulses"
            )
            try require(pulse.start >= priorEnd, "light.pulses")
            if priorEnd >= 0 && pulse.start > priorEnd {
                hasDarkGap = true
            }
            priorEnd = pulse.end
        }
        if priorEnd < light.periodSeconds {
            hasDarkGap = true
        }
        try require(hasDarkGap, "light.pulses")

        try require(!light.sectors.isEmpty, "light.sectors")
        var priorSectorEnd = -Double.infinity
        for sector in light.sectors {
            try require(
                sector.startBearing.isFinite && sector.endBearing.isFinite &&
                    sector.rangeNauticalMiles.isFinite,
                "light.sectors"
            )
            try require(
                sector.startBearing >= 0 && sector.startBearing < 360 &&
                    sector.endBearing > sector.startBearing && sector.endBearing <= 360,
                "light.sectors"
            )
            try require(sector.rangeNauticalMiles > 0, "light.sectors")
            try require(sector.startBearing >= priorSectorEnd, "light.sectors")
            priorSectorEnd = sector.endBearing
        }
        return self
    }
}
