import Foundation

enum Engine {
    /// Orient, then straighten, then crop, then grade, then sharpen.
    /// Marks burn in only when `bakeAnnotations` is set. Save and Copy do that.
    /// The live preview leaves them off so the screen can draw the same marks on top.
    /// A default edit returns the source pixels unchanged, including values a tone curve would round.
    /// Straighten is skipped at 0 degrees so that path stays exact.
    static func render(
        _ source: PixelBuffer,
        state: EditState,
        applyCrop: Bool,
        bakeAnnotations: Bool = false
    ) -> PixelBuffer {
        guard !source.isEmpty else { return source }
        var image = oriented(source, state.orientation)
        if abs(state.straighten) > 1e-8 {
            image = straightened(image, degrees: state.straighten)
        }
        if applyCrop, !state.crop.isFull {
            image = cropped(image, state.crop)
        }
        if state.needsGrade {
            image = graded(image, state)
        }
        if state.sharpness > 0 {
            image = sharpened(image, amount: Float(state.sharpness))
        }
        if bakeAnnotations, !state.annotations.isEmpty {
            let crop: CropRect = applyCrop ? state.crop : .full
            image = AnnotationDrawing.burn(image, annotations: state.annotations, crop: crop)
        }
        return image
    }

    static func outputSize(source: PixelBuffer, state: EditState) -> (width: Int, height: Int) {
        let frame = frameSize(source: source, orientation: state.orientation, straighten: state.straighten)
        let bounds = CropMath.pixelBounds(crop: state.crop, width: frame.width, height: frame.height)
        return (bounds.w, bounds.h)
    }

    /// Size of the picture the crop is drawn on: quarter-turns, then the upright frame inside a straighten.
    static func frameSize(
        source: PixelBuffer,
        orientation: PlateOrientation,
        straighten: Double
    ) -> (width: Int, height: Int) {
        let orientedSize = size(of: source, orientation: orientation)
        return StraightenMath.pixelSize(
            width: orientedSize.width,
            height: orientedSize.height,
            degrees: straighten
        )
    }

    static func orientedSize(of source: PixelBuffer, orientation: PlateOrientation) -> (width: Int, height: Int) {
        size(of: source, orientation: orientation)
    }

    static func downscale(_ source: PixelBuffer, maxSide: Int) -> PixelBuffer {
        let longSide = max(source.width, source.height)
        guard longSide > maxSide, maxSide >= 1, !source.isEmpty else { return source }
        let scale = Double(maxSide) / Double(longSide)
        let width = max(1, Int((Double(source.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(source.height) * scale).rounded(.down)))
        var pixels = [Pixel]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let y0 = y * source.height / height
            let y1 = max(y0 + 1, (y + 1) * source.height / height)
            for x in 0..<width {
                let x0 = x * source.width / width
                let x1 = max(x0 + 1, (x + 1) * source.width / width)
                var r = 0, g = 0, b = 0, a = 0, n = 0
                for yy in y0..<y1 {
                    let row = yy * source.width
                    for xx in x0..<x1 {
                        let p = source.pixels[row + xx]
                        r += Int(p.r)
                        g += Int(p.g)
                        b += Int(p.b)
                        a += Int(p.a)
                        n += 1
                    }
                }
                pixels.append(Pixel(
                    r: UInt8(r / n),
                    g: UInt8(g / n),
                    b: UInt8(b / n),
                    a: UInt8(a / n)
                ))
            }
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    static func centerSquare(_ source: PixelBuffer, side: Int) -> PixelBuffer {
        guard !source.isEmpty else { return source }
        let sideSrc = min(source.width, source.height)
        let x0 = (source.width - sideSrc) / 2
        let y0 = (source.height - sideSrc) / 2
        var pixels = [Pixel]()
        pixels.reserveCapacity(sideSrc * sideSrc)
        for y in 0..<sideSrc {
            let row = (y0 + y) * source.width
            for x in 0..<sideSrc {
                pixels.append(source.pixels[row + x0 + x])
            }
        }
        return downscale(PixelBuffer(width: sideSrc, height: sideSrc, pixels: pixels), maxSide: max(1, side))
    }

    static func lumaHistogram(_ source: PixelBuffer) -> [Int] {
        var bins = [Int](repeating: 0, count: 256)
        for pixel in source.pixels where pixel.a > 0 {
            let y = (77 * Int(pixel.r) + 150 * Int(pixel.g) + 29 * Int(pixel.b)) >> 8
            bins[min(255, y)] += 1
        }
        return bins
    }

    static func oriented(_ source: PixelBuffer, _ orientation: PlateOrientation) -> PixelBuffer {
        switch orientation {
        case .up:
            return source
        case .upMirrored:
            return flipH(source)
        case .down:
            return rotate180(source)
        case .downMirrored:
            return flipV(source)
        case .right:
            return rotate90CW(source)
        case .left:
            return rotate90CCW(source)
        case .rightMirrored:
            return flipH(rotate90CW(source))
        case .leftMirrored:
            return flipH(rotate90CCW(source))
        }
    }

    static func transform(_ source: PixelBuffer, _ op: OrientOp) -> PixelBuffer {
        switch op {
        case .rotateCW: return rotate90CW(source)
        case .rotateCCW: return rotate90CCW(source)
        case .flipH: return flipH(source)
        case .flipV: return flipV(source)
        }
    }

    /// Clockwise by `degrees`. The result is the largest upright rectangle that stays inside the photo.
    static func straightened(_ source: PixelBuffer, degrees: Double) -> PixelBuffer {
        if abs(degrees) < 1e-8 || source.isEmpty { return source }
        let size = StraightenMath.pixelSize(width: source.width, height: source.height, degrees: degrees)
        if size.width == source.width, size.height == source.height { return source }
        let radians = degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let w = Double(size.width)
        let h = Double(size.height)
        let sourceWidth = Double(source.width)
        let sourceHeight = Double(source.height)
        var pixels = [Pixel](repeating: .clear, count: size.width * size.height)
        for y in 0..<size.height {
            let ry = (Double(y) + 0.5) - h / 2
            for x in 0..<size.width {
                let rx = (Double(x) + 0.5) - w / 2
                let dx = rx * cosA + ry * sinA
                let dy = -rx * sinA + ry * cosA
                pixels[y * size.width + x] = sample(source, x: dx + sourceWidth / 2, y: dy + sourceHeight / 2)
            }
        }
        return PixelBuffer(width: size.width, height: size.height, pixels: pixels)
    }

    static func cropped(_ source: PixelBuffer, _ crop: CropRect) -> PixelBuffer {
        let bounds = CropMath.pixelBounds(crop: crop, width: source.width, height: source.height)
        if bounds.x == 0, bounds.y == 0, bounds.w == source.width, bounds.h == source.height {
            return source
        }
        var pixels = [Pixel]()
        pixels.reserveCapacity(bounds.w * bounds.h)
        for y in 0..<bounds.h {
            let row = (bounds.y + y) * source.width + bounds.x
            pixels.append(contentsOf: source.pixels[row..<(row + bounds.w)])
        }
        return PixelBuffer(width: bounds.w, height: bounds.h, pixels: pixels)
    }

    // MARK: - Geometry

    static func flipH(_ source: PixelBuffer) -> PixelBuffer {
        let width = source.width
        let height = source.height
        var pixels = [Pixel](repeating: .clear, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                pixels[row + x] = source.pixels[row + (width - 1 - x)]
            }
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    static func flipV(_ source: PixelBuffer) -> PixelBuffer {
        let width = source.width
        let height = source.height
        var pixels = [Pixel](repeating: .clear, count: width * height)
        for y in 0..<height {
            let src = (height - 1 - y) * width
            let dst = y * width
            pixels.replaceSubrange(dst..<(dst + width), with: source.pixels[src..<(src + width)])
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    static func rotate180(_ source: PixelBuffer) -> PixelBuffer {
        flipH(flipV(source))
    }

    static func rotate90CW(_ source: PixelBuffer) -> PixelBuffer {
        let width = source.width
        let height = source.height
        let newWidth = height
        let newHeight = width
        var pixels = [Pixel](repeating: .clear, count: newWidth * newHeight)
        for y in 0..<height {
            for x in 0..<width {
                let destX = height - 1 - y
                let destY = x
                pixels[destY * newWidth + destX] = source.pixels[y * width + x]
            }
        }
        return PixelBuffer(width: newWidth, height: newHeight, pixels: pixels)
    }

    static func rotate90CCW(_ source: PixelBuffer) -> PixelBuffer {
        let width = source.width
        let height = source.height
        let newWidth = height
        let newHeight = width
        var pixels = [Pixel](repeating: .clear, count: newWidth * newHeight)
        for y in 0..<height {
            for x in 0..<width {
                let destX = y
                let destY = width - 1 - x
                pixels[destY * newWidth + destX] = source.pixels[y * width + x]
            }
        }
        return PixelBuffer(width: newWidth, height: newHeight, pixels: pixels)
    }

    private static func sample(_ source: PixelBuffer, x: Double, y: Double) -> Pixel {
        let width = source.width
        let height = source.height
        let px = min(max(0, x - 0.5), Double(width - 1))
        let py = min(max(0, y - 0.5), Double(height - 1))
        let x0 = min(max(0, Int(px)), width - 1)
        let y0 = min(max(0, Int(py)), height - 1)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = px - Double(x0)
        let ty = py - Double(y0)
        let p00 = source.pixels[y0 * width + x0]
        let p10 = source.pixels[y0 * width + x1]
        let p01 = source.pixels[y1 * width + x0]
        let p11 = source.pixels[y1 * width + x1]
        func mix(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt8 {
            let top = Double(a) + (Double(b) - Double(a)) * tx
            let bottom = Double(c) + (Double(d) - Double(c)) * tx
            let value = top + (bottom - top) * ty
            return UInt8(min(255, max(0, value.rounded())))
        }
        return Pixel(
            r: mix(p00.r, p10.r, p01.r, p11.r),
            g: mix(p00.g, p10.g, p01.g, p11.g),
            b: mix(p00.b, p10.b, p01.b, p11.b),
            a: mix(p00.a, p10.a, p01.a, p11.a)
        )
    }

    // MARK: - Grade

    static func graded(_ source: PixelBuffer, _ state: EditState) -> PixelBuffer {
        let width = source.width
        let height = source.height
        let count = width * height
        var pixels = [Pixel](repeating: .clear, count: count)

        let gain = powf(2, Float(state.exposure))
        let lift = Float(state.brightness) * 0.12
        let warmth = Float(state.temperature)
        let tint = Float(state.tint)
        let contrast = powf(2, Float(state.contrast))
        let highlights = Float(state.highlights)
        let shadows = Float(state.shadows)
        let saturation = Float(1 + state.saturation)
        let vignette = Float(max(0, state.vignette))
        let look = state.look
        let pivot: Float = 0.18

        let src = source.pixels
        for i in 0..<count {
            let p = src[i]
            if p.a == 0 {
                pixels[i] = .clear
                continue
            }
            var r = Tone.toLinear[Int(p.r)]
            var g = Tone.toLinear[Int(p.g)]
            var b = Tone.toLinear[Int(p.b)]

            r *= gain
            g *= gain
            b *= gain

            r += lift
            g += lift
            b += lift

            r *= 1 + warmth * 0.28
            b *= 1 - warmth * 0.28
            g *= 1 - tint * 0.22
            r *= 1 + tint * 0.08
            b *= 1 + tint * 0.08

            r = (r - pivot) * contrast + pivot
            g = (g - pivot) * contrast + pivot
            b = (b - pivot) * contrast + pivot

            var y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if highlights != 0 {
                let w = smoothstep(0.35, 0.95, y)
                let scale = 1 + highlights * 0.55 * w
                r *= scale
                g *= scale
                b *= scale
                y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            if shadows != 0 {
                let w = 1 - smoothstep(0.05, 0.45, y)
                let shadowLift = shadows * 0.28 * w
                r += shadowLift
                g += shadowLift
                b += shadowLift
                y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            }

            let sat = max(0, saturation)
            r = y + (r - y) * sat
            g = y + (g - y) * sat
            b = y + (b - y) * sat

            apply(look, r: &r, g: &g, b: &b)

            if vignette > 0, width > 0, height > 0 {
                let x = i % width
                let yy = i / width
                let nx = (Float(x) + 0.5) / Float(width) - 0.5
                let ny = (Float(yy) + 0.5) / Float(height) - 0.5
                let dist = sqrt(nx * nx + ny * ny) / 0.70710678
                let falloff = smoothstep(0.45, 1, dist)
                let factor = 1 - vignette * falloff * 0.85
                r *= factor
                g *= factor
                b *= factor
            }

            pixels[i] = Pixel(r: Tone.encode(r), g: Tone.encode(g), b: Tone.encode(b), a: p.a)
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    static func sharpened(_ source: PixelBuffer, amount: Float) -> PixelBuffer {
        let width = source.width
        let height = source.height
        guard amount > 0, width >= 3, height >= 3 else { return source }
        var pixels = source.pixels
        let src = source.pixels
        let strength = amount * 1.4
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var rs = 0, gs = 0, bs = 0
                for ky in -1...1 {
                    let row = (y + ky) * width
                    for kx in -1...1 {
                        let p = src[row + x + kx]
                        rs += Int(p.r)
                        gs += Int(p.g)
                        bs += Int(p.b)
                    }
                }
                let p = src[y * width + x]
                let nr = clampByte(Int(p.r) + Int((Float(Int(p.r) - rs / 9) * strength).rounded()))
                let ng = clampByte(Int(p.g) + Int((Float(Int(p.g) - gs / 9) * strength).rounded()))
                let nb = clampByte(Int(p.b) + Int((Float(Int(p.b) - bs / 9) * strength).rounded()))
                pixels[y * width + x] = Pixel(r: nr, g: ng, b: nb, a: p.a)
            }
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    private static func apply(_ look: PlateLook, r: inout Float, g: inout Float, b: inout Float) {
        switch look {
        case .none:
            break
        case .mono:
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = y
            g = y
            b = y
        case .sepia:
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = y * 1.18
            g = y * 0.98
            b = y * 0.72
        case .warm:
            r *= 1.12
            b *= 0.88
        case .cool:
            r *= 0.90
            b *= 1.14
        case .fade:
            r = r * 0.86 + 0.06
            g = g * 0.86 + 0.06
            b = b * 0.86 + 0.055
        case .punch:
            let pivot: Float = 0.18
            r = (r - pivot) * 1.25 + pivot
            g = (g - pivot) * 1.25 + pivot
            b = (b - pivot) * 1.25 + pivot
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            r = y + (r - y) * 1.2
            g = y + (g - y) * 1.2
            b = y + (b - y) * 1.2
        }
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func clampByte(_ value: Int) -> UInt8 {
        UInt8(min(255, max(0, value)))
    }

    private static func size(of source: PixelBuffer, orientation: PlateOrientation) -> (width: Int, height: Int) {
        orientation.swapsAxes ? (source.height, source.width) : (source.width, source.height)
    }
}

enum Tone {
    static let toLinear: [Float] = (0...255).map { channel in
        let c = Float(channel) / 255
        if c <= 0.04045 { return c / 12.92 }
        return powf((c + 0.055) / 1.055, 2.4)
    }

    static func encode(_ linear: Float) -> UInt8 {
        let c = min(1, max(0, linear))
        let index = Int((c * Float(tableCount - 1)).rounded())
        return fromLinear[index]
    }

    private static let tableCount = 4096
    private static let fromLinear: [UInt8] = (0..<tableCount).map { i in
        let c = Float(i) / Float(tableCount - 1)
        let encoded: Float
        if c <= 0.0031308 {
            encoded = c * 12.92
        } else {
            encoded = 1.055 * powf(c, 1 / 2.4) - 0.055
        }
        return UInt8(min(255, max(0, Int((encoded * 255).rounded()))))
    }
}
