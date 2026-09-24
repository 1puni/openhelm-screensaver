import CoreGraphics

public struct ChartLayout: Equatable, Sendable {
    public let frame: CGRect
    public let anchor: CGPoint

    public init(frame: CGRect, anchor: CGPoint) {
        self.frame = frame
        self.anchor = anchor
    }

    public static let zero = ChartLayout(frame: .zero, anchor: .zero)
}

public enum AspectFill {
    public static func layout(
        imageSize: CGSize,
        viewSize: CGSize,
        anchor: UnitAnchor,
        backingScale: CGFloat
    ) -> ChartLayout {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              viewSize.width.isFinite, viewSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let pixelScale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let width = (imageSize.width * scale * pixelScale).rounded(.up) / pixelScale
        let height = (imageSize.height * scale * pixelScale).rounded(.up) / pixelScale
        let x = (((viewSize.width - width) / 2) * pixelScale).rounded() / pixelScale
        let y = (((viewSize.height - height) / 2) * pixelScale).rounded() / pixelScale
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let point = CGPoint(
            x: frame.minX + CGFloat(anchor.x) * frame.width,
            y: frame.maxY - CGFloat(anchor.y) * frame.height
        )
        return ChartLayout(frame: frame, anchor: point)
    }
}
