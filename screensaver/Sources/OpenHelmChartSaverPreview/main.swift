import AppKit
import CoreGraphics
import ImageIO
import OpenHelmChartSaver

struct Options {
    var scene = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Scenes/alcatraz-noaa-preview.json")
    var resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources")
    var snapshot: URL?
    var phase = 2.0
    var width = 1728
    var height = 1117
    var scale = 2
    var frames = 1
    var fps = 30.0
}

enum ParseError: Error {
    case missingValue(String)
    case unknown(String)
    case invalid(String)
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let flag = arguments[index]
        switch flag {
        case "--scene", "--resources", "--snapshot", "--phase", "--width", "--height", "--scale", "--frames", "--fps":
            guard index + 1 < arguments.count else { throw ParseError.missingValue(flag) }
        default:
            throw ParseError.unknown(flag)
        }

        let value = arguments[index + 1]
        switch flag {
        case "--scene":
            options.scene = URL(fileURLWithPath: value)
        case "--resources":
            options.resources = URL(fileURLWithPath: value)
        case "--snapshot":
            options.snapshot = URL(fileURLWithPath: value)
        case "--phase":
            guard let parsed = Double(value), parsed.isFinite, parsed >= 0 else {
                throw ParseError.invalid(flag)
            }
            options.phase = parsed
        case "--width":
            guard let parsed = Int(value), parsed > 0 else { throw ParseError.invalid(flag) }
            options.width = parsed
        case "--height":
            guard let parsed = Int(value), parsed > 0 else { throw ParseError.invalid(flag) }
            options.height = parsed
        case "--scale":
            guard let parsed = Int(value), parsed > 0 else { throw ParseError.invalid(flag) }
            options.scale = parsed
        case "--frames":
            guard let parsed = Int(value), parsed > 0 else { throw ParseError.invalid(flag) }
            options.frames = parsed
        case "--fps":
            guard let parsed = Double(value), parsed.isFinite, parsed > 0 else { throw ParseError.invalid(flag) }
            options.fps = parsed
        default:
            preconditionFailure("validated flag was not handled")
        }
        index += 2
    }
    return options
}

@MainActor
func writeSnapshot(view: OpenHelmChartSaverView, to url: URL, scale: Int) throws {
    let width = Int(view.bounds.width) * scale
    let height = Int(view.bounds.height) * scale
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    view.layer?.render(in: context)
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
_ = NSApplication.shared
guard let saver = OpenHelmChartSaverView(
    frame: CGRect(x: 0, y: 0, width: options.width, height: options.height),
    isPreview: false,
    sceneURL: options.scene,
    resourceDirectory: options.resources
) else {
    throw CocoaError(.coderInvalidValue)
}
saver.layoutSubtreeIfNeeded()

if let snapshot = options.snapshot, options.frames > 1 {
    // Frame sequence for clips: SNAPSHOT-0000.png, SNAPSHOT-0001.png, … at --fps from --phase.
    let stem = snapshot.deletingPathExtension().path
    for frame in 0..<options.frames {
        saver.renderPreviewFrame(at: options.phase + Double(frame) / options.fps)
        let url = URL(fileURLWithPath: stem + String(format: "-%04d.png", frame))
        try writeSnapshot(view: saver, to: url, scale: options.scale)
    }
} else if let snapshot = options.snapshot {
    saver.renderPreviewFrame(at: options.phase)
    try writeSnapshot(view: saver, to: snapshot, scale: options.scale)
} else {
    let visibleSize = CGSize(width: min(options.width, 1180), height: min(options.height, 762))
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: visibleSize),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    saver.frame = CGRect(origin: .zero, size: visibleSize)
    window.title = "OpenHelm Chart Saver Preview"
    window.contentView = saver
    window.center()
    window.makeKeyAndOrderFront(nil)
    saver.startAnimation()
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.run()
}
