import CoreGraphics
import Foundation
import ImageIO

enum DiffError: Error {
    case usage
    case image(String)
    case dimensions
    case insufficientMotion(String, Int)
    case excessiveChange(String, Int, Int)
    case insufficientReach(String, Double, Double)
    case notPrimarilyBrighter(String, Int, Int)
    case escapedVisibilityMask(String, Int)
}

typealias RGBAImage = (width: Int, height: Int, bytes: [UInt8])

func rgba(_ path: String) throws -> RGBAImage {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw DiffError.image(path)
    }
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DiffError.image(path)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return (image.width, image.height, bytes)
}

let args = Array(CommandLine.arguments.dropFirst())
guard
    args.count == 6,
    let centerX = Int(args[4]),
    let centerY = Int(args[5]),
    centerX >= 0,
    centerY >= 0
else {
    throw DiffError.usage
}

let inactive = try rgba(args[0])
let activeA = try rgba(args[1])
let activeB = try rgba(args[2])
let visibility = try rgba(args[3])
guard inactive.width == activeA.width, inactive.height == activeA.height,
      inactive.width == activeB.width, inactive.height == activeB.height,
      inactive.width == visibility.width, inactive.height == visibility.height else {
    throw DiffError.dimensions
}

struct DiffStats {
    var changed = 0
    var brighter = 0
    var outsideVisibilityMask = 0
    var maximumDistanceSquared = 0.0
}

func diffStats(
    reference: RGBAImage,
    candidate: RGBAImage,
    visibilityMask: RGBAImage? = nil
) -> DiffStats {
    var stats = DiffStats()
    for y in 0..<reference.height {
        for x in 0..<reference.width {
            let offset = (y * reference.width + x) * 4
            let referenceRed = Int(reference.bytes[offset])
            let referenceGreen = Int(reference.bytes[offset + 1])
            let referenceBlue = Int(reference.bytes[offset + 2])
            let candidateRed = Int(candidate.bytes[offset])
            let candidateGreen = Int(candidate.bytes[offset + 1])
            let candidateBlue = Int(candidate.bytes[offset + 2])
            let maximumChannelDelta = max(
                abs(referenceRed - candidateRed),
                abs(referenceGreen - candidateGreen),
                abs(referenceBlue - candidateBlue)
            )
            guard maximumChannelDelta >= 2 else { continue }

            stats.changed += 1
            if let visibilityMask, visibilityMask.bytes[offset + 3] == 0 {
                stats.outsideVisibilityMask += 1
            }
            let referenceLuma = referenceRed + referenceGreen + referenceBlue
            let candidateLuma = candidateRed + candidateGreen + candidateBlue
            if candidateLuma > referenceLuma { stats.brighter += 1 }
            let deltaX = Double(x - centerX)
            let deltaY = Double(y - centerY)
            stats.maximumDistanceSquared = max(
                stats.maximumDistanceSquared,
                deltaX * deltaX + deltaY * deltaY
            )
        }
    }
    return stats
}

let pixelCount = inactive.width * inactive.height
let minimumChanged = max(256, pixelCount / 50_000)
let maximumChanged = pixelCount / 12
let minimumReach = Double(min(inactive.width, inactive.height)) * 0.08

func requireActiveSweep(_ label: String, _ candidate: RGBAImage) throws {
    let stats = diffStats(reference: inactive, candidate: candidate, visibilityMask: visibility)
    if stats.changed < minimumChanged {
        throw DiffError.insufficientMotion(label, stats.changed)
    }
    if stats.changed > maximumChanged {
        throw DiffError.excessiveChange(label, stats.changed, maximumChanged)
    }
    let reach = sqrt(stats.maximumDistanceSquared)
    if reach < minimumReach {
        throw DiffError.insufficientReach(label, reach, minimumReach)
    }
    if stats.brighter * 100 < stats.changed * 85 {
        throw DiffError.notPrimarilyBrighter(label, stats.brighter, stats.changed)
    }
    if stats.outsideVisibilityMask > 0 {
        throw DiffError.escapedVisibilityMask(label, stats.outsideVisibilityMask)
    }
    print("\(label): \(stats.changed) illuminated pixels, reach \(Int(reach)) px")
}

try requireActiveSweep("active-a", activeA)
try requireActiveSweep("active-b", activeB)
let rotated = diffStats(reference: activeA, candidate: activeB)
if rotated.changed < minimumChanged {
    throw DiffError.insufficientMotion("active-a/active-b rotation", rotated.changed)
}
print("rotating selective-light sweep verified; chart layer remains structurally static in native tests")
