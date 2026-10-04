import CoreGraphics
import Foundation

enum PlateLook: String, Codable, CaseIterable, Equatable {
    case none
    case mono
    case sepia
    case warm
    case cool
    case fade
    case punch

    var title: String {
        switch self {
        case .none: return "None"
        case .mono: return "Mono"
        case .sepia: return "Sepia"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .fade: return "Fade"
        case .punch: return "Punch"
        }
    }

    static func parse(_ raw: String) -> PlateLook? {
        let key = raw.lowercased()
        return allCases.first { $0.rawValue == key || $0.title.lowercased() == key }
    }
}

enum PlateOrientation: CaseIterable, Equatable {
    case up
    case upMirrored
    case down
    case downMirrored
    case left
    case leftMirrored
    case right
    case rightMirrored

    var swapsAxes: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored: return true
        default: return false
        }
    }

    /// Visual operation on the already-oriented picture.
    func applying(_ op: OrientOp) -> PlateOrientation {
        let probe = PixelBuffer.probe()
        let visual = Engine.transform(Engine.oriented(probe, self), op)
        return PlateOrientation.allCases.first { Engine.oriented(probe, $0) == visual } ?? .up
    }

    static func from(clockwiseDegrees degrees: Int) -> PlateOrientation? {
        switch normalized(degrees) {
        case 0: return .up
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return nil
        }
    }

    static func normalized(_ degrees: Int) -> Int {
        var d = degrees % 360
        if d < 0 { d += 360 }
        return d
    }
}

enum OrientOp: CaseIterable {
    case rotateCW
    case rotateCCW
    case flipH
    case flipV
}

enum EditorTool: String, CaseIterable, Equatable {
    case adjust
    case crop
    case looks
    case annotate

    var title: String {
        switch self {
        case .adjust: return "Adjust"
        case .crop: return "Crop"
        case .looks: return "Looks"
        case .annotate: return "Annotate"
        }
    }

    var symbol: String {
        switch self {
        case .adjust: return "slider.horizontal.3"
        case .crop: return "crop"
        case .looks: return "camera.filters"
        case .annotate: return "pencil.tip"
        }
    }
}

enum CropAspect: String, CaseIterable, Equatable {
    case free
    case original
    case square
    case threeTwo
    case fourThree
    case sixteenNine

    var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "1:1"
        case .threeTwo: return "3:2"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        }
    }

    /// Pixel width / pixel height. Nil means unconstrained.
    func pixelRatio(imageWidth: Int, imageHeight: Int) -> Double? {
        switch self {
        case .free:
            return nil
        case .original:
            guard imageHeight > 0 else { return nil }
            return Double(imageWidth) / Double(imageHeight)
        case .square:
            return 1
        case .threeTwo:
            return 3.0 / 2.0
        case .fourThree:
            return 4.0 / 3.0
        case .sixteenNine:
            return 16.0 / 9.0
        }
    }
}

struct CropRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    var isFull: Bool { x == 0 && y == 0 && width == 1 && height == 1 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

enum CropHandle: Equatable {
    case move
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
}

enum CropMath {
    static let minimum: Double = 0.02

    static func clamped(_ crop: CropRect) -> CropRect {
        var width = min(1, max(minimum, crop.width))
        var height = min(1, max(minimum, crop.height))
        var x = crop.x
        var y = crop.y
        if x < 0 {
            width += x
            x = 0
        }
        if y < 0 {
            height += y
            y = 0
        }
        width = max(minimum, min(width, 1))
        height = max(minimum, min(height, 1))
        if x + width > 1 { x = 1 - width }
        if y + height > 1 { y = 1 - height }
        x = min(max(0, x), 1 - width)
        y = min(max(0, y), 1 - height)
        return CropRect(x: x, y: y, width: width, height: height)
    }

    static func translated(_ crop: CropRect, dx: Double, dy: Double) -> CropRect {
        var next = crop
        next.x += dx
        next.y += dy
        let width = min(1, max(minimum, next.width))
        let height = min(1, max(minimum, next.height))
        let x = min(max(0, next.x), 1 - width)
        let y = min(max(0, next.y), 1 - height)
        return CropRect(x: x, y: y, width: width, height: height)
    }

    static func applying(_ op: OrientOp, to crop: CropRect) -> CropRect {
        if crop.isFull { return .full }
        switch op {
        case .flipH:
            return CropRect(x: 1 - crop.maxX, y: crop.y, width: crop.width, height: crop.height)
        case .flipV:
            return CropRect(x: crop.x, y: 1 - crop.maxY, width: crop.width, height: crop.height)
        case .rotateCW:
            return CropRect(x: 1 - crop.maxY, y: crop.x, width: crop.height, height: crop.width)
        case .rotateCCW:
            return CropRect(x: crop.y, y: 1 - crop.maxX, width: crop.height, height: crop.width)
        }
    }

    /// Largest centered crop with `ratio` = pixel width / pixel height.
    static func fitted(ratio: Double?, imageWidth: Int, imageHeight: Int) -> CropRect {
        guard let ratio, ratio > 0, imageWidth > 0, imageHeight > 0 else { return .full }
        let imageRatio = Double(imageWidth) / Double(imageHeight)
        if imageRatio > ratio {
            let width = ratio / imageRatio
            return CropRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = imageRatio / ratio
        return CropRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    static func hitTest(point: CGPoint, cropRect: CGRect, slack: CGFloat) -> CropHandle? {
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
        ]
        for (handle, corner) in corners {
            if hypot(point.x - corner.x, point.y - corner.y) <= slack { return handle }
        }
        let edges: [(CropHandle, CGRect)] = [
            (.top, CGRect(x: cropRect.minX, y: cropRect.minY - slack, width: cropRect.width, height: slack * 2)),
            (.bottom, CGRect(x: cropRect.minX, y: cropRect.maxY - slack, width: cropRect.width, height: slack * 2)),
            (.left, CGRect(x: cropRect.minX - slack, y: cropRect.minY, width: slack * 2, height: cropRect.height)),
            (.right, CGRect(x: cropRect.maxX - slack, y: cropRect.minY, width: slack * 2, height: cropRect.height)),
        ]
        for (handle, rect) in edges where rect.contains(point) {
            return handle
        }
        if cropRect.insetBy(dx: slack, dy: slack).contains(point) { return .move }
        return nil
    }

    static func resized(
        start: CropRect,
        handle: CropHandle,
        dx: Double,
        dy: Double,
        pixelRatio: Double?,
        imageWidth: Int,
        imageHeight: Int
    ) -> CropRect {
        if handle == .move {
            return translated(start, dx: dx, dy: dy)
        }

        var width = start.width
        var height = start.height
        if isHorizontal(handle) {
            width = handle == .left || handle == .topLeft || handle == .bottomLeft
                ? start.width - dx
                : start.width + dx
        }
        if isVertical(handle) {
            height = handle == .top || handle == .topLeft || handle == .topRight
                ? start.height - dy
                : start.height + dy
        }

        let normRatio: Double?
        if let pixelRatio, pixelRatio > 0, imageWidth > 0, imageHeight > 0 {
            normRatio = pixelRatio * Double(imageHeight) / Double(imageWidth)
        } else {
            normRatio = nil
        }

        if let normRatio, normRatio > 0 {
            if isHorizontal(handle), !isVertical(handle) {
                height = width / normRatio
            } else if isVertical(handle), !isHorizontal(handle) {
                width = height * normRatio
            } else if abs(dx) >= abs(dy) {
                height = width / normRatio
            } else {
                width = height * normRatio
            }
        }

        width = max(minimum, width)
        height = max(minimum, height)

        if let normRatio, normRatio > 0 {
            return clampKeepingAspect(
                start: start,
                handle: handle,
                width: width,
                height: height,
                normRatio: normRatio
            )
        }
        return clamped(anchored(start: start, handle: handle, width: width, height: height))
    }

    static func pixelBounds(crop: CropRect, width: Int, height: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        guard width > 0, height > 0 else { return (0, 0, 0, 0) }
        if crop.isFull { return (0, 0, width, height) }
        let x0 = clampInt(Int((crop.x * Double(width)).rounded(.down)), 0, width - 1)
        let y0 = clampInt(Int((crop.y * Double(height)).rounded(.down)), 0, height - 1)
        let x1 = min(width, max(x0 + 1, Int(((crop.x + crop.width) * Double(width)).rounded(.up))))
        let y1 = min(height, max(y0 + 1, Int(((crop.y + crop.height) * Double(height)).rounded(.up))))
        return (x0, y0, x1 - x0, y1 - y0)
    }

    private static func anchored(start: CropRect, handle: CropHandle, width: Double, height: Double) -> CropRect {
        let x: Double
        if handle == .left || handle == .topLeft || handle == .bottomLeft {
            x = start.maxX - width
        } else {
            x = start.x
        }
        let y: Double
        if handle == .top || handle == .topLeft || handle == .topRight {
            y = start.maxY - height
        } else {
            y = start.y
        }
        return CropRect(x: x, y: y, width: width, height: height)
    }

    private static func clampKeepingAspect(
        start: CropRect,
        handle: CropHandle,
        width: Double,
        height: Double,
        normRatio: Double
    ) -> CropRect {
        var width = width
        var height = height
        let maxW: Double = (handle == .left || handle == .topLeft || handle == .bottomLeft) ? start.maxX : (1 - start.x)
        let maxH: Double = (handle == .top || handle == .topLeft || handle == .topRight) ? start.maxY : (1 - start.y)
        width = min(width, max(minimum, maxW))
        height = min(height, max(minimum, maxH))
        if height <= 0 || width / height > normRatio {
            width = height * normRatio
        } else {
            height = width / normRatio
        }
        width = max(minimum, width)
        height = max(minimum, height)
        return clamped(anchored(start: start, handle: handle, width: width, height: height))
    }

    private static func isHorizontal(_ handle: CropHandle) -> Bool {
        switch handle {
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    private static func isVertical(_ handle: CropHandle) -> Bool {
        switch handle {
        case .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }

    private static func clampInt(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(hi, max(lo, value))
    }
}

/// A small clockwise turn after the quarter-turns. Zero is exact: the engine does not resample.
enum StraightenMath {
    static let limit = 45.0

    static func clamped(_ degrees: Double) -> Double {
        min(limit, max(-limit, degrees))
    }

    /// Continuous width and height of the largest centered upright rectangle inside the rotated photo.
    static func inscribed(width: Double, height: Double, degrees: Double) -> (width: Double, height: Double) {
        let theta = abs(degrees) * .pi / 180
        if theta < 1e-8 || width <= 0 || height <= 0 { return (width, height) }
        let s = sin(theta)
        let c = cos(theta)
        let longer = width >= height
        let sideLong = longer ? width : height
        let sideShort = longer ? height : width
        if sideShort <= 2 * s * c * sideLong || abs(s - c) < 1e-10 {
            let x = 0.5 * sideShort
            if longer { return (x / s, x / c) }
            return (x / c, x / s)
        }
        let cos2 = c * c - s * s
        return ((width * c - height * s) / cos2, (height * c - width * s) / cos2)
    }

    /// Pixel size of that rectangle. Rounded down so the sample stays inside the photo.
    static func pixelSize(width: Int, height: Int, degrees: Double) -> (width: Int, height: Int) {
        let size = inscribed(width: Double(width), height: Double(height), degrees: degrees)
        return (max(1, Int(size.width.rounded(.down))), max(1, Int(size.height.rounded(.down))))
    }

    /// Where an inscribed-frame point sits in the oriented photo, before the small turn.
    static func orientedPixel(
        _ point: NormPoint,
        degrees: Double,
        width: Int,
        height: Int
    ) -> (x: Double, y: Double) {
        let frame = inscribed(width: Double(width), height: Double(height), degrees: degrees)
        let radians = degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let rx = point.x * frame.width - frame.width / 2
        let ry = point.y * frame.height - frame.height / 2
        let dx = rx * cosA + ry * sinA
        let dy = -rx * sinA + ry * cosA
        return (dx + Double(width) / 2, dy + Double(height) / 2)
    }

    /// Inscribed-frame point for a pixel in the oriented photo. Y grows downward.
    static func inscribedPoint(
        x: Double,
        y: Double,
        degrees: Double,
        width: Int,
        height: Int
    ) -> NormPoint {
        let frame = inscribed(width: Double(width), height: Double(height), degrees: degrees)
        let radians = degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let dx = x - Double(width) / 2
        let dy = y - Double(height) / 2
        let rx = dx * cosA - dy * sinA
        let ry = dx * sinA + dy * cosA
        guard frame.width > 0, frame.height > 0 else { return NormPoint(x: 0.5, y: 0.5) }
        return NormPoint(x: (rx + frame.width / 2) / frame.width, y: (ry + frame.height / 2) / frame.height)
    }

    static func remap(
        _ point: NormPoint,
        from oldDegrees: Double,
        to newDegrees: Double,
        width: Int,
        height: Int
    ) -> NormPoint {
        let pixel = orientedPixel(point, degrees: oldDegrees, width: width, height: height)
        return inscribedPoint(x: pixel.x, y: pixel.y, degrees: newDegrees, width: width, height: height)
    }

    static func remap(
        _ annotation: Annotation,
        from oldDegrees: Double,
        to newDegrees: Double,
        width: Int,
        height: Int
    ) -> Annotation {
        var copy = annotation
        copy.points = annotation.points.map {
            remap($0, from: oldDegrees, to: newDegrees, width: width, height: height)
        }
        return copy
    }
}

struct EditState: Equatable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var saturation: Double = 0
    var temperature: Double = 0
    var tint: Double = 0
    var sharpness: Double = 0
    var vignette: Double = 0
    var look: PlateLook = .none
    var orientation: PlateOrientation = .up
    /// Degrees clockwise, after the quarter-turns. Zero leaves the pixels untouched.
    var straighten: Double = 0
    var crop: CropRect = .full
    var cropAspect: CropAspect = .free
    /// Marks in the frame after quarter-turns and straighten, before the crop. (0, 0) is the top left.
    var annotations: [Annotation] = []

    var needsGrade: Bool {
        exposure != 0 || brightness != 0 || contrast != 0 || highlights != 0 || shadows != 0
            || saturation != 0 || temperature != 0 || tint != 0 || vignette != 0 || look != .none
    }

    func applying(_ op: OrientOp) -> EditState {
        var copy = self
        copy.orientation = orientation.applying(op)
        copy.crop = CropMath.applying(op, to: crop)
        copy.annotations = annotations.map { AnnotationGeometry.applying(op, to: $0) }
        return copy
    }
}

/// One named set of the sliders and the look. Crop, turns, straighten, and marks stay with the photo.
struct PlateGrade: Codable, Equatable {
    var name: String
    var exposure: Double
    var brightness: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var saturation: Double
    var temperature: Double
    var tint: Double
    var sharpness: Double
    var vignette: Double
    var look: PlateLook

    static let defaultsKey = "com.tim.plate.savedGrade"

    static func capture(_ state: EditState, name: String) -> PlateGrade {
        PlateGrade(
            name: name,
            exposure: state.exposure,
            brightness: state.brightness,
            contrast: state.contrast,
            highlights: state.highlights,
            shadows: state.shadows,
            saturation: state.saturation,
            temperature: state.temperature,
            tint: state.tint,
            sharpness: state.sharpness,
            vignette: state.vignette,
            look: state.look
        )
    }

    func applied(to state: EditState) -> EditState {
        var copy = state
        copy.exposure = exposure
        copy.brightness = brightness
        copy.contrast = contrast
        copy.highlights = highlights
        copy.shadows = shadows
        copy.saturation = saturation
        copy.temperature = temperature
        copy.tint = tint
        copy.sharpness = sharpness
        copy.vignette = vignette
        copy.look = look
        return copy
    }

    static func load(from defaults: UserDefaults = .standard) -> PlateGrade? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PlateGrade.self, from: data)
    }

    func store(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

struct EditHistory {
    private(set) var states: [EditState]
    private(set) var index: Int
    private let limit: Int

    init(limit: Int = 50) {
        states = [EditState()]
        index = 0
        self.limit = max(2, limit)
    }

    var current: EditState { states[index] }
    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index + 1 < states.count }

    mutating func reset(to state: EditState = EditState()) {
        states = [state]
        index = 0
    }

    mutating func push(_ state: EditState) {
        if state == states[index] { return }
        if index + 1 < states.count {
            states.removeLast(states.count - index - 1)
        }
        states.append(state)
        index = states.count - 1
        if states.count > limit {
            let extra = states.count - limit
            states.removeFirst(extra)
            index -= extra
        }
    }

    @discardableResult
    mutating func undo() -> EditState? {
        guard canUndo else { return nil }
        index -= 1
        return current
    }

    @discardableResult
    mutating func redo() -> EditState? {
        guard canRedo else { return nil }
        index += 1
        return current
    }
}

enum ExportNaming {
    static func suggestedURL(for source: URL?, jpeg: Bool) -> URL {
        let ext = jpeg ? "jpg" : "png"
        let folder = source?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let stem: String
        if let source {
            let base = source.deletingPathExtension().lastPathComponent
            stem = base.hasSuffix("-edited") ? base : "\(base)-edited"
        } else {
            stem = "Plate-edited"
        }
        var candidate = folder.appendingPathComponent("\(stem).\(ext)")
        if overwritesSource(candidate, source: source) {
            candidate = folder.appendingPathComponent("\(stem)-copy.\(ext)")
        }
        return candidate
    }

    static func overwritesSource(_ output: URL, source: URL?) -> Bool {
        guard let source else { return false }
        let out = output.standardizedFileURL.resolvingSymlinksInPath().path
        let src = source.standardizedFileURL.resolvingSymlinksInPath().path
        return out == src
    }
}
