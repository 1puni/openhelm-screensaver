import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import OpenHelmChartSaver
import OpenHelmChartSaverCore

@MainActor
@Suite("Native saver view")
struct OpenHelmChartSaverViewTests {
    private func scene(
        logicalWidth: Int = 2,
        logicalHeight: Int = 2,
        deviceScaleFactor: Int = 1,
        pulses: [Pulse] = [Pulse(start: 0, end: 0.48), Pulse(start: 0.96, end: 1.44)],
        sectors: [LightSector] = [LightSector(
            startBearing: 0, endBearing: 360, colour: .white, rangeNauticalMiles: 10
        )]
    ) -> SaverScene {
        SaverScene(
            id: "test-scene",
            title: "Test",
            chart: ChartSpec(
                center: GeoCoordinate(longitude: 18, latitude: 59),
                zoom: 13,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                deviceScaleFactor: deviceScaleFactor,
                asset: "chart.png",
                lightVisibilityAsset: "light-visibility.png"
            ),
            light: LightSpec(
                name: "Test",
                coordinate: GeoCoordinate(longitude: 18, latitude: 59),
                character: "Fl(2) W 6s",
                periodSeconds: 6,
                pulses: pulses,
                anchor: UnitAnchor(x: 0.5, y: 0.5),
                sectors: sectors
            )
        )
    }

    private func withResources(
        scene: SaverScene,
        pngData: Data? = nil,
        visibilityPNGData: Data? = nil,
        _ body: (URL, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenHelmChartSaverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sceneURL = directory.appendingPathComponent("scene.json")
        try JSONEncoder().encode(scene).write(to: sceneURL)
        if let pngData {
            try pngData.write(to: directory.appendingPathComponent(scene.chart.asset))
        }
        if let visibilityPNGData {
            try visibilityPNGData.write(
                to: directory.appendingPathComponent(scene.chart.lightVisibilityAsset)
            )
        }
        try body(sceneURL, directory)
    }

    private func pngData(width: Int = 2, height: Int = 2) throws -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        return try #require(representation.representation(using: .png, properties: [:]))
    }

    private func requireRootLayer(_ view: OpenHelmChartSaverView) throws -> CALayer {
        let root = try #require(view.layer)
        let background = try #require(root.backgroundColor)
        #expect(view.isOpaque)
        #expect(root.isOpaque)
        #expect(background == NSColor.black.cgColor)
        return root
    }

    @Test func chartStaysStaticBehindPairedFeatheredBeamsAndHotCore() throws {
        try withResources(
            scene: scene(),
            pngData: pngData(),
            visibilityPNGData: pngData()
        ) { sceneURL, directory in
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: false,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            view.layoutSubtreeIfNeeded()

            let root = try requireRootLayer(view)
            let layers = try #require(root.sublayers)
            #expect(layers.count == 3)
            let chart = layers[0]
            #expect(chart.sublayers?.isEmpty ?? true)
            let beamContainer = layers[1]
            let visibilityMask = try #require(beamContainer.mask)
            let beams = try #require(beamContainer.sublayers)
            let firstBeam = try #require(beams[0] as? CAGradientLayer)
            let secondBeam = try #require(beams[1] as? CAGradientLayer)
            let core = layers[2]
            #expect(chart.contents != nil)
            #expect(visibilityMask.contents != nil)
            #expect(firstBeam.type == .axial)
            #expect(secondBeam.type == .axial)
            let firstFeather = try #require(firstBeam.mask as? CAGradientLayer)
            let secondFeather = try #require(secondBeam.mask as? CAGradientLayer)
            #expect(firstFeather.type == .axial)
            #expect(secondFeather.type == .axial)
            #expect(firstFeather.startPoint == CGPoint(x: 0.5, y: 0))
            #expect(firstFeather.endPoint == CGPoint(x: 0.5, y: 1))
            #expect(firstFeather.mask is CAShapeLayer)
            #expect(secondFeather.mask is CAShapeLayer)
            #expect(core.backgroundColor == NSColor.white.cgColor)

            let beforeFrame = chart.frame
            let beforeContents = try #require(chart.contents as AnyObject?)
            view.renderPreviewFrame(at: 0.24)
            #expect(chart.frame == beforeFrame)
            #expect((try #require(chart.contents as AnyObject?)) === beforeContents)
            #expect(firstBeam.opacity == 1)
            #expect(secondBeam.opacity == 1)
            #expect(core.opacity == 1)
            let firstTransform = firstBeam.transform
            let secondTransform = secondBeam.transform
            #expect(!CATransform3DEqualToTransform(firstTransform, secondTransform))

            view.renderPreviewFrame(at: 0.74)
            #expect(chart.frame == beforeFrame)
            #expect((try #require(chart.contents as AnyObject?)) === beforeContents)
            #expect(!CATransform3DEqualToTransform(firstBeam.transform, firstTransform))
            #expect(!CATransform3DEqualToTransform(secondBeam.transform, secondTransform))
            #expect(core.opacity == 1)
        }
    }

    @Test func inscriptionFollowsChartThroughResizeAndStaysFixedDuringSweep() throws {
        try withResources(scene: scene(), pngData: pngData(), visibilityPNGData: pngData()) {
            sceneURL, directory in
            try pngData().write(to: directory.appendingPathComponent("logo.png"))
            try Data(#"{"image":"logo.png","text":"1puni.com","centerX":0.49,"centerY":0.245,"width":440,"rotationDegrees":-36}"#.utf8)
                .write(to: directory.appendingPathComponent("inscription.json"))
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100), isPreview: false,
                sceneURL: sceneURL, resourceDirectory: directory
            ))
            for size in [CGSize(width: 100, height: 100), CGSize(width: 200, height: 100),
                         CGSize(width: 100, height: 200)] {
                view.frame.size = size
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                let chart = try #require(view.layer?.sublayers?.first)
                let mark = try #require(chart.sublayers?.first)
                #expect(mark.name == "chart-inscription")
                #expect(abs(mark.position.x / chart.bounds.width - 0.49) < 0.0001)
                #expect(abs(mark.position.y / chart.bounds.height - 0.755) < 0.0001)
                #expect(mark.sublayers?.count == 1)
                #expect(mark.sublayers?.first?.contents != nil)
                let position = mark.position
                let transform = mark.transform
                view.renderPreviewFrame(at: 1.5)
                view.renderPreviewFrame(at: 2.75)
                #expect(mark.position == position)
                #expect(CATransform3DEqualToTransform(mark.transform, transform))
            }
        }
    }

    @Test func beamLengthTracksTheCurrentSectorRangeAtTrueChartScale() throws {
        let short = LightSector(
            startBearing: 0, endBearing: 180, colour: .white, rangeNauticalMiles: 0.001
        )
        let long = LightSector(
            startBearing: 180, endBearing: 360, colour: .green, rangeNauticalMiles: 0.002
        )
        let singlePulse = [Pulse(start: 0, end: 0.2)]
        try withResources(
            scene: scene(pulses: singlePulse, sectors: [short, long]),
            pngData: pngData(),
            visibilityPNGData: pngData()
        ) { sceneURL, directory in
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: false,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            view.layoutSubtreeIfNeeded()
            let container = try #require(view.layer?.sublayers?[1])
            let beam = try #require(container.sublayers?[0] as? CAGradientLayer)

            view.renderPreviewFrame(at: 0.1)
            let shortLength = beam.bounds.width
            view.renderPreviewFrame(at: 3.1)
            let longLength = beam.bounds.width

            #expect(shortLength > 0)
            #expect(abs(longLength / shortLength - 2) < 0.001)
        }
    }

    @Test func missingResourcesStayOpaqueBlackWithoutChartOrGlowLayers() throws {
        let missing = URL(fileURLWithPath: "/path/that/does/not/exist")
        let view = try #require(OpenHelmChartSaverView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isPreview: false,
            sceneURL: missing.appendingPathComponent("scene.json"),
            resourceDirectory: missing
        ))
        let root = try requireRootLayer(view)
        #expect(root.sublayers?.count ?? 0 == 0)
        view.renderPreviewFrame(at: 0.24)
        #expect(root.sublayers?.count ?? 0 == 0)
    }

    @Test func corruptPNGStaysOpaqueBlackWithoutChartOrGlowLayers() throws {
        try withResources(
            scene: scene(),
            pngData: Data("not a PNG".utf8),
            visibilityPNGData: pngData()
        ) { sceneURL, directory in
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: false,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            let root = try requireRootLayer(view)
            #expect(root.sublayers?.count ?? 0 == 0)
            view.renderPreviewFrame(at: 0.24)
            #expect(root.sublayers?.count ?? 0 == 0)
        }
    }

    @Test func wrongImageDimensionsStayOpaqueBlackWithoutChartOrGlowLayers() throws {
        try withResources(
            scene: scene(logicalWidth: 4),
            pngData: pngData(),
            visibilityPNGData: pngData()
        ) { sceneURL, directory in
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: false,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            let root = try requireRootLayer(view)
            #expect(root.sublayers?.count ?? 0 == 0)
            view.renderPreviewFrame(at: 0.24)
            #expect(root.sublayers?.count ?? 0 == 0)
        }
    }

    @Test func missingVisibilityMaskStaysOpaqueBlackWithoutChartOrBeamLayers() throws {
        try withResources(scene: scene(), pngData: pngData()) { sceneURL, directory in
            let view = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: false,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            let root = try requireRootLayer(view)
            #expect(root.sublayers?.count ?? 0 == 0)
        }
    }

    @Test func optionsSheetShowsBundledCreditsOnlyWhenPresent() throws {
        try withResources(scene: scene(), pngData: pngData(), visibilityPNGData: pngData()) { sceneURL, directory in
            let plain = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: true,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            #expect(!plain.hasConfigureSheet)
            #expect(plain.configureSheet == nil)

            let credits = "© OpenStreetMap contributors https://www.openstreetmap.org/copyright"
            try credits.write(to: directory.appendingPathComponent("CREDITS.txt"), atomically: true, encoding: .utf8)
            let credited = try #require(OpenHelmChartSaverView(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                isPreview: true,
                sceneURL: sceneURL,
                resourceDirectory: directory
            ))
            #expect(credited.hasConfigureSheet)
            let sheet = try #require(credited.configureSheet)
            #expect(credited.configureSheet === sheet)
            let scroll = try #require(sheet.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
            let text = try #require(scroll.documentView as? NSTextView)
            #expect(text.string == credits)
            #expect(!text.isEditable)
            let link = text.textStorage?.attribute(.link, at: credits.count - 5, effectiveRange: nil)
            #expect(link != nil)
        }
    }

    private func sceneNamed(_ id: String, title: String) -> SaverScene {
        let base = scene()
        return SaverScene(id: id, title: title, chart: base.chart, light: base.light)
    }

    @Test func catalogPersistsTheChosenChartAndSwapsItsCredits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenHelmChartSaverCatalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (id, title) in [("tynningo", "Tynningö"), ("alcatraz", "Alcatraz")] {
            let directory = root.appendingPathComponent("Scenes/\(id)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let scene = sceneNamed(id, title: title)
            try JSONEncoder().encode(scene).write(to: directory.appendingPathComponent("scene.json"))
            try pngData().write(to: directory.appendingPathComponent(scene.chart.asset))
            try pngData().write(to: directory.appendingPathComponent(scene.chart.lightVisibilityAsset))
            try "credits for \(title)".write(
                to: directory.appendingPathComponent("CREDITS.txt"), atomically: true, encoding: .utf8
            )
        }
        // A directory whose scene id disagrees with its name is ignored, not guessed at.
        let stray = root.appendingPathComponent("Scenes/stray")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try JSONEncoder().encode(sceneNamed("other", title: "Other")).write(to: stray.appendingPathComponent("scene.json"))

        #expect(discoverSaverCatalog(in: root).map(\.id) == ["alcatraz", "tynningo"])

        let suite = "OpenHelmChartSaverTests-\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: suite))
        defer { settings.removePersistentDomain(forName: suite) }

        let view = try #require(OpenHelmChartSaverView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isPreview: true, catalogDirectory: root, settings: settings
        ))
        #expect(view.selectedSceneID == "alcatraz")
        #expect(view.hasConfigureSheet)
        let sheet = try #require(view.configureSheet)
        let picker = try #require(sheet.contentView?.subviews.compactMap { $0 as? NSPopUpButton }.first)
        #expect(picker.itemTitles == ["Alcatraz", "Tynningö"])
        let text = try #require(sheet.contentView?.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView)
        #expect(text.string == "credits for Alcatraz")

        view.selectScene(id: "tynningo")
        #expect(settings.string(forKey: "selectedSceneID") == "tynningo")
        #expect(text.string == "credits for Tynningö")
        let root0 = try requireRootLayer(view)
        #expect(root0.sublayers?.count == 3)
        #expect(root0.sublayers?[1].sublayers?.count == 2)  // beams rebuilt, not accumulated

        let reopened = try #require(OpenHelmChartSaverView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isPreview: true, catalogDirectory: root, settings: settings
        ))
        #expect(reopened.selectedSceneID == "tynningo")
    }
}
