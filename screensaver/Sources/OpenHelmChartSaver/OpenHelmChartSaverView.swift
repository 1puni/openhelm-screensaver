import AppKit
import CoreGraphics
import ImageIO
import OpenHelmChartSaverCore
import OSLog
import QuartzCore
import ScreenSaver

enum SaverResourceError: Error {
    case missing(String)
    case invalidImage(String)
    case wrongDimensions
}

struct LoadedSaverResources {
    let scene: SaverScene
    let image: CGImage
    let lightVisibilityImage: CGImage
}

func loadSaverResources(sceneURL: URL, assetDirectory: URL) throws -> LoadedSaverResources {
    guard FileManager.default.fileExists(atPath: sceneURL.path) else {
        throw SaverResourceError.missing(sceneURL.path)
    }

    let scene = try SaverScene.decode(Data(contentsOf: sceneURL))
    func loadImage(named asset: String) throws -> CGImage {
        let url = assetDirectory.appendingPathComponent(asset)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SaverResourceError.invalidImage(url.path)
        }
        return image
    }
    let image = try loadImage(named: scene.chart.asset)
    let lightVisibilityImage = try loadImage(named: scene.chart.lightVisibilityAsset)
    guard [image, lightVisibilityImage].allSatisfy({ candidate in
        candidate.width == scene.chart.physicalWidth &&
            candidate.height == scene.chart.physicalHeight
    }) else {
        throw SaverResourceError.wrongDimensions
    }
    return LoadedSaverResources(
        scene: scene,
        image: image,
        lightVisibilityImage: lightVisibilityImage
    )
}

@MainActor
@objc(OpenHelmChartSaverView)
public final class OpenHelmChartSaverView: ScreenSaverView {
    private static let logger = Logger(
        subsystem: "com.openhelm.ChartSaver",
        category: "runtime"
    )

    private let chartLayer = CALayer()
    private let beamContainerLayer = CALayer()
    private let lightVisibilityLayer = CALayer()
    private var beamLayers: [CAGradientLayer] = []
    private let coreLayer = CALayer()
    private var scene: SaverScene?
    private var chartImage: CGImage?
    private var sweep: LightSweep?
    private var chartLayout = ChartLayout.zero
    private var lastUptime = 0.0
    private var sceneURL: URL?
    private var resourceDirectory: URL?

    public override init?(frame: NSRect, isPreview: Bool) {
        sceneURL = nil
        resourceDirectory = nil
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    public init?(
        frame: NSRect,
        isPreview: Bool,
        sceneURL: URL,
        resourceDirectory: URL
    ) {
        self.sceneURL = sceneURL
        self.resourceDirectory = resourceDirectory
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    public required init?(coder: NSCoder) {
        sceneURL = nil
        resourceDirectory = nil
        super.init(coder: coder)
        configure()
    }

    public override var isOpaque: Bool { true }
    public override var hasConfigureSheet: Bool { false }

    private func configure() {
        prepareBlackLayerTree()
        do {
            let bundleDirectory = Bundle(for: OpenHelmChartSaverView.self).resourceURL
            guard let assetDirectory = resourceDirectory ?? bundleDirectory else {
                throw SaverResourceError.missing("bundle resource directory")
            }
            let resolvedSceneURL = sceneURL ?? assetDirectory.appendingPathComponent("scene.json")
            let loaded = try loadSaverResources(
                sceneURL: resolvedSceneURL,
                assetDirectory: assetDirectory
            )
            configure(
                scene: loaded.scene,
                image: loaded.image,
                lightVisibilityImage: loaded.lightVisibilityImage
            )
        } catch {
            Self.logger.error(
                "Saver resources unavailable: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func prepareBlackLayerTree() {
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.isOpaque = true
        layer = rootLayer
        animationTimeInterval = 1.0 / 30.0
    }

    private func configure(
        scene: SaverScene,
        image: CGImage,
        lightVisibilityImage: CGImage
    ) {
        self.scene = scene
        chartImage = image
        sweep = LightSweep(light: scene.light)

        chartLayer.contents = image
        chartLayer.contentsGravity = .resize
        chartLayer.minificationFilter = .trilinear
        chartLayer.magnificationFilter = .linear

        lightVisibilityLayer.contents = lightVisibilityImage
        lightVisibilityLayer.contentsGravity = .resize
        lightVisibilityLayer.minificationFilter = .trilinear
        lightVisibilityLayer.magnificationFilter = .linear
        beamContainerLayer.mask = lightVisibilityLayer

        beamLayers = scene.light.pulses.map { _ in
            let beam = CAGradientLayer()
            beam.type = .axial
            beam.colors = [
                NSColor.white.withAlphaComponent(0.86).cgColor,
                NSColor.white.withAlphaComponent(0.40).cgColor,
                NSColor.white.withAlphaComponent(0.15).cgColor,
                NSColor.white.withAlphaComponent(0.04).cgColor,
                NSColor.clear.cgColor,
            ]
            beam.locations = [0, 0.05, 0.30, 0.72, 1]
            beam.startPoint = CGPoint(x: 0, y: 0.5)
            beam.endPoint = CGPoint(x: 1, y: 0.5)
            beam.anchorPoint = CGPoint(x: 0, y: 0.5)

            let feather = CAGradientLayer()
            feather.type = .axial
            feather.colors = [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.08).cgColor,
                NSColor.white.withAlphaComponent(0.48).cgColor,
                NSColor.white.cgColor,
                NSColor.white.withAlphaComponent(0.48).cgColor,
                NSColor.white.withAlphaComponent(0.08).cgColor,
                NSColor.clear.cgColor,
            ]
            feather.locations = [0, 0.18, 0.40, 0.5, 0.60, 0.82, 1]
            feather.startPoint = CGPoint(x: 0.5, y: 0)
            feather.endPoint = CGPoint(x: 0.5, y: 1)
            let wedge = CAShapeLayer()
            wedge.fillColor = NSColor.white.cgColor
            feather.mask = wedge
            beam.mask = feather
            beam.opacity = 0
            return beam
        }

        coreLayer.backgroundColor = NSColor.white.cgColor
        coreLayer.shadowColor = NSColor.white.cgColor
        coreLayer.shadowOpacity = 0.72
        coreLayer.shadowRadius = 4

        layer?.addSublayer(chartLayer)
        for beam in beamLayers {
            beamContainerLayer.addSublayer(beam)
        }
        layer?.addSublayer(beamContainerLayer)
        layer?.addSublayer(coreLayer)
        lastUptime = ProcessInfo.processInfo.systemUptime
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard let scene, let image = chartImage else { return }

        let backingScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        chartLayout = AspectFill.layout(
            imageSize: CGSize(width: image.width, height: image.height),
            viewSize: bounds.size,
            anchor: scene.light.anchor,
            backingScale: backingScale
        )
        let relativeScale = min(
            1,
            max(0.34, min(bounds.width / 1728, bounds.height / 1117))
        )
        let coreDiameter = max(2, 5 * relativeScale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chartLayer.frame = chartLayout.frame
        chartLayer.contentsScale = backingScale
        beamContainerLayer.frame = bounds
        lightVisibilityLayer.frame = chartLayout.frame
        lightVisibilityLayer.contentsScale = backingScale
        coreLayer.frame = CGRect(
            x: chartLayout.anchor.x - coreDiameter / 2,
            y: chartLayout.anchor.y - coreDiameter / 2,
            width: coreDiameter,
            height: coreDiameter
        )
        coreLayer.cornerRadius = coreDiameter / 2
        updateBeams(at: lastUptime)
        CATransaction.commit()
    }

    public override func animateOneFrame() {
        renderPreviewFrame(at: ProcessInfo.processInfo.systemUptime)
    }

    public func renderPreviewFrame(at uptime: TimeInterval) {
        lastUptime = uptime
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateBeams(at: uptime)
        coreLayer.opacity = scene == nil ? 0 : 1
        CATransaction.commit()
    }

    private func updateBeams(at uptime: TimeInterval) {
        guard let scene, let sweep, chartLayout.frame.width > 0 else {
            for beam in beamLayers { beam.opacity = 0 }
            return
        }
        let states = sweep.beams(at: uptime)
        let presentationScale = chartLayout.frame.width / CGFloat(scene.chart.logicalWidth)
        let visibleLengthCap = hypot(bounds.width, bounds.height) * 1.1

        for (index, beam) in beamLayers.enumerated() {
            guard index < states.count, let sector = states[index].sector else {
                beam.opacity = 0
                continue
            }
            let logicalLength = ChartProjection.logicalPoints(
                forNauticalMiles: sector.rangeNauticalMiles,
                latitudeDegrees: scene.light.coordinate.latitude,
                zoom: scene.chart.zoom
            )
            let length = min(CGFloat(logicalLength) * presentationScale, visibleLengthCap)
            guard length.isFinite, length > 0 else {
                beam.opacity = 0
                continue
            }

            let halfWidth = max(0.9, length * tan(0.42 * .pi / 180))
            let beamBounds = CGRect(x: 0, y: 0, width: length, height: halfWidth * 2)
            beam.bounds = beamBounds
            beam.position = chartLayout.anchor
            if let feather = beam.mask as? CAGradientLayer,
               let wedge = feather.mask as? CAShapeLayer {
                feather.frame = beamBounds
                wedge.frame = feather.bounds
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: halfWidth - 0.65))
                path.addLine(to: CGPoint(x: length, y: 0))
                path.addLine(to: CGPoint(x: length, y: halfWidth * 2))
                path.addLine(to: CGPoint(x: 0, y: halfWidth + 0.65))
                path.closeSubpath()
                wedge.path = path
            }
            let radians = CGFloat((90 - states[index].bearingDegrees) * .pi / 180)
            beam.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
            beam.opacity = 1
        }
    }
}
