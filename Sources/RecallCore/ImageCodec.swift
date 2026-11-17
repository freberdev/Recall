import CryptoKit
import Foundation
import ImageIO

/// An image taken from the clipboard, ready to be stored.
public struct CapturedImage: Equatable, Sendable {
    /// The image as it will be written to disk: PNG or JPEG.
    public var data: Data
    public var info: Clip.ImageInfo
}

/// Turns image data from the clipboard into what Recall stores.
public enum ImageCodec {
    /// The longest side of the picture shown in the history list, in pixels.
    public static let thumbnailSize = 160

    /// Clipboard data larger than this is not even decoded. An uncompressed picture of a
    /// large screen is under a hundred megabytes, and can shrink to a few when stored as PNG.
    public static let maxRawBytes = 256_000_000

    /// PNG and JPEG are kept as they are. Everything else is stored as PNG, which is what an
    /// uncompressed screenshot or a TIFF from another app shrinks best to without loss.
    ///
    /// Nil if the data is not an image, or if what would be stored is larger than `maxBytes`.
    public static func capture(_ raw: Data, maxBytes: Int, maxRawBytes: Int = maxRawBytes) -> CapturedImage? {
        guard !raw.isEmpty, raw.count <= maxRawBytes,
              let source = CGImageSourceCreateWithData(raw as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        // Orientations five to eight are the ones that turn the image on its side.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }

        let format: Clip.ImageFormat
        let data: Data
        switch CGImageSourceGetType(source) as String? {
        case Clip.ImageFormat.png.typeIdentifier:
            (format, data) = (.png, raw)
        case Clip.ImageFormat.jpeg.typeIdentifier:
            (format, data) = (.jpeg, raw)
        default:
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let png = png(from: image)
            else { return nil }
            (format, data) = (.png, png)
        }
        guard data.count <= maxBytes, let thumbnail = thumbnail(from: source) else { return nil }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return CapturedImage(
            data: data,
            info: Clip.ImageInfo(
                format: format, width: width, height: height,
                byteCount: data.count, digest: digest, thumbnail: thumbnail))
    }

    private static func thumbnail(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return png(from: image)
    }

    private static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, Clip.ImageFormat.png.typeIdentifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
