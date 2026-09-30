// Load a built .saver exactly as the screen saver host does (principal class, bundle resources,
// ScreenSaverDefaults), animate every bundled scene and write one snapshot per scene.
// Usage: swift scripts/verify-bundle-load.swift BUNDLE.saver [SNAPSHOT_DIR]
// Temporarily writes the bundle's own "selectedSceneID" default and restores it afterwards.
import AppKit
import QuartzCore
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

_ = NSApplication.shared
guard CommandLine.arguments.count > 1 else { fail("usage: BUNDLE.saver [SNAPSHOT_DIR]") }
let bundlePath = CommandLine.arguments[1]
let snapshotDirectory = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
guard let bundle = Bundle(path: bundlePath), let identifier = bundle.bundleIdentifier else { fail("not a bundle: \(bundlePath)") }
do { try bundle.loadAndReturnError() } catch { fail("load failed: \(error)") }
guard let viewType = bundle.principalClass as? ScreenSaverView.Type else { fail("principal class is not a ScreenSaverView") }
guard let defaults = ScreenSaverDefaults(forModuleWithName: identifier) else { fail("no ScreenSaverDefaults for \(identifier)") }

let key = "selectedSceneID"
let previous = defaults.object(forKey: key)
defer {
    if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
    defaults.synchronize()
}

let scenesRoot = bundle.resourceURL!.appendingPathComponent("Scenes")
let ids = ((try? FileManager.default.contentsOfDirectory(atPath: scenesRoot.path)) ?? []).sorted()
guard !ids.isEmpty else { fail("bundle carries no Scenes/<id>/ collection") }

func makeView() -> ScreenSaverView {
    guard let view = viewType.init(frame: NSRect(x: 0, y: 0, width: 1728, height: 1117), isPreview: false) else {
        fail("principal class failed to initialise")
    }
    view.layoutSubtreeIfNeeded()
    return view
}

// Fresh install: no saved choice, so the Info.plist default must win.
defaults.removeObject(forKey: key)
defaults.synchronize()
let fresh = makeView()
let expectedDefault = bundle.object(forInfoDictionaryKey: "OpenHelmDefaultScene") as? String
guard fresh.hasConfigureSheet, let sheet = fresh.configureSheet else { fail("no Options sheet") }
guard let picker = sheet.contentView?.subviews.compactMap({ $0 as? NSPopUpButton }).first else { fail("Options sheet has no chart picker") }
guard picker.numberOfItems == ids.count else { fail("picker shows \(picker.numberOfItems) charts, bundle has \(ids.count)") }
let credits = sheet.contentView?.subviews.compactMap { ($0 as? NSScrollView)?.documentView as? NSTextView }.first?.string ?? ""
guard !credits.isEmpty else { fail("Options sheet shows no credits") }
print("fresh install: picker [\(picker.itemTitles.joined(separator: " | "))], selected \"\(picker.titleOfSelectedItem ?? "?")\", default \(expectedDefault ?? "first")")

for id in ids {
    defaults.set(id, forKey: key)
    defaults.synchronize()
    let view = makeView()
    view.startAnimation()
    for _ in 0..<180 {
        view.animateOneFrame()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0 / 30))
    }
    view.stopAnimation()
    guard let layers = view.layer?.sublayers, layers.count == 3,
          layers[0].contents != nil, layers[1].mask?.contents != nil else {
        fail("\(id): chart, beam mask or core missing")
    }
    let hasInscription = FileManager.default.fileExists(
        atPath: scenesRoot.appendingPathComponent(id).appendingPathComponent("inscription.json").path
    )
    let inscription = layers[0].sublayers?.first { $0.name == "chart-inscription" }
    guard hasInscription == (inscription != nil) else { fail("\(id): inscription did not load") }
    if let inscription {
        guard inscription.sublayers?.count == 1,
              inscription.sublayers?.first?.contents != nil else {
            fail("\(id): complete domain artwork missing")
        }
    }
    let sceneCredits = view.configureSheet?.contentView?.subviews
        .compactMap { ($0 as? NSScrollView)?.documentView as? NSTextView }.first?.string ?? ""
    guard sceneCredits.contains("NOT FOR NAVIGATION") else { fail("\(id): credits lack the navigation disclaimer") }
    if let snapshotDirectory {
        try? FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
        view.layer?.render(in: context)
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        try! rep.representation(using: .png, properties: [:])!.write(to: snapshotDirectory.appendingPathComponent("\(id).png"))
    }
    print("\(id): loaded from bundle, 180 frames animated, credits and artwork verified")
}
print("verified dynamic load of \(bundlePath): \(ids.count) scenes; no installation")
