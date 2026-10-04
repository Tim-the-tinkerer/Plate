import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageCodec {
    static let maxSide = 8192
    static let previewMaxSide = 1600

    /// Big-endian + alpha last = RGBA bytes in memory on every Mac.
    /// Load with premultipliedLast. Encode with straight last. Do not flip Y.
    private static let rgbaPremultiplied: UInt32 =
        CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    private static let rgbaStraight: UInt32 =
        CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue

    enum CodecError: LocalizedError {
        case unreadable
        case empty
        case encodeFailed
        case noImage
        case overwrite

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not read that image."
            case .empty: return "That image is empty."
            case .encodeFailed: return "Could not encode the image."
            case .noImage: return "Open an image first."
            case .overwrite: return "Plate will not replace the original. Save a new file."
            }
        }
    }

    static func load(url: URL) throws -> PixelBuffer {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw CodecError.unreadable
        }
        return try buffer(from: source)
    }

    static func load(data: Data) throws -> PixelBuffer {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            throw CodecError.unreadable
        }
        return try buffer(from: source)
    }

    static func load(nsImage: NSImage) throws -> PixelBuffer {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw CodecError.unreadable
        }
        return try fromCGImage(cg)
    }

    static func pngData(_ buffer: PixelBuffer) throws -> Data {
        try encode(buffer, type: .png, quality: nil)
    }

    static func jpegData(_ buffer: PixelBuffer, quality: Double = 0.92) throws -> Data {
        try encode(buffer, type: .jpeg, quality: quality)
    }

    static func write(_ data: Data, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        try data.write(to: url, options: .atomic)
    }

    static func cgImage(_ buffer: PixelBuffer) -> CGImage? {
        guard !buffer.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(buffer.pixelCount * 4)
        for pixel in buffer.pixels {
            bytes.append(pixel.r)
            bytes.append(pixel.g)
            bytes.append(pixel.b)
            bytes.append(pixel.a)
        }
        guard let data = CFDataCreate(nil, bytes, bytes.count),
              let provider = CGDataProvider(data: data)
        else {
            return nil
        }
        return CGImage(
            width: buffer.width,
            height: buffer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: buffer.width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: rgbaStraight),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func nsImage(_ buffer: PixelBuffer) -> NSImage? {
        guard let cg = cgImage(buffer) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: buffer.width, height: buffer.height))
    }

    private static func buffer(from source: CGImageSource) throws -> PixelBuffer {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
        let longSide = max(width, height)
        let needsThumb = orientation != 1 || longSide > maxSide

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let image: CGImage?
        if needsThumb {
            let thumb: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
                kCGImageSourceShouldCache: false,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        guard let image else { throw CodecError.unreadable }
        return try fromCGImage(image)
    }

    static func fromCGImage(_ image: CGImage) throws -> PixelBuffer {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw CodecError.empty }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw CodecError.unreadable }

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = raw.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: rgbaPremultiplied
            ) else {
                return false
            }
            ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CodecError.unreadable }

        var pixels = [Pixel]()
        pixels.reserveCapacity(width * height)
        var i = 0
        while i < raw.count {
            pixels.append(unpremultiply(r: raw[i], g: raw[i + 1], b: raw[i + 2], a: raw[i + 3]))
            i += 4
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    private static func encode(_ buffer: PixelBuffer, type: UTType, quality: Double?) throws -> Data {
        guard let cg = cgImage(buffer) else { throw CodecError.encodeFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw CodecError.encodeFailed
        }
        var props: [CFString: Any] = [:]
        if let quality {
            props[kCGImageDestinationLossyCompressionQuality] = max(0.05, min(1, quality))
        }
        CGImageDestinationAddImage(destination, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CodecError.encodeFailed }
        return data as Data
    }

    private static func unpremultiply(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Pixel {
        if a == 0 { return .clear }
        if a == 255 { return Pixel(r: r, g: g, b: b, a: a) }
        let ia = Int(a)
        return Pixel(
            r: UInt8(min(255, Int(r) * 255 / ia)),
            g: UInt8(min(255, Int(g) * 255 / ia)),
            b: UInt8(min(255, Int(b) * 255 / ia)),
            a: a
        )
    }
}
