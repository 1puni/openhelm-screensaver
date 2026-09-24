import CoreGraphics
import Testing
@testable import OpenHelmChartSaverCore

@Suite("Aspect-fill layout")
struct AspectFillTests {
    @Test func exactRetinaAspectFillsWithoutCrop() {
        let result = AspectFill.layout(
            imageSize: CGSize(width: 3456, height: 2234),
            viewSize: CGSize(width: 1728, height: 1117),
            anchor: UnitAnchor(x: 0.5, y: 0.5), backingScale: 2
        )
        #expect(result.frame == CGRect(x: 0, y: 0, width: 1728, height: 1117))
        #expect(result.anchor == CGPoint(x: 864, y: 558.5))
    }

    @Test func widerViewCropsVerticallyAndMapsTopLeftAnchor() {
        let result = AspectFill.layout(
            imageSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 1000, height: 500),
            anchor: UnitAnchor(x: 0.2, y: 0.25), backingScale: 2
        )
        #expect(result.frame == CGRect(x: 0, y: -250, width: 1000, height: 1000))
        #expect(result.anchor == CGPoint(x: 200, y: 500))
    }

    @Test func tallerViewCropsHorizontally() {
        let result = AspectFill.layout(
            imageSize: CGSize(width: 200, height: 100), viewSize: CGSize(width: 1000, height: 1000),
            anchor: UnitAnchor(x: 0.25, y: 0.75), backingScale: 2
        )
        #expect(result.frame == CGRect(x: -500, y: 0, width: 2000, height: 1000))
        #expect(result.anchor == CGPoint(x: 0, y: 250))
    }

    @Test func zeroSizeReturnsZeroLayout() {
        #expect(AspectFill.layout(
            imageSize: .zero, viewSize: CGSize(width: 100, height: 100),
            anchor: UnitAnchor(x: 0.5, y: 0.5), backingScale: 2
        ) == .zero)
    }
}
