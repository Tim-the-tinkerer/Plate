import Foundation

struct Pixel: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let clear = Pixel(r: 0, g: 0, b: 0, a: 0)

    static func rgb(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> Pixel {
        Pixel(r: r, g: g, b: b, a: a)
    }
}

struct PixelBuffer: Equatable {
    var width: Int
    var height: Int
    var pixels: [Pixel]

    var isEmpty: Bool { width <= 0 || height <= 0 || pixels.count != width * height }
    var pixelCount: Int { width * height }

    func pixel(x: Int, y: Int) -> Pixel {
        pixels[y * width + x]
    }

    mutating func setPixel(x: Int, y: Int, _ pixel: Pixel) {
        pixels[y * width + x] = pixel
    }

    static func filled(width: Int, height: Int, pixel: Pixel) -> PixelBuffer {
        PixelBuffer(
            width: width,
            height: height,
            pixels: Array(repeating: pixel, count: width * height)
        )
    }

    /// 2×3 unique pixels. Each orientation places them in a different slot.
    static func probe() -> PixelBuffer {
        PixelBuffer(
            width: 2,
            height: 3,
            pixels: [
                .rgb(10, 0, 0), .rgb(20, 0, 0),
                .rgb(30, 0, 0), .rgb(40, 0, 0),
                .rgb(50, 0, 0), .rgb(60, 0, 0),
            ]
        )
    }
}
