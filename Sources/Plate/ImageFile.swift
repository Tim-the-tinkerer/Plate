import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LoadedImage {
    var image: CGImage
    var capped: Bool
}

enum ImageFile {
    static let maxSide = 8192
    static let previewMaxSide = 1600

    private static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue

    enum ImageError: LocalizedError {
        case unreadable
        case empty
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not read that image."
            case .empty: return "That image is empty."
            case .encodeFailed: return "Could not write that image."
            }
        }
    }

    static let openExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "gif", "bmp", "webp",
    ]

    static func load(url: URL) throws -> LoadedImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageError.unreadable
        }
        return try image(from: source)
    }

    static func load(data: Data) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageError.unreadable
        }
        return try image(from: source)
    }

    static func load(nsImage: NSImage) throws -> LoadedImage {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw ImageError.unreadable
        }
        guard let image = normalize(cg) else { throw ImageError.unreadable }
        let long = max(image.width, image.height)
        guard long > maxSide else {
            return LoadedImage(image: image, capped: false)
        }
        return LoadedImage(image: scaled(image, maxSide: maxSide), capped: true)
    }

    static func solid(width: Int, height: Int, color: CaptionColor) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        return draw(width: width, height: height) { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Visual top `band` rows are `top`; the rest is `rest`. Used to pin y-down sampling.
    static func banded(width: Int, height: Int, band: Int, top: CaptionColor, rest: CaptionColor) -> CGImage? {
        guard width > 0, height > 0, band > 0, band < height else { return nil }
        return draw(width: width, height: height) { ctx in
            ctx.setFillColor(rest.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(top.cgColor)
            ctx.fill(CGRect(x: 0, y: height - band, width: width, height: band))
        }
    }

    /// Mat around the photo. An empty mat returns the same image.
    static func expand(_ photo: CGImage, margins: CanvasMargins, maxSide: Int) -> (image: CGImage, contentWidth: Int) {
        if margins.isEmpty {
            return (photo, photo.width)
        }
        let layout = margins.layout(photoWidth: photo.width, photoHeight: photo.height, maxSide: maxSide)
        let drawn = draw(width: layout.width, height: layout.height) { ctx in
            ctx.setFillColor(margins.color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
            ctx.interpolationQuality = .high
            ctx.draw(photo, in: layout.photo)
        }
        return (drawn ?? photo, layout.contentWidth)
    }

    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > maxSide, long > 0 else { return image }
        let scale = Double(maxSide) / Double(long)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        return draw(width: width, height: height) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        } ?? image
    }

    static func pngData(_ image: CGImage) throws -> Data {
        try data(image, jpeg: false, quality: 1)
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.92) throws -> Data {
        try data(image, jpeg: true, quality: quality)
    }

    static func write(_ image: CGImage, to url: URL, jpeg: Bool) throws {
        let bytes = jpeg ? try jpegData(image) : try pngData(image)
        try bytes.write(to: url, options: .atomic)
    }

    static func nsImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        let bytesPerRow = width * 4
        let storage = NSMutableData(length: height * bytesPerRow)
        guard let storage else { return nil }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: storage.mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        body(ctx)
        guard let made = ctx.makeImage() else { return nil }
        return owningCopy(made)
    }

    /// RGBA bytes, row 0 is the visual top. Forces a draw so the layout is known.
    static func rgbaTopDown(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: bitmapInfo
            ) else { return false }
            // This context stores row 0 as the visual top. Drawing upright
            // puts the image's top in that first row. Do not flip.
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    private static func image(from source: CGImageSource) throws -> LoadedImage {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { throw ImageError.empty }
        let capped = max(pixelWidth, pixelHeight) > maxSide
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCache: false,
        ]
        guard let raw = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else {
            throw ImageError.unreadable
        }
        guard let image = normalize(raw) else { throw ImageError.unreadable }
        return LoadedImage(image: image, capped: capped)
    }

    private static func normalize(_ image: CGImage) -> CGImage? {
        draw(width: image.width, height: image.height) { ctx in
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    private static func data(_ image: CGImage, jpeg: Bool, quality: Double) throws -> Data {
        let buffer = NSMutableData()
        let type: CFString = (jpeg ? UTType.jpeg : UTType.png).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(buffer, type, 1, nil) else {
            throw ImageError.encodeFailed
        }
        var props: [CFString: Any] = [:]
        if jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.05, quality))
        }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.encodeFailed }
        return buffer as Data
    }

    /// `makeImage()` can be copy-on-write against the context buffer. Copy the bytes out.
    private static func owningCopy(_ image: CGImage) -> CGImage? {
        guard let providerData = image.dataProvider?.data else { return nil }
        let length = CFDataGetLength(providerData)
        var bytes = Data(count: length)
        let copied = bytes.withUnsafeMutableBytes { dst -> Bool in
            guard let address = dst.baseAddress else { return false }
            CFDataGetBytes(providerData, CFRange(location: 0, length: length), address.assumingMemoryBound(to: UInt8.self))
            return true
        }
        guard copied, let owned = CGDataProvider(data: bytes as CFData) else { return nil }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: space,
            bitmapInfo: image.bitmapInfo,
            provider: owned,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
