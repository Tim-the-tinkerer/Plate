import AppKit
import CoreGraphics
import CoreText
import SwiftUI

struct NormPoint: Equatable {
    var x: Double
    var y: Double
}

enum AnnotationKind: Equatable {
    case pen
    case marker
    case line
    case arrow
    case rectangle
    case ellipse
    case text
}

enum AnnotationColor: String, CaseIterable, Equatable {
    case amber
    case white
    case black
    case red
    case yellow
    case green
    case blue

    var title: String {
        switch self {
        case .amber: return "Amber"
        case .white: return "White"
        case .black: return "Black"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        }
    }

    var components: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .amber: return (0.93, 0.62, 0.28)
        case .white: return (1, 1, 1)
        case .black: return (0.08, 0.07, 0.06)
        case .red: return (0.86, 0.23, 0.18)
        case .yellow: return (0.95, 0.82, 0.22)
        case .green: return (0.30, 0.72, 0.38)
        case .blue: return (0.28, 0.50, 0.90)
        }
    }

    var swiftColor: Color {
        let (r, g, b) = components
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }
}

struct Annotation: Equatable, Identifiable {
    var id: UUID
    var kind: AnnotationKind
    var color: AnnotationColor
    var weight: Double
    var points: [NormPoint]
    var text: String

    static let defaultStroke = 0.008
    static let defaultMarker = 0.028
    static let defaultText = 0.05
}

enum AnnotateTool: String, CaseIterable, Equatable {
    case select
    case pen
    case marker
    case line
    case arrow
    case rectangle
    case ellipse
    case text

    var title: String {
        switch self {
        case .select: return "Select"
        case .pen: return "Pen"
        case .marker: return "Marker"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Box"
        case .ellipse: return "Oval"
        case .text: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }

    var kind: AnnotationKind? {
        switch self {
        case .select: return nil
        case .pen: return .pen
        case .marker: return .marker
        case .line: return .line
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .text: return .text
        }
    }
}

enum BoxCorner: Equatable {
    /// Corners of the visual box. `minMin` is the top left, because y grows downward.
    case minMin, maxMin, minMax, maxMax
}

enum AnnotationHandle: Equatable {
    case point(Int)
    case boxCorner(BoxCorner)
}

enum AnnotationGeometry {
    static func transformed(_ point: NormPoint, _ op: OrientOp) -> NormPoint {
        switch op {
        case .rotateCW:
            return NormPoint(x: 1 - point.y, y: point.x)
        case .rotateCCW:
            return NormPoint(x: point.y, y: 1 - point.x)
        case .flipH:
            return NormPoint(x: 1 - point.x, y: point.y)
        case .flipV:
            return NormPoint(x: point.x, y: 1 - point.y)
        }
    }

    static func applying(_ op: OrientOp, to annotation: Annotation) -> Annotation {
        var copy = annotation
        copy.points = annotation.points.map { transformed($0, op) }
        return copy
    }

    static func translated(_ annotation: Annotation, dx: Double, dy: Double) -> Annotation {
        var copy = annotation
        copy.points = annotation.points.map { NormPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }

    /// Move one stored point, or one corner of a box or oval. The opposite corner stays put.
    static func reshaped(_ annotation: Annotation, handle: AnnotationHandle, to point: NormPoint) -> Annotation {
        var copy = annotation
        switch handle {
        case .point(let index):
            guard copy.points.indices.contains(index) else { return annotation }
            copy.points[index] = point
        case .boxCorner(let corner):
            guard copy.points.count >= 2 else { return annotation }
            let a = copy.points[0]
            let b = copy.points[1]
            let minX = min(a.x, b.x)
            let maxX = max(a.x, b.x)
            let minY = min(a.y, b.y)
            let maxY = max(a.y, b.y)
            let anchor: NormPoint
            switch corner {
            case .minMin:
                anchor = NormPoint(x: maxX, y: maxY)
            case .maxMin:
                anchor = NormPoint(x: minX, y: maxY)
            case .minMax:
                anchor = NormPoint(x: maxX, y: minY)
            case .maxMax:
                anchor = NormPoint(x: minX, y: minY)
            }
            copy.points = [anchor, point]
        }
        return copy
    }

    static func isSubstantial(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .pen, .marker:
            return annotation.points.count >= 2
        case .line, .arrow:
            guard annotation.points.count >= 2 else { return false }
            let a = annotation.points[0]
            let b = annotation.points[1]
            return hypot(a.x - b.x, a.y - b.y) >= 0.004
        case .rectangle, .ellipse:
            guard annotation.points.count >= 2 else { return false }
            let a = annotation.points[0]
            let b = annotation.points[1]
            return abs(a.x - b.x) >= 0.004 || abs(a.y - b.y) >= 0.004
        case .text:
            return annotation.points.count >= 1
                && !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Full-frame unit point into the rectangle that displays `crop`. Y grows downward.
    static func placed(_ point: NormPoint, in rect: CGRect, crop: CropRect) -> CGPoint {
        let spanX = crop.width == 0 ? 1 : crop.width
        let spanY = crop.height == 0 ? 1 : crop.height
        let vx = (point.x - crop.x) / spanX
        let vy = (point.y - crop.y) / spanY
        return CGPoint(
            x: rect.minX + vx * rect.width,
            y: rect.minY + vy * rect.height
        )
    }

    static func pixelWeight(_ annotation: Annotation, in rect: CGRect) -> CGFloat {
        max(1, CGFloat(annotation.weight) * min(rect.width, rect.height))
    }

    static func arrowWings(from start: CGPoint, to end: CGPoint, stroke: CGFloat) -> (CGPoint, CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return (end, end) }
        let ux = dx / length
        let uy = dy / length
        let head = max(stroke * 4, 1)
        let spread = head * 0.55
        let base = CGPoint(x: end.x - ux * head, y: end.y - uy * head)
        let left = CGPoint(x: base.x + (-uy) * spread, y: base.y + ux * spread)
        let right = CGPoint(x: base.x - (-uy) * spread, y: base.y - ux * spread)
        return (left, right)
    }

    static func boxBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    static func textBox(anchor: CGPoint, text: String, fontSize: CGFloat) -> CGRect {
        let count = CGFloat(max(text.count, 1))
        let width = max(fontSize, count * fontSize * 0.55)
        let height = max(fontSize, fontSize * 1.25)
        return CGRect(x: anchor.x, y: anchor.y, width: width, height: height)
    }

    static func bounds(_ annotation: Annotation, in rect: CGRect, crop: CropRect) -> CGRect? {
        let points = annotation.points.map { placed($0, in: rect, crop: crop) }
        guard let first = points.first else { return nil }
        let weight = pixelWeight(annotation, in: rect)
        if annotation.kind == .text {
            return textBox(anchor: first, text: annotation.text, fontSize: weight)
        }
        var box = CGRect(x: first.x, y: first.y, width: 0, height: 0)
        for point in points.dropFirst() {
            box = box.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let pad = annotation.kind == .arrow ? weight * 4 : weight * 0.5
        return box.insetBy(dx: -pad, dy: -pad)
    }

    /// Handles you can drag to reshape. Pen and marker strokes move as a whole.
    static func handles(
        of annotation: Annotation,
        in rect: CGRect,
        crop: CropRect
    ) -> [(AnnotationHandle, CGPoint)] {
        switch annotation.kind {
        case .line, .arrow:
            return annotation.points.enumerated().map { index, point in
                (.point(index), placed(point, in: rect, crop: crop))
            }
        case .rectangle, .ellipse:
            guard annotation.points.count >= 2 else { return [] }
            let box = boxBetween(
                placed(annotation.points[0], in: rect, crop: crop),
                placed(annotation.points[1], in: rect, crop: crop)
            )
            return [
                (.boxCorner(.minMin), CGPoint(x: box.minX, y: box.minY)),
                (.boxCorner(.maxMin), CGPoint(x: box.maxX, y: box.minY)),
                (.boxCorner(.minMax), CGPoint(x: box.minX, y: box.maxY)),
                (.boxCorner(.maxMax), CGPoint(x: box.maxX, y: box.maxY)),
            ]
        case .pen, .marker, .text:
            return []
        }
    }

    /// Topmost handle under the point wins.
    static func hitHandle(
        _ annotations: [Annotation],
        at point: CGPoint,
        imageRect: CGRect,
        crop: CropRect,
        slack: CGFloat = 9
    ) -> (id: UUID, handle: AnnotationHandle, annotation: Annotation)? {
        for mark in annotations.reversed() {
            var best: (AnnotationHandle, CGFloat)?
            for (handle, location) in handles(of: mark, in: imageRect, crop: crop) {
                let distance = hypot(point.x - location.x, point.y - location.y)
                if distance <= slack, best == nil || distance < best!.1 {
                    best = (handle, distance)
                }
            }
            if let best {
                return (mark.id, best.0, mark)
            }
        }
        return nil
    }

    /// Last drawn mark wins. `imageRect` is the on-screen photo, in the same space as `point`.
    static func hitTest(
        _ annotations: [Annotation],
        at point: CGPoint,
        imageRect: CGRect,
        crop: CropRect
    ) -> UUID? {
        for mark in annotations.reversed() {
            if hits(mark, at: point, imageRect: imageRect, crop: crop) {
                return mark.id
            }
        }
        return nil
    }

    private static func hits(
        _ mark: Annotation,
        at point: CGPoint,
        imageRect: CGRect,
        crop: CropRect
    ) -> Bool {
        let placedPoints = mark.points.map { placed($0, in: imageRect, crop: crop) }
        guard let first = placedPoints.first else { return false }
        let weight = pixelWeight(mark, in: imageRect)
        let tolerance = max(weight * 0.5 + 4, 7)

        switch mark.kind {
        case .pen, .marker, .line, .arrow:
            var segments: [(CGPoint, CGPoint)] = []
            if placedPoints.count == 1 {
                return hypot(point.x - first.x, point.y - first.y) <= tolerance
            }
            for index in 1..<placedPoints.count {
                segments.append((placedPoints[index - 1], placedPoints[index]))
            }
            if mark.kind == .arrow, placedPoints.count >= 2 {
                let wings = arrowWings(from: first, to: placedPoints[1], stroke: weight)
                segments.append((wings.0, placedPoints[1]))
                segments.append((wings.1, placedPoints[1]))
            }
            for (start, end) in segments {
                if distance(point, start, end) <= tolerance { return true }
            }
            return false
        case .rectangle:
            guard placedPoints.count >= 2 else { return false }
            return boxBetween(first, placedPoints[1]).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .ellipse:
            guard placedPoints.count >= 2 else { return false }
            let box = boxBetween(first, placedPoints[1])
            let rx = max(box.width / 2 + tolerance, 1)
            let ry = max(box.height / 2 + tolerance, 1)
            let nx = (point.x - box.midX) / rx
            let ny = (point.y - box.midY) / ry
            return nx * nx + ny * ny <= 1
        case .text:
            let box = textBox(anchor: first, text: mark.text, fontSize: weight)
            return box.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private static func distance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.0001 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let raw = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(1, max(0, raw))
        let x = start.x + t * dx
        let y = start.y + t * dy
        return hypot(point.x - x, point.y - y)
    }
}

enum AnnotationDrawing {
    /// Paint marks onto a buffer whose row 0 is the top of the picture.
    /// `crop` is the full-frame region this buffer shows. `.full` means the whole frame.
    static func burn(_ buffer: PixelBuffer, annotations: [Annotation], crop: CropRect) -> PixelBuffer {
        guard !annotations.isEmpty, !buffer.isEmpty else { return buffer }
        guard let base = ImageCodec.cgImage(buffer),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return buffer
        }

        let width = buffer.width
        let height = buffer.height
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        let image: CGImage? = raw.withUnsafeMutableBytes { pointer in
            guard let ctx = CGContext(
                data: pointer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: space,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            ctx.interpolationQuality = .none
            ctx.draw(base, in: canvas)
            // The bitmap's first row is the top. Flip so mark y grows downward from that row.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for mark in annotations {
                draw(mark, in: ctx, canvas: canvas, crop: crop)
            }
            return ctx.makeImage()
        }

        guard let image, let burned = try? ImageCodec.fromCGImage(image) else { return buffer }
        return burned
    }

    private static func draw(_ mark: Annotation, in ctx: CGContext, canvas: CGRect, crop: CropRect) {
        let points = mark.points.map { AnnotationGeometry.placed($0, in: canvas, crop: crop) }
        guard let first = points.first else { return }
        let lineWidth = AnnotationGeometry.pixelWeight(mark, in: canvas)
        let (red, green, blue) = mark.color.components
        let alpha: CGFloat = mark.kind == .marker ? 0.45 : 1
        ctx.setStrokeColor(red: red, green: green, blue: blue, alpha: alpha)
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch mark.kind {
        case .pen, .marker:
            guard points.count >= 2 else { return }
            ctx.beginPath()
            ctx.move(to: first)
            for point in points.dropFirst() {
                ctx.addLine(to: point)
            }
            ctx.strokePath()
        case .line:
            guard points.count >= 2 else { return }
            ctx.beginPath()
            ctx.move(to: first)
            ctx.addLine(to: points[1])
            ctx.strokePath()
        case .arrow:
            guard points.count >= 2 else { return }
            let end = points[1]
            let wings = AnnotationGeometry.arrowWings(from: first, to: end, stroke: lineWidth)
            ctx.beginPath()
            ctx.move(to: first)
            ctx.addLine(to: end)
            ctx.move(to: wings.0)
            ctx.addLine(to: end)
            ctx.move(to: wings.1)
            ctx.addLine(to: end)
            ctx.strokePath()
        case .rectangle:
            guard points.count >= 2 else { return }
            ctx.stroke(AnnotationGeometry.boxBetween(first, points[1]))
        case .ellipse:
            guard points.count >= 2 else { return }
            ctx.strokeEllipse(in: AnnotationGeometry.boxBetween(first, points[1]))
        case .text:
            drawText(mark, at: first, size: lineWidth, in: ctx)
        }
    }

    /// The context is already y-down. A local flip turns the glyphs upright under the anchor.
    private static func drawText(_ mark: Annotation, at anchor: CGPoint, size: CGFloat, in ctx: CGContext) {
        let text = mark.text
        guard !text.isEmpty, size > 0 else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let (red, green, blue) = mark.color.components
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y + size)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

struct AnnotationOverlay: View {
    var imageRect: CGRect
    var crop: CropRect
    var annotations: [Annotation]
    var draft: Annotation?
    var selectedID: UUID?
    var showsHandles = false

    var body: some View {
        Canvas { context, _ in
            var context = context
            context.clip(to: Path(imageRect))
            for mark in annotations {
                draw(mark, into: &context)
            }
            if let draft {
                draw(draft, into: &context)
            }
            if let selectedID, let mark = annotations.first(where: { $0.id == selectedID }) {
                if let halo = AnnotationGeometry.bounds(mark, in: imageRect, crop: crop) {
                    let ring = halo.insetBy(dx: -4, dy: -4)
                    context.stroke(
                        Path(roundedRect: ring, cornerRadius: 3),
                        with: .color(Theme.amber),
                        lineWidth: 1
                    )
                }
                if showsHandles {
                    for (_, point) in AnnotationGeometry.handles(of: mark, in: imageRect, crop: crop) {
                        let handle = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                        let shape = Path(roundedRect: handle, cornerRadius: 1.5)
                        context.fill(shape, with: .color(Theme.amber))
                        context.stroke(shape, with: .color(Theme.ink), lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ mark: Annotation, into context: inout GraphicsContext) {
        let points = mark.points.map { AnnotationGeometry.placed($0, in: imageRect, crop: crop) }
        guard let first = points.first else { return }
        let lineWidth = AnnotationGeometry.pixelWeight(mark, in: imageRect)
        let ink = mark.kind == .marker ? mark.color.swiftColor.opacity(0.45) : mark.color.swiftColor

        if mark.kind == .text {
            let resolved = context.resolve(
                Text(mark.text)
                    .font(.system(size: lineWidth, weight: .medium))
                    .foregroundColor(ink)
            )
            context.draw(resolved, at: first, anchor: .topLeading)
            return
        }

        if points.count == 1 {
            let radius = lineWidth / 2
            let dot = CGRect(x: first.x - radius, y: first.y - radius, width: lineWidth, height: lineWidth)
            context.fill(Path(ellipseIn: dot), with: .color(ink))
            return
        }

        var path = Path()
        switch mark.kind {
        case .pen, .marker, .line:
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        case .arrow:
            let end = points[1]
            let wings = AnnotationGeometry.arrowWings(from: first, to: end, stroke: lineWidth)
            path.move(to: first)
            path.addLine(to: end)
            path.move(to: wings.0)
            path.addLine(to: end)
            path.move(to: wings.1)
            path.addLine(to: end)
        case .rectangle:
            path.addRect(AnnotationGeometry.boxBetween(first, points[1]))
        case .ellipse:
            path.addEllipse(in: AnnotationGeometry.boxBetween(first, points[1]))
        case .text:
            break
        }
        context.stroke(
            path,
            with: .color(ink),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
