import CoreGraphics
import Foundation
import ImageIO

enum ColourCheckError: Error {
    case usage
    case image(String)
    case missingSignalColour(String, Int)
    case excessiveMagentaClutter(Int, Int)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 1 else { throw ColourCheckError.usage }

let path = args[0]
let url = URL(fileURLWithPath: path)
guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    throw ColourCheckError.image(path)
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
        throw ColourCheckError.image(path)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
}

var redPixels = 0
var greenPixels = 0
var yellowPixels = 0
var magentaPixels = 0
for offset in stride(from: 0, to: bytes.count, by: 4) {
    let red = Int(bytes[offset])
    let green = Int(bytes[offset + 1])
    let blue = Int(bytes[offset + 2])
    if red >= 160, green <= 105, blue <= 125 {
        redPixels += 1
    }
    if green >= 130, red <= 105, blue <= 115 {
        greenPixels += 1
    }
    if red >= 160, green >= 130, blue <= 105 {
        yellowPixels += 1
    }
    if red >= 150, blue >= 100, green <= 115,
       red >= green + 50, blue >= green + 30 {
        magentaPixels += 1
    }
}

let minimumPixels = 40
for (name, count) in [("red", redPixels), ("green", greenPixels)] {
    if count < minimumPixels {
        throw ColourCheckError.missingSignalColour(name, count)
    }
}
let maximumMagentaPixels = 1_000
if magentaPixels > maximumMagentaPixels {
    throw ColourCheckError.excessiveMagentaClutter(magentaPixels, maximumMagentaPixels)
}

print(
    "source-colour navigation symbols verified: red \(redPixels), green \(greenPixels), " +
    "yellow \(yellowPixels), magenta \(magentaPixels) pixels"
)
