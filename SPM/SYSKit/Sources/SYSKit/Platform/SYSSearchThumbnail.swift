#if canImport(CoreSpotlight) && !os(watchOS)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The small square picture system search shows beside a result: sized for the list, set on white and saved as JPEG.
public enum SYSSearchThumbnail {
    public static let side = 360

    public enum Mode: String, Sendable {
        case fill
        case fit
    }

    public static func jpeg(
        contentsOf url: URL,
        mode: Mode = .fill,
        side: Int = SYSSearchThumbnail.side,
        quality: Double = 0.82
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return jpeg(from: source, mode: mode, side: side, quality: quality)
    }

    public static func jpeg(
        from data: Data,
        mode: Mode = .fill,
        side: Int = SYSSearchThumbnail.side,
        quality: Double = 0.82
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return jpeg(from: source, mode: mode, side: side, quality: quality)
    }

    private static func jpeg(from source: CGImageSource, mode: Mode, side: Int, quality: Double) -> Data? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        let inset = mode == .fit ? 0.84 : 1.0
        let target = Double(side) * inset
        let reach = mode == .fill ? min(width, height) : max(width, height)
        let scale = min(1, target / Double(reach))
        let longest = Int((Double(max(width, height)) * scale).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest, 1)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high

        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let factor = mode == .fill
            ? max(Double(side) / imageWidth, Double(side) / imageHeight)
            : min(target / imageWidth, target / imageHeight)
        let drawWidth = imageWidth * factor
        let drawHeight = imageHeight * factor
        context.draw(image, in: CGRect(
            x: (Double(side) - drawWidth) / 2,
            y: (Double(side) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        ))

        guard let flat = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination,
            flat,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
#endif
