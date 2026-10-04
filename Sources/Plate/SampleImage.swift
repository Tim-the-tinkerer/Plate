import CoreGraphics
import Foundation

enum SampleImage {
    /// A small still scene with a gray ramp and color chips, so the sliders have something to push.
    static func make() -> PixelBuffer {
        let width = 960
        let height = 640
        var pixels = [Pixel](repeating: .rgb(0, 0, 0), count: width * height)
        for y in 0..<height {
            let ny = Float(y) / Float(height - 1)
            for x in 0..<width {
                let nx = Float(x) / Float(width - 1)
                var r = UInt8(clamping: Int(48 + (1 - ny) * 40 + nx * 20))
                var g = UInt8(clamping: Int(110 + (1 - ny) * 70))
                var b = UInt8(clamping: Int(176 + (1 - ny) * 50))

                let dx = (Float(x) - 0.74 * Float(width)) / Float(height)
                let dy = (Float(y) - 0.30 * Float(height)) / Float(height)
                let sun = dx * dx + dy * dy
                if sun < 0.012 {
                    r = 255
                    g = 196
                    b = 92
                } else if sun < 0.020 {
                    r = 255
                    g = 220
                    b = 150
                }

                if ny > 0.62 {
                    let t = (ny - 0.62) / 0.38
                    let hill = sin(nx * 9.2) * 0.015
                    if ny > 0.62 + hill {
                        r = UInt8(clamping: Int(86 + t * 48))
                        g = UInt8(clamping: Int(122 - t * 36))
                        b = UInt8(clamping: Int(78 - t * 20))
                    }
                }

                pixels[y * width + x] = .rgb(r, g, b)
            }
        }

        let chips: [(CGFloat, UInt8, UInt8, UInt8)] = [
            (0.08, 196, 54, 42),
            (0.18, 42, 150, 78),
            (0.28, 42, 86, 186),
            (0.38, 214, 168, 48),
            (0.48, 150, 64, 168),
        ]
        for (origin, cr, cg, cb) in chips {
            let x0 = Int(origin * CGFloat(width))
            fill(&pixels, width: width, rectX: x0, rectY: 250, w: 72, h: 96, pixel: .rgb(cr, cg, cb))
        }

        for x in 0..<width {
            let v = UInt8((Float(x) / Float(width - 1) * 255).rounded())
            for y in (height - 48)..<height {
                pixels[y * width + x] = .rgb(v, v, v)
            }
        }

        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    private static func fill(
        _ pixels: inout [Pixel],
        width: Int,
        rectX: Int,
        rectY: Int,
        w: Int,
        h: Int,
        pixel: Pixel
    ) {
        let height = pixels.count / width
        for y in rectY..<min(height, rectY + h) {
            for x in rectX..<min(width, rectX + w) {
                pixels[y * width + x] = pixel
            }
        }
    }
}
