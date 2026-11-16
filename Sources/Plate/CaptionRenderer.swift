import AppKit
import CoreGraphics
import CoreText
import Foundation

enum CaptionRenderer {
    struct Product {
        var image: CGImage
        var hits: [CaptionHit]
    }

    /// Draws each caption onto `source`, after any mat. Core Graphics is y-up.
    /// Hit rects are y-down so they line up with the preview. Letter size is a
    /// fraction of the photo width, so a side mat does not enlarge the type.
    /// An empty caption list with no mat returns the source unchanged.
    static func render(
        source: CGImage,
        marks: [CaptionMark],
        margins: CanvasMargins = CanvasMargins(),
        flatten: Bool,
        maxSide: Int = ImageFile.maxSide
    ) -> Product {
        let expanded = ImageFile.expand(source, margins: margins, maxSide: maxSide)
        let canvas = expanded.image
        let visible = marks.filter(\.hasVisibleText)
        guard !visible.isEmpty else {
            return Product(image: canvas, hits: [])
        }
        let width = canvas.width
        let height = canvas.height
        guard width > 0, height > 0 else {
            return Product(image: canvas, hits: [])
        }
        let contentWidth = CGFloat(max(1, expanded.contentWidth))
        let layout = margins.layout(photoWidth: source.width, photoHeight: source.height, maxSide: maxSide)

        var hits: [CaptionHit] = []
        let image = ImageFile.draw(width: width, height: height) { ctx in
            let full = CGRect(x: 0, y: 0, width: width, height: height)
            if flatten {
                ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(full)
            }
            ctx.draw(canvas, in: full)
            for mark in visible {
                if let hit = draw(
                    mark,
                    in: ctx,
                    width: width,
                    height: height,
                    contentWidth: contentWidth,
                    layout: layout
                ) {
                    hits.append(hit)
                }
            }
        }
        return Product(image: image ?? canvas, hits: hits)
    }

    private static func draw(
        _ mark: CaptionMark,
        in ctx: CGContext,
        width: Int,
        height: Int,
        contentWidth: CGFloat,
        layout: CanvasLayout
    ) -> CaptionHit? {
        if let region = marginRegion(for: mark, layout: layout, canvasWidth: CGFloat(width), canvasHeight: CGFloat(height)) {
            return drawFitted(
                mark,
                in: ctx,
                width: width,
                height: height,
                contentWidth: contentWidth,
                region: region
            )
        }
        return drawOverlay(mark, in: ctx, width: width, height: height, contentWidth: contentWidth)
    }

    /// White space the caption should live in, or nil when it stays on the photo.
    private static func marginRegion(
        for mark: CaptionMark,
        layout: CanvasLayout,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> CGRect? {
        let scaleX = canvasWidth / CGFloat(max(layout.width, 1))
        let scaleY = canvasHeight / CGFloat(max(layout.height, 1))
        let photo = CGRect(
            x: layout.photo.minX * scaleX,
            y: layout.photo.minY * scaleY,
            width: layout.photo.width * scaleX,
            height: layout.photo.height * scaleY
        )
        let bottomH = photo.minY
        let topH = canvasHeight - photo.maxY
        let leftW = photo.minX
        let rightW = canvasWidth - photo.maxX
        let bottomBar = CGRect(x: 0, y: 0, width: canvasWidth, height: max(0, bottomH))
        let topBar = CGRect(x: 0, y: photo.maxY, width: canvasWidth, height: max(0, topH))
        let leftColumn = CGRect(x: 0, y: 0, width: max(0, leftW), height: canvasHeight)
        let rightColumn = CGRect(x: photo.maxX, y: 0, width: max(0, rightW), height: canvasHeight)

        switch mark.pin {
        case .bottom where bottomH >= 8:
            return bottomBar
        case .top where topH >= 8:
            return topBar
        case .free:
            let ax = CGFloat(min(1, max(0, mark.anchorX))) * canvasWidth
            let ay = (1 - CGFloat(min(1, max(0, mark.anchorY)))) * canvasHeight
            if rightW >= 8, ax >= photo.maxX - 0.5 { return rightColumn }
            if leftW >= 8, ax <= photo.minX + 0.5 { return leftColumn }
            if bottomH >= 8, ay <= photo.minY + 0.5 { return bottomBar }
            if topH >= 8, ay >= photo.maxY - 0.5 { return topBar }
            return nil
        default:
            return nil
        }
    }

    /// Wrap the caption to the white strip and shrink it until the ink, outline
    /// included, sits inside that strip. Size is still a fraction of the photo
    /// width, and it will not grow past the strip.
    private static func drawFitted(
        _ mark: CaptionMark,
        in ctx: CGContext,
        width: Int,
        height: Int,
        contentWidth: CGFloat,
        region: CGRect
    ) -> CaptionHit? {
        let shown = mark.uppercase ? mark.text.uppercased() : mark.text
        guard shown.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else { return nil }

        let box = innerBox(region)
        guard box.width >= 8, box.height >= 8 else { return nil }
        let widthFraction = min(1, max(0.2, mark.width))
        let wrap = max(8, box.width * CGFloat(widthFraction))
        let strokeRatio = CGFloat(min(0.45, max(0, mark.strokeWidth)))
        let asked = max(4, CGFloat(min(0.25, max(0.02, mark.size))) * contentWidth)
        let fontSize = largestFont(
            text: shown,
            mark: mark,
            wrap: wrap,
            limit: box.size,
            strokeRatio: strokeRatio,
            ceiling: asked
        ) ?? 4
        guard let laid = layoutFrame(
            text: shown,
            mark: mark,
            fontSize: fontSize,
            wrap: wrap,
            strokeRatio: strokeRatio
        ) else { return nil }

        let ink = laid.ink
        let radius = laid.radius
        let dx: CGFloat
        switch mark.alignment {
        case .left:
            dx = box.minX + radius - ink.minX
        case .right:
            dx = box.maxX - radius - ink.maxX
        case .center:
            dx = box.midX - ink.midX
        }
        var dy = box.midY - ink.midY
        if mark.pin == .free {
            let imageHeight = CGFloat(height)
            let ay = (1 - CGFloat(min(1, max(0, mark.anchorY)))) * imageHeight
            dy = ay - ink.midY
        }
        let lowest = ink.minY + dy - radius
        let highest = ink.maxY + dy + radius
        if lowest < box.minY { dy += box.minY - lowest }
        if highest > box.maxY { dy -= highest - box.maxY }

        paint(laid, in: ctx, dx: dx, dy: dy)
        return hit(for: mark, ink: ink, dx: dx, dy: dy, radius: laid.radius, width: width, height: height)
    }

    private static func innerBox(_ region: CGRect) -> CGRect {
        let dx = min(region.width * 0.1, max(8, region.width * 0.045))
        let dy = min(region.height * 0.12, max(6, region.height * 0.06))
        let box = region.insetBy(dx: min(dx, region.width * 0.4), dy: min(dy, region.height * 0.4))
        if box.width >= 8, box.height >= 8 { return box }
        return region.insetBy(dx: min(2, region.width * 0.02), dy: min(2, region.height * 0.02))
    }

    /// Largest font whose ink and outline fit in `limit`. `ceiling` stops the search.
    private static func largestFont(
        text: String,
        mark: CaptionMark,
        wrap: CGFloat,
        limit: CGSize,
        strokeRatio: CGFloat,
        ceiling: CGFloat
    ) -> CGFloat? {
        if let laid = layoutFrame(text: text, mark: mark, fontSize: ceiling, wrap: wrap, strokeRatio: strokeRatio) {
            let visualW = laid.ink.width + laid.radius * 2
            let visualH = laid.ink.height + laid.radius * 2
            if visualW <= limit.width + 0.5, visualH <= limit.height + 0.5 {
                return ceiling
            }
        }
        var low: CGFloat = 4
        var high = max(ceiling, 4)
        var best: CGFloat = 4
        var any = false
        for _ in 0..<14 {
            let size = (low + high) / 2
            guard let laid = layoutFrame(text: text, mark: mark, fontSize: size, wrap: wrap, strokeRatio: strokeRatio) else {
                high = size
                continue
            }
            let visualW = laid.ink.width + laid.radius * 2
            let visualH = laid.ink.height + laid.radius * 2
            if visualW <= limit.width + 0.5, visualH <= limit.height + 0.5 {
                best = size
                any = true
                low = size
            } else {
                high = size
            }
        }
        return any ? best : nil
    }

    private struct LaidText {
        var fill: CTFrame
        var stroke: CTFrame?
        var ink: CGRect
        var radius: CGFloat
    }

    private static func layoutFrame(
        text: String,
        mark: CaptionMark,
        fontSize: CGFloat,
        wrap: CGFloat,
        strokeRatio: CGFloat
    ) -> LaidText? {
        let font = mark.font.nsFont(size: max(4, fontSize))
        let fillString = attributed(text, font: font, color: mark.fill.nsColor, alignment: mark.alignment.nsTextAlignment)
        let framesetter = CTFramesetterCreateWithAttributedString(fillString)
        var fit = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: wrap, height: CGFloat.greatestFiniteMagnitude),
            &fit
        )
        let frameHeight = max(fontSize, ceil(suggested.height) + fontSize * 0.35)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: wrap, height: frameHeight), transform: nil)
        let fillFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let ink = inkBounds(fillFrame) else { return nil }
        let radius = fontSize * strokeRatio
        var strokeFrame: CTFrame?
        if radius >= 0.4 {
            let strokeString = attributed(text, font: font, color: mark.stroke.nsColor, alignment: mark.alignment.nsTextAlignment)
            let strokeSetter = CTFramesetterCreateWithAttributedString(strokeString)
            strokeFrame = CTFramesetterCreateFrame(strokeSetter, CFRange(location: 0, length: 0), path, nil)
        }
        return LaidText(fill: fillFrame, stroke: strokeFrame, ink: ink, radius: radius)
    }

    private static func paint(_ laid: LaidText, in ctx: CGContext, dx: CGFloat, dy: CGFloat) {
        if laid.radius >= 0.4, let stroke = laid.stroke {
            let steps = max(12, min(32, Int((laid.radius * 1.6).rounded(.up))))
            for step in 0..<steps {
                let angle = (Double(step) / Double(steps)) * Double.pi * 2
                let ox = CGFloat(cos(angle)) * laid.radius
                let oy = CGFloat(sin(angle)) * laid.radius
                draw(stroke, in: ctx, dx: dx + ox, dy: dy + oy)
            }
        }
        draw(laid.fill, in: ctx, dx: dx, dy: dy)
    }

    private static func hit(
        for mark: CaptionMark,
        ink: CGRect,
        dx: CGFloat,
        dy: CGFloat,
        radius: CGFloat,
        width: Int,
        height: Int
    ) -> CaptionHit {
        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        let placed = ink.offsetBy(dx: dx, dy: dy)
        let grown = placed.insetBy(dx: -(radius + 6), dy: -(radius + 6))
        let rect = CGRect(
            x: grown.minX,
            y: imageHeight - grown.maxY,
            width: grown.width,
            height: grown.height
        )
        let center = CGPoint(
            x: placed.midX / imageWidth,
            y: 1 - (placed.midY / imageHeight)
        )
        return CaptionHit(id: mark.id, rect: rect, center: center)
    }

    private static func drawOverlay(
        _ mark: CaptionMark,
        in ctx: CGContext,
        width: Int,
        height: Int,
        contentWidth: CGFloat
    ) -> CaptionHit? {
        let shown = mark.uppercase ? mark.text.uppercased() : mark.text
        guard shown.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else { return nil }

        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        let sizeRatio = min(0.25, max(0.02, mark.size))
        let fontSize = max(4, sizeRatio * contentWidth)
        let font = mark.font.nsFont(size: fontSize)
        let wrap = min(imageWidth, max(8, min(1, max(0.2, mark.width)) * imageWidth))
        let strokeRatio = min(0.45, max(0, mark.strokeWidth))
        let radius = fontSize * CGFloat(strokeRatio)

        let fillString = attributed(shown, font: font, color: mark.fill.nsColor, alignment: mark.alignment.nsTextAlignment)
        let framesetter = CTFramesetterCreateWithAttributedString(fillString)
        var fit = CFRange()
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: wrap, height: imageHeight),
            &fit
        )
        let frameHeight = min(imageHeight, max(fontSize, ceil(suggested.height) + fontSize * 0.35))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: wrap, height: frameHeight), transform: nil)
        let fillFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        guard let ink = inkBounds(fillFrame) else { return nil }

        let margin = max(0, (imageWidth - wrap) / 2)
        let pad = max(imageHeight * 0.02, radius)
        let dx: CGFloat
        let dy: CGFloat
        switch mark.pin {
        case .top, .bottom:
            switch mark.alignment {
            case .left:
                dx = margin - ink.minX
            case .right:
                dx = (imageWidth - margin) - ink.maxX
            case .center:
                dx = imageWidth / 2 - ink.midX
            }
            if mark.pin == .top {
                dy = imageHeight - pad - ink.maxY
            } else {
                dy = pad - ink.minY
            }
        case .free:
            let ax = CGFloat(min(1, max(0, mark.anchorX))) * imageWidth
            let ay = (1 - CGFloat(min(1, max(0, mark.anchorY)))) * imageHeight
            dx = ax - ink.midX
            dy = ay - ink.midY
        }

        if radius >= 0.4 {
            let strokeString = attributed(shown, font: font, color: mark.stroke.nsColor, alignment: mark.alignment.nsTextAlignment)
            let strokeSetter = CTFramesetterCreateWithAttributedString(strokeString)
            let strokeFrame = CTFramesetterCreateFrame(strokeSetter, CFRange(location: 0, length: 0), path, nil)
            let steps = max(12, min(32, Int((radius * 1.6).rounded(.up))))
            for step in 0..<steps {
                let angle = (Double(step) / Double(steps)) * Double.pi * 2
                let ox = CGFloat(cos(angle)) * radius
                let oy = CGFloat(sin(angle)) * radius
                draw(strokeFrame, in: ctx, dx: dx + ox, dy: dy + oy)
            }
        }
        draw(fillFrame, in: ctx, dx: dx, dy: dy)

        let placed = ink.offsetBy(dx: dx, dy: dy)
        let grown = placed.insetBy(dx: -(radius + 6), dy: -(radius + 6))
        let hit = CGRect(
            x: grown.minX,
            y: imageHeight - grown.maxY,
            width: grown.width,
            height: grown.height
        )
        let center = CGPoint(
            x: (placed.midX / imageWidth),
            y: 1 - (placed.midY / imageHeight)
        )
        return CaptionHit(id: mark.id, rect: hit, center: center)
    }

    private static func draw(_ frame: CTFrame, in ctx: CGContext, dx: CGFloat, dy: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: dx, y: dy)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    private static func attributed(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    /// Glyph ink relative to the frame path origin, in Core Graphics points (y up).
    private static func inkBounds(_ frame: CTFrame) -> CGRect? {
        let lines = CTFrameGetLines(frame)
        let count = CFArrayGetCount(lines)
        guard count > 0 else { return nil }
        var origins = [CGPoint](repeating: .zero, count: count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var union = CGRect.null
        for index in 0..<count {
            let line = unsafeBitCast(CFArrayGetValueAtIndex(lines, index), to: CTLine.self)
            let bounds = CTLineGetImageBounds(line, nil)
            if bounds.isNull || bounds.width < 0.5 || bounds.height < 0.5 { continue }
            let rect = CGRect(
                x: origins[index].x + bounds.origin.x,
                y: origins[index].y + bounds.origin.y,
                width: bounds.width,
                height: bounds.height
            )
            union = union.union(rect)
        }
        if union.isNull || union.width < 0.5 || union.height < 0.5 { return nil }
        return union
    }
}
