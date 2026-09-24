// Synthetic geometry below is not derived from a navigation dataset.
import Foundation
import Testing
@testable import OpenHelmChartSaverCore

@Suite("Saver scene")
struct SceneTests {
    private func validJSON() -> Data {
        Data(#"{"id":"synthetic-test","title":"Synthetic test","chart":{"center":[0.0,45.0],"zoom":13.0,"logicalWidth":1728,"logicalHeight":1117,"deviceScaleFactor":2,"asset":"synthetic-test@2x.png","lightVisibilityAsset":"synthetic-test-light-visibility@2x.png"},"light":{"name":"Synthetic light","coordinate":[0.0,45.0],"character":"Fl(2) WRG 6s","periodSeconds":6.0,"pulses":[{"start":0.0,"end":0.48},{"start":0.96,"end":1.44}],"anchor":{"x":0.5,"y":0.5},"sectors":[{"startBearing":90.0,"endBearing":120.0,"colour":"green","rangeNauticalMiles":10.0},{"startBearing":120.0,"endBearing":180.0,"colour":"white","rangeNauticalMiles":20.0},{"startBearing":180.0,"endBearing":270.0,"colour":"red","rangeNauticalMiles":5.0}]}}"#.utf8)
    }

    @Test func decodesSyntheticScene() throws {
        let scene = try SaverScene.decode(validJSON())
        #expect(scene.id == "synthetic-test")
        #expect(scene.chart.physicalWidth == 3456)
        #expect(scene.chart.physicalHeight == 2234)
        #expect(scene.chart.lightVisibilityAsset == "synthetic-test-light-visibility@2x.png")
        #expect(scene.light.pulses == [Pulse(start: 0, end: 0.48), Pulse(start: 0.96, end: 1.44)])
        #expect(scene.light.sectors.first == LightSector(
            startBearing: 90, endBearing: 120, colour: .green, rangeNauticalMiles: 10
        ))
        #expect(scene.light.sectors.last == LightSector(
            startBearing: 180, endBearing: 270, colour: .red, rangeNauticalMiles: 5
        ))
    }

    @Test func rejectsInvalidSchedules() throws {
        let decoded = try JSONDecoder().decode(SaverScene.self, from: validJSON())
        let overlapping = SaverScene(
            id: decoded.id, title: decoded.title, chart: decoded.chart,
            light: LightSpec(
                name: decoded.light.name, coordinate: decoded.light.coordinate,
                character: decoded.light.character, periodSeconds: 6,
                pulses: [Pulse(start: 0, end: 1), Pulse(start: 0.5, end: 2)],
                anchor: decoded.light.anchor, sectors: decoded.light.sectors
            )
        )
        #expect(throws: SceneValidationError.self) { try overlapping.validated() }
        let continuous = SaverScene(
            id: decoded.id, title: decoded.title, chart: decoded.chart,
            light: LightSpec(
                name: decoded.light.name, coordinate: decoded.light.coordinate,
                character: decoded.light.character, periodSeconds: 6,
                pulses: [Pulse(start: 0, end: 6)], anchor: decoded.light.anchor,
                sectors: decoded.light.sectors
            )
        )
        #expect(throws: SceneValidationError.self) { try continuous.validated() }
    }

    @Test func rejectsAnchorOutsideUnitSquare() throws {
        let decoded = try JSONDecoder().decode(SaverScene.self, from: validJSON())
        let bad = SaverScene(
            id: decoded.id, title: decoded.title, chart: decoded.chart,
            light: LightSpec(
                name: decoded.light.name, coordinate: decoded.light.coordinate,
                character: decoded.light.character, periodSeconds: decoded.light.periodSeconds,
                pulses: decoded.light.pulses, anchor: UnitAnchor(x: -0.01, y: 0.5),
                sectors: decoded.light.sectors
            )
        )
        #expect(throws: SceneValidationError.self) { try bad.validated() }
    }

    @Test func rejectsEmptyInvalidAndOverlappingLightSectors() throws {
        let decoded = try JSONDecoder().decode(SaverScene.self, from: validJSON())
        let invalidSectors: [[LightSector]] = [
            [],
            [LightSector(startBearing: -0.1, endBearing: 20, colour: .white, rangeNauticalMiles: 10)],
            [LightSector(startBearing: 10, endBearing: 361, colour: .white, rangeNauticalMiles: 10)],
            [LightSector(startBearing: 20, endBearing: 10, colour: .white, rangeNauticalMiles: 10)],
            [LightSector(startBearing: 10, endBearing: 20, colour: .white, rangeNauticalMiles: 0)],
            [
                LightSector(startBearing: 10, endBearing: 30, colour: .white, rangeNauticalMiles: 10),
                LightSector(startBearing: 29, endBearing: 40, colour: .green, rangeNauticalMiles: 9),
            ],
        ]
        for sectors in invalidSectors {
            let scene = SaverScene(
                id: decoded.id, title: decoded.title, chart: decoded.chart,
                light: LightSpec(
                    name: decoded.light.name, coordinate: decoded.light.coordinate,
                    character: decoded.light.character, periodSeconds: decoded.light.periodSeconds,
                    pulses: decoded.light.pulses, anchor: decoded.light.anchor, sectors: sectors
                )
            )
            #expect(throws: SceneValidationError.self) { try scene.validated() }
        }
    }

    @Test func rejectsInvalidChartAndLightFields() throws {
        let source = String(decoding: validJSON(), as: UTF8.self)
        let replacements = [
            (#""logicalWidth":1728"#, #""logicalWidth":0"#),
            (#""logicalWidth":1728"#, #""logicalWidth":9223372036854775807"#),
            (#""deviceScaleFactor":2"#, #""deviceScaleFactor":0"#),
            (#""asset":"synthetic-test@2x.png""#, #""asset":"../chart.jpg""#),
            (#""lightVisibilityAsset":"synthetic-test-light-visibility@2x.png""#, #""lightVisibilityAsset":"mask.jpg""#),
            (#""lightVisibilityAsset":"synthetic-test-light-visibility@2x.png""#, #""lightVisibilityAsset":"synthetic-test@2x.png""#),
            (#""center":[0.0,45.0]"#, #""center":[181,45.0]"#),
            (#""coordinate":[0.0,45.0]"#, #""coordinate":[0.0,91]"#),
            (#""periodSeconds":6.0"#, #""periodSeconds":0"#),
        ]
        for (old, new) in replacements {
            let data = Data(source.replacingOccurrences(of: old, with: new).utf8)
            #expect(throws: SceneValidationError.self) { try SaverScene.decode(data) }
        }
    }

    @Test func rejectsLogicalDimensionAboveJavaScriptSafeInteger() throws {
        let source = String(decoding: validJSON(), as: UTF8.self)
        let data = Data(
            source
                .replacingOccurrences(of: #""logicalWidth":1728"#, with: #""logicalWidth":9007199254740992"#)
                .replacingOccurrences(of: #""deviceScaleFactor":2"#, with: #""deviceScaleFactor":1"#)
                .utf8
        )

        #expect(throws: SceneValidationError.self) { try SaverScene.decode(data) }
    }

    @Test func rejectsJavaScriptUnsafePhysicalDimensionFromSafeOperands() throws {
        let source = String(decoding: validJSON(), as: UTF8.self)
        let data = Data(
            source.replacingOccurrences(of: #""logicalWidth":1728"#, with: #""logicalWidth":4503599627370496"#).utf8
        )

        #expect(throws: SceneValidationError.self) { try SaverScene.decode(data) }
    }

    @Test func acceptsMaximumJavaScriptSafePhysicalDimension() throws {
        let source = String(decoding: validJSON(), as: UTF8.self)
        let data = Data(
            source
                .replacingOccurrences(of: #""logicalWidth":1728"#, with: #""logicalWidth":9007199254740991"#)
                .replacingOccurrences(of: #""deviceScaleFactor":2"#, with: #""deviceScaleFactor":1"#)
                .utf8
        )

        let scene = try SaverScene.decode(data)
        #expect(scene.chart.physicalWidth == 9_007_199_254_740_991)
    }
}
