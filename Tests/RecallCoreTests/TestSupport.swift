import CoreGraphics
import Foundation
import ImageIO
@testable import RecallCore

/// A temporary directory that is removed when the value is deallocated.
final class TempDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recall-tests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        // Restore permissions first so a directory made read-only by a test can be removed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: history.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    var history: URL { url.appendingPathComponent("History", isDirectory: true) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []).sorted()
    }

    func files(key: Data = testKey) -> ClipFiles {
        ClipFiles(directory: history, cipher: ClipCipher(keyData: key))
    }
}

/// A fixed key, so that tests can write files with one value and read them with another.
let testKey = Data(repeating: 7, count: ClipCipher.keyLength)
let otherKey = Data(repeating: 9, count: ClipCipher.keyLength)

func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + seconds)
}

func makeClip(_ text: String, at seconds: TimeInterval = 0, id: UUID = UUID()) -> Clip {
    Clip(id: id, kind: .of(text), text: text, created: date(seconds), used: date(seconds))
}

/// A small picture in the given format. Different shades give different pictures.
func makeImageData(width: Int = 40, height: Int = 30, type: String = "public.png", shade: Int = 120) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: CGFloat(shade) / 255, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 4, y: 4, width: width / 2, height: height / 2))

    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// The size in pixels of image data, or nil if it is not an image.
func pixelSize(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
}

func makeCapturedImage(shade: Int = 120, width: Int = 40, height: Int = 30) -> CapturedImage {
    ImageCodec.capture(makeImageData(width: width, height: height, shade: shade), maxBytes: 10_000_000)!
}

/// A square picture of random pixels, which a PNG cannot shrink.
func makeNoiseImageData(side: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    var pixels = [UInt8](repeating: 255, count: side * side * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let value = generator.next() as UInt64
        pixels[index] = UInt8(truncatingIfNeeded: value)
        pixels[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
        pixels[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
    }
    let context = pixels.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
