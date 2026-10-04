import CoreGraphics
import Foundation

enum SelfTest {
    static func run() -> String? {
        let checks: [(String, () -> String?)] = [
            ("identity", identity),
            ("exposure", exposure),
            ("contrast", contrast),
            ("saturation", saturation),
            ("temperature", temperature),
            ("tint", tint),
            ("highlights", highlights),
            ("shadows", shadows),
            ("fade", fade),
            ("mono", mono),
            ("sepia", sepia),
            ("vignette", vignette),
            ("sharpness", sharpness),
            ("alpha", alpha),
            ("rotate90", rotate90),
            ("flipH", flipHorizontal),
            ("orientation", orientation),
            ("crop", crop),
            ("crop follows rotate", cropFollowsRotate),
            ("downscale", downscale),
            ("histogram", histogram),
            ("history", history),
            ("export name", exportName),
            ("crop math", cropMath),
            ("cli", cli),
            ("png round trip", pngRoundTrip),
            ("jpeg round trip", jpegRoundTrip),
            ("annotation points", annotationPoints),
            ("annotation hit", annotationHit),
            ("annotation undo", annotationUndo),
            ("annotation reshape", annotationReshape),
            ("annotation burn", annotationBurn),
            ("straighten", straighten),
            ("grade", grade),
            ("nudge and duplicate", nudgeAndDuplicate),
        ]
        for (name, check) in checks {
            if let failure = check() {
                return "\(name): \(failure)"
            }
        }
        return nil
    }

    private static func identity() -> String? {
        let source = pattern(width: 5, height: 4)
        let rendered = Engine.render(source, state: EditState(), applyCrop: true)
        if rendered != source { return "default edit changed pixels" }
        return nil
    }

    private static func exposure() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(100, 100, 100))
        var state = EditState()
        state.exposure = 1
        let rendered = Engine.render(source, state: state, applyCrop: true)
        if rendered.pixel(x: 0, y: 0).r <= 100 { return "one stop did not brighten" }
        return nil
    }

    private static func contrast() -> String? {
        var source = PixelBuffer.filled(width: 2, height: 1, pixel: .rgb(0, 0, 0))
        source.setPixel(x: 0, y: 0, .rgb(64, 64, 64))
        source.setPixel(x: 1, y: 0, .rgb(192, 192, 192))
        var state = EditState()
        state.contrast = 1
        let rendered = Engine.render(source, state: state, applyCrop: true)
        let before = Int(source.pixel(x: 1, y: 0).r) - Int(source.pixel(x: 0, y: 0).r)
        let after = Int(rendered.pixel(x: 1, y: 0).r) - Int(rendered.pixel(x: 0, y: 0).r)
        if after <= before { return "contrast did not increase separation" }
        return nil
    }

    private static func saturation() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(220, 30, 40))
        var state = EditState()
        state.saturation = -1
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.r != pixel.g || pixel.g != pixel.b { return "full desat left color" }
        if pixel.r == 0 || pixel.r == 255 { return "gray landed on a clamp" }
        return nil
    }

    private static func temperature() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(128, 128, 128))
        var state = EditState()
        state.temperature = 1
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.r <= pixel.b { return "warmth did not lift red over blue" }
        return nil
    }

    private static func tint() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(128, 128, 128))
        var state = EditState()
        state.tint = 1
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.g >= pixel.r { return "magenta tint did not drop green" }
        return nil
    }

    private static func highlights() -> String? {
        var source = PixelBuffer.filled(width: 2, height: 1, pixel: .rgb(0, 0, 0))
        source.setPixel(x: 0, y: 0, .rgb(240, 240, 240))
        source.setPixel(x: 1, y: 0, .rgb(20, 20, 20))
        var state = EditState()
        state.highlights = -1
        let rendered = Engine.render(source, state: state, applyCrop: true)
        if rendered.pixel(x: 0, y: 0).r >= 240 { return "highlight recovery did not darken the bright pixel" }
        if abs(Int(rendered.pixel(x: 1, y: 0).r) - 20) > 8 { return "highlight recovery moved the shadow" }
        return nil
    }

    private static func shadows() -> String? {
        var source = PixelBuffer.filled(width: 2, height: 1, pixel: .rgb(0, 0, 0))
        source.setPixel(x: 0, y: 0, .rgb(20, 20, 20))
        source.setPixel(x: 1, y: 0, .rgb(240, 240, 240))
        var state = EditState()
        state.shadows = 1
        let rendered = Engine.render(source, state: state, applyCrop: true)
        if rendered.pixel(x: 0, y: 0).r <= 20 { return "shadow lift did nothing" }
        if rendered.pixel(x: 1, y: 0).r < 230 { return "shadow lift darkened the highlight" }
        return nil
    }

    private static func fade() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(0, 0, 0))
        var state = EditState()
        state.look = .fade
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.r == 0 { return "fade left black at zero" }
        return nil
    }

    private static func mono() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(20, 180, 40))
        var state = EditState()
        state.look = .mono
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.r != pixel.g || pixel.g != pixel.b { return "mono left chroma" }
        return nil
    }

    private static func sepia() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(140, 140, 140))
        var state = EditState()
        state.look = .sepia
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel.r <= pixel.b { return "sepia did not warm the gray" }
        return nil
    }

    private static func vignette() -> String? {
        let source = PixelBuffer.filled(width: 32, height: 32, pixel: .rgb(255, 255, 255))
        var state = EditState()
        state.vignette = 1
        let rendered = Engine.render(source, state: state, applyCrop: true)
        let center = rendered.pixel(x: 16, y: 16).r
        let corner = rendered.pixel(x: 0, y: 0).r
        if center != 255 { return "vignette darkened the center (\(center))" }
        if corner >= 200 { return "vignette left the corner bright (\(corner))" }
        return nil
    }

    private static func sharpness() -> String? {
        let flat = PixelBuffer.filled(width: 5, height: 5, pixel: .rgb(90, 90, 90))
        var state = EditState()
        state.sharpness = 1
        if Engine.render(flat, state: state, applyCrop: true) != flat { return "sharpen changed a flat field" }

        var edge = PixelBuffer.filled(width: 5, height: 5, pixel: .rgb(40, 40, 40))
        for y in 0..<5 {
            for x in 2..<5 {
                edge.setPixel(x: x, y: y, .rgb(200, 200, 200))
            }
        }
        let sharpened = Engine.render(edge, state: state, applyCrop: true)
        if sharpened.pixel(x: 2, y: 2).r <= 200 { return "bright side of the edge was not sharpened" }
        if sharpened.pixel(x: 1, y: 2).r >= 40 { return "dark side of the edge was not sharpened" }
        return nil
    }

    private static func alpha() -> String? {
        let source = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(10, 20, 30, 0))
        var state = EditState()
        state.exposure = 2
        let pixel = Engine.render(source, state: state, applyCrop: true).pixel(x: 0, y: 0)
        if pixel != .clear { return "clear pixel picked up color" }

        let translucent = PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(80, 90, 100, 128))
        let kept = Engine.render(translucent, state: EditState(), applyCrop: true).pixel(x: 0, y: 0)
        if kept.a != 128 { return "alpha changed on an identity edit" }
        return nil
    }

    private static func rotate90() -> String? {
        let source = PixelBuffer(
            width: 2,
            height: 3,
            pixels: [
                .rgb(1, 0, 0), .rgb(2, 0, 0),
                .rgb(3, 0, 0), .rgb(4, 0, 0),
                .rgb(5, 0, 0), .rgb(6, 0, 0),
            ]
        )
        let turned = Engine.rotate90CW(source)
        if turned.width != 3 || turned.height != 2 { return "size \(turned.width)×\(turned.height)" }
        let expected: [UInt8] = [5, 3, 1, 6, 4, 2]
        let got = turned.pixels.map(\.r)
        if got != expected { return "pixels \(got)" }
        return nil
    }

    private static func flipHorizontal() -> String? {
        let source = PixelBuffer(
            width: 2,
            height: 1,
            pixels: [.rgb(1, 0, 0), .rgb(2, 0, 0)]
        )
        let flipped = Engine.flipH(source)
        if flipped.pixels.map(\.r) != [2, 1] { return "order \(flipped.pixels.map(\.r))" }
        return nil
    }

    private static func orientation() -> String? {
        if PlateOrientation.up.applying(.rotateCW) != .right { return "CW from up is not right" }
        if PlateOrientation.up.applying(.rotateCCW) != .left { return "CCW from up is not left" }
        if PlateOrientation.up.applying(.flipH) != .upMirrored { return "flip H missed" }
        var turns = PlateOrientation.up
        for _ in 0..<4 { turns = turns.applying(.rotateCW) }
        if turns != .up { return "four quarter-turns did not close" }
        if PlateOrientation.up.applying(.flipH).applying(.flipH) != .up { return "flip H did not toggle" }
        let probe = PixelBuffer.probe()
        for base in PlateOrientation.allCases {
            for op in OrientOp.allCases {
                let viaEnum = Engine.oriented(probe, base.applying(op))
                let viaPixels = Engine.transform(Engine.oriented(probe, base), op)
                if viaEnum != viaPixels { return "\(base) + \(op) disagrees" }
            }
        }
        return nil
    }

    private static func crop() -> String? {
        var source = PixelBuffer.filled(width: 4, height: 4, pixel: .rgb(0, 0, 9))
        source.setPixel(x: 3, y: 3, .rgb(7, 0, 0))
        var state = EditState()
        state.crop = CropRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        let rendered = Engine.render(source, state: state, applyCrop: true)
        if rendered.width != 2 || rendered.height != 2 { return "size \(rendered.width)×\(rendered.height)" }
        if rendered.pixel(x: 1, y: 1).r != 7 { return "missed the marked pixel" }
        let bounds = CropMath.pixelBounds(crop: state.crop, width: 4, height: 4)
        if bounds != (2, 2, 2, 2) { return "bounds \(bounds)" }
        return nil
    }

    private static func cropFollowsRotate() -> String? {
        var source = PixelBuffer.filled(width: 4, height: 4, pixel: .rgb(0, 0, 20))
        source.setPixel(x: 1, y: 1, .rgb(255, 0, 0))
        var state = EditState()
        state.crop = CropRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)
        let before = Engine.render(source, state: state, applyCrop: true)
        if before.width != 1 || before.height != 1 || before.pixel(x: 0, y: 0).r != 255 {
            return "crop did not isolate the red pixel"
        }
        for op in OrientOp.allCases {
            let turned = state.applying(op)
            let after = Engine.render(source, state: turned, applyCrop: true)
            if after.pixels.contains(where: { $0.r == 255 }) == false || after.pixelCount != 1 {
                return "\(op) lost the cropped pixel (\(after.width)×\(after.height))"
            }
        }
        return nil
    }

    private static func downscale() -> String? {
        var source = PixelBuffer.filled(width: 4, height: 2, pixel: .rgb(0, 0, 0))
        for y in 0..<2 {
            for x in 0..<2 {
                source.setPixel(x: x, y: y, .rgb(255, 255, 255))
            }
        }
        let small = Engine.downscale(source, maxSide: 2)
        if small.width != 2 || small.height != 1 { return "size \(small.width)×\(small.height)" }
        if small.pixel(x: 0, y: 0) != .rgb(255, 255, 255) { return "left average" }
        if small.pixel(x: 1, y: 0) != .rgb(0, 0, 0) { return "right average" }
        if Engine.downscale(source, maxSide: 8).width != 4 { return "small image was scaled" }
        return nil
    }

    private static func histogram() -> String? {
        let black = Engine.lumaHistogram(PixelBuffer.filled(width: 2, height: 2, pixel: .rgb(0, 0, 0)))
        if black[0] != 4 { return "black bin \(black[0])" }
        let white = Engine.lumaHistogram(PixelBuffer.filled(width: 1, height: 1, pixel: .rgb(255, 255, 255)))
        if white[255] != 1 { return "white bin \(white[255])" }
        return nil
    }

    private static func history() -> String? {
        var history = EditHistory(limit: 4)
        if history.canUndo || history.canRedo { return "fresh history is not empty" }
        var edited = EditState()
        edited.exposure = 0.5
        history.push(edited)
        history.push(edited)
        if history.states.count != 2 { return "duplicate push was stored" }
        edited.contrast = 0.2
        history.push(edited)
        guard history.undo()?.exposure == 0.5 else { return "undo missed the exposure step" }
        history.push(EditState())
        if history.canRedo { return "push did not drop the redo tail" }
        _ = history.undo()
        _ = history.undo()
        if history.canUndo { return "undo walked off the start" }
        var capped = EditHistory(limit: 3)
        for value in [0.1, 0.2, 0.3, 0.4] {
            var step = EditState()
            step.exposure = value
            capped.push(step)
        }
        if capped.states.count != 3 { return "cap kept \(capped.states.count)" }
        if capped.current.exposure != 0.4 { return "cap lost the latest edit" }
        return nil
    }

    private static func exportName() -> String? {
        let photo = URL(fileURLWithPath: "/tmp/photo.png")
        let suggested = ExportNaming.suggestedURL(for: photo, jpeg: false)
        if suggested.lastPathComponent != "photo-edited.png" { return suggested.lastPathComponent }
        let jpeg = ExportNaming.suggestedURL(for: photo, jpeg: true)
        if jpeg.pathExtension != "jpg" { return jpeg.path }
        let already = URL(fileURLWithPath: "/tmp/photo-edited.png")
        let copy = ExportNaming.suggestedURL(for: already, jpeg: false)
        if copy.lastPathComponent != "photo-edited-copy.png" { return copy.lastPathComponent }
        if !ExportNaming.overwritesSource(photo, source: photo) { return "same path was allowed" }
        if ExportNaming.overwritesSource(suggested, source: photo) { return "a new name was treated as the original" }
        return nil
    }

    private static func cropMath() -> String? {
        let start = CropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let wider = CropMath.resized(
            start: start, handle: .right, dx: 0.1, dy: 0,
            pixelRatio: nil, imageWidth: 100, imageHeight: 100
        )
        if abs(wider.x - 0.2) > 0.0001 || abs(wider.width - 0.5) > 0.0001 {
            return "right edge \(wider)"
        }
        let shoved = CropMath.translated(start, dx: -1, dy: 0)
        if shoved.x != 0 || abs(shoved.width - 0.4) > 0.0001 { return "clamp \(shoved)" }
        let square = CropMath.fitted(ratio: 1, imageWidth: 100, imageHeight: 50)
        if abs(square.width - 0.5) > 0.0001 || abs(square.height - 1) > 0.0001 {
            return "square fit \(square)"
        }
        let rect = CGRect(x: 10, y: 10, width: 100, height: 80)
        if CropMath.hitTest(point: CGPoint(x: 10, y: 10), cropRect: rect, slack: 8) != .topLeft {
            return "missed the corner"
        }
        if CropMath.hitTest(point: CGPoint(x: 50, y: 50), cropRect: rect, slack: 8) != .move {
            return "missed the inside"
        }
        return nil
    }

    private static func cli() -> String? {
        let args = [
            "Plate", "a.png", "--exposure", "0.5", "--rotate", "90",
            "--look", "mono", "--flip-h", "--crop", "0.1,0.2,0.3,0.4",
            "-o", "b.jpg", "--jpeg",
        ]
        guard case .success(let request) = CLI.parse(args) else { return "parse failed" }
        if request.input != "a.png" || request.output != "b.jpg" || !request.jpeg { return "paths" }
        if request.state.exposure != 0.5 || request.state.look != .mono { return "grade" }
        if request.state.orientation != .rightMirrored { return "orientation \(request.state.orientation)" }
        if request.state.crop != CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4) { return "crop" }
        if case .success = CLI.parse(["Plate"]) { return "missing input was accepted" }
        if case .success = CLI.parse(["Plate", "a.png", "--exposure", "9"]) { return "bad exposure was accepted" }
        if case .success = CLI.parse(["Plate", "a.png", "--look", "nope"]) { return "bad look was accepted" }
        guard case .success(let negative) = CLI.parse(["Plate", "a.png", "--exposure", "-0.25", "--rotate", "-90"]) else {
            return "negative values were rejected"
        }
        if negative.state.exposure != -0.25 || negative.state.orientation != .left {
            return "negative parse \(negative.state.exposure) \(negative.state.orientation)"
        }
        guard case .success(let tilted) = CLI.parse(["Plate", "a.png", "--straighten", "-12.5"]) else {
            return "straighten was rejected"
        }
        if abs(tilted.state.straighten - -12.5) > 0.0001 { return "straighten parse" }
        if case .success = CLI.parse(["Plate", "a.png", "--straighten", "46"]) {
            return "straighten past 45 was accepted"
        }
        return nil
    }

    private static func pngRoundTrip() -> String? {
        let source = PixelBuffer(
            width: 3,
            height: 2,
            pixels: [
                .rgb(0, 0, 0), .rgb(255, 0, 0), .rgb(0, 255, 0),
                .rgb(0, 0, 255), .rgb(128, 64, 32), .rgb(255, 255, 255),
            ]
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plate-selftest-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try ImageCodec.write(try ImageCodec.pngData(source), to: url)
            let loaded = try ImageCodec.load(url: url)
            if loaded != source { return "pixels changed" }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private static func jpegRoundTrip() -> String? {
        let source = PixelBuffer.filled(width: 16, height: 16, pixel: .rgb(128, 64, 32))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plate-selftest-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try ImageCodec.write(try ImageCodec.jpegData(source, quality: 0.92), to: url)
            let loaded = try ImageCodec.load(url: url)
            if loaded.width != 16 || loaded.height != 16 { return "size" }
            let pixel = loaded.pixel(x: 8, y: 8)
            if abs(Int(pixel.r) - 128) > 6 || abs(Int(pixel.g) - 64) > 6 || abs(Int(pixel.b) - 32) > 6 {
                return "color drifted to \(pixel)"
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private static func annotationPoints() -> String? {
        let start = NormPoint(x: 0.2, y: 0.3)
        let expectations: [(OrientOp, Double, Double)] = [
            (.rotateCW, 0.7, 0.2),
            (.rotateCCW, 0.3, 0.8),
            (.flipH, 0.8, 0.3),
            (.flipV, 0.2, 0.7),
        ]
        for (op, x, y) in expectations {
            let point = AnnotationGeometry.transformed(start, op)
            if abs(point.x - x) > 0.0001 || abs(point.y - y) > 0.0001 {
                return "\(op) moved the point to \(point.x), \(point.y)"
            }
        }

        let crop = CropRect(x: 0.2, y: 0.3, width: 0.4, height: 0.25)
        let corners = [
            NormPoint(x: crop.x, y: crop.y),
            NormPoint(x: crop.maxX, y: crop.y),
            NormPoint(x: crop.x, y: crop.maxY),
            NormPoint(x: crop.maxX, y: crop.maxY),
        ]
        for op in OrientOp.allCases {
            let moved = CropMath.applying(op, to: crop)
            let mapped = corners.map { AnnotationGeometry.transformed($0, op) }
            let landed = [
                NormPoint(x: moved.x, y: moved.y),
                NormPoint(x: moved.maxX, y: moved.y),
                NormPoint(x: moved.x, y: moved.maxY),
                NormPoint(x: moved.maxX, y: moved.maxY),
            ]
            for corner in mapped {
                let found = landed.contains { abs($0.x - corner.x) < 0.0001 && abs($0.y - corner.y) < 0.0001 }
                if !found { return "\(op) split a mark from the crop" }
            }
        }

        var state = EditState()
        state.annotations = [
            Annotation(
                id: UUID(),
                kind: .line,
                color: .amber,
                weight: 0.01,
                points: [start, NormPoint(x: 0.4, y: 0.5)],
                text: ""
            ),
        ]
        let turned = state.applying(.rotateCW)
        let first = turned.annotations[0].points[0]
        if abs(first.x - 0.7) > 0.0001 || abs(first.y - 0.2) > 0.0001 {
            return "edit state left the mark behind"
        }
        return nil
    }

    private static func annotationHit() -> String? {
        let line = Annotation(
            id: UUID(),
            kind: .line,
            color: .red,
            weight: 0.02,
            points: [NormPoint(x: 0.1, y: 0.2), NormPoint(x: 0.9, y: 0.2)],
            text: ""
        )
        let box = Annotation(
            id: UUID(),
            kind: .rectangle,
            color: .blue,
            weight: 0.01,
            points: [NormPoint(x: 0.4, y: 0.1), NormPoint(x: 0.7, y: 0.4)],
            text: ""
        )
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let onLine = AnnotationGeometry.hitTest([line], at: CGPoint(x: 100, y: 20), imageRect: frame, crop: .full)
        if onLine != line.id { return "missed the line" }
        let offLine = AnnotationGeometry.hitTest([line], at: CGPoint(x: 100, y: 70), imageRect: frame, crop: .full)
        if offLine != nil { return "hit empty space" }
        let top = AnnotationGeometry.hitTest(
            [line, box],
            at: CGPoint(x: 100, y: 20),
            imageRect: frame,
            crop: .full
        )
        if top != box.id { return "an older mark won the hit" }
        return nil
    }

    private static func annotationUndo() -> String? {
        var history = EditHistory()
        var marked = EditState()
        marked.annotations = [
            Annotation(
                id: UUID(),
                kind: .line,
                color: .red,
                weight: 0.02,
                points: [NormPoint(x: 0, y: 0), NormPoint(x: 1, y: 1)],
                text: ""
            ),
        ]
        history.push(marked)
        guard history.undo() != nil else { return "no undo" }
        if !history.current.annotations.isEmpty { return "undo left the mark" }
        if history.redo()?.annotations.count != 1 { return "redo lost the mark" }
        return nil
    }

    private static func annotationReshape() -> String? {
        let line = Annotation(
            id: UUID(),
            kind: .line,
            color: .red,
            weight: 0.02,
            points: [NormPoint(x: 0.2, y: 0.2), NormPoint(x: 0.8, y: 0.2)],
            text: ""
        )
        let moved = AnnotationGeometry.reshaped(line, handle: .point(1), to: NormPoint(x: 0.8, y: 0.6))
        if moved.points[0].x != line.points[0].x || moved.points[0].y != line.points[0].y {
            return "reshaping the end moved the start"
        }
        if abs(moved.points[1].y - 0.6) > 0.0001 { return "the end did not follow the cursor" }

        let box = Annotation(
            id: UUID(),
            kind: .rectangle,
            color: .blue,
            weight: 0.01,
            points: [NormPoint(x: 0.6, y: 0.7), NormPoint(x: 0.2, y: 0.3)],
            text: ""
        )
        let resized = AnnotationGeometry.reshaped(box, handle: .boxCorner(.minMin), to: NormPoint(x: 0.05, y: 0.1))
        let xs = resized.points.map(\.x).sorted()
        let ys = resized.points.map(\.y).sorted()
        if abs(xs[0] - 0.05) > 0.0001 || abs(xs[1] - 0.6) > 0.0001 {
            return "the box lost its anchored x"
        }
        if abs(ys[0] - 0.1) > 0.0001 || abs(ys[1] - 0.7) > 0.0001 {
            return "the box lost its anchored y"
        }

        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let end = AnnotationGeometry.hitHandle([line], at: CGPoint(x: 160, y: 20), imageRect: frame, crop: .full)
        if end?.handle != .point(1) { return "missed the line's end handle" }
        let shaft = AnnotationGeometry.hitHandle([line], at: CGPoint(x: 100, y: 20), imageRect: frame, crop: .full)
        if shaft != nil { return "the middle of a line is not a handle" }
        return nil
    }

    private static func annotationBurn() -> String? {
        let source = pattern(width: 6, height: 5)
        if Engine.render(source, state: EditState(), applyCrop: true, bakeAnnotations: true) != source {
            return "empty marks changed pixels"
        }
        var parked = EditState()
        parked.annotations = [
            Annotation(
                id: UUID(),
                kind: .line,
                color: .red,
                weight: 0.2,
                points: [NormPoint(x: 0, y: 0), NormPoint(x: 1, y: 0)],
                text: ""
            ),
        ]
        if Engine.render(source, state: parked, applyCrop: true) != source {
            return "unbaked marks changed pixels"
        }

        let white = PixelBuffer.filled(width: 40, height: 40, pixel: .rgb(255, 255, 255))
        var top = EditState()
        top.annotations = [
            Annotation(
                id: UUID(),
                kind: .line,
                color: .red,
                weight: 0.12,
                points: [NormPoint(x: 0.05, y: 0.1), NormPoint(x: 0.95, y: 0.1)],
                text: ""
            ),
        ]
        let burned = Engine.render(white, state: top, applyCrop: true, bakeAnnotations: true)
        let sample = burned.pixel(x: 20, y: 4)
        if !isRed(sample) {
            let low = burned.pixel(x: 20, y: 36)
            return "top line missed row 4, got \(sample.r),\(sample.g),\(sample.b); row 36 is \(low.r),\(low.g),\(low.b)"
        }
        let bottom = burned.pixel(x: 20, y: 39)
        if bottom.r < 250 || bottom.g < 250 || bottom.b < 250 {
            return "top line painted the bottom row"
        }

        var cropped = EditState()
        cropped.crop = CropRect(x: 0.5, y: 0, width: 0.5, height: 1)
        cropped.annotations = [
            Annotation(
                id: UUID(),
                kind: .line,
                color: .red,
                weight: 0.2,
                points: [NormPoint(x: 0.55, y: 0.2), NormPoint(x: 0.55, y: 0.8)],
                text: ""
            ),
        ]
        let half = Engine.render(white, state: cropped, applyCrop: true, bakeAnnotations: true)
        if half.width != 20 || half.height != 40 {
            return "crop size \(half.width)x\(half.height)"
        }
        if !isRed(half.pixel(x: 2, y: 20)) {
            let pixel = half.pixel(x: 2, y: 20)
            return "right-half mark missed the left of the crop (\(pixel.r),\(pixel.g),\(pixel.b))"
        }
        let far = half.pixel(x: 18, y: 20)
        if far.r < 250 || far.g < 250 || far.b < 250 {
            return "right-half mark painted the far side"
        }

        let tall = PixelBuffer.filled(width: 160, height: 160, pixel: .rgb(255, 255, 255))
        var note = EditState()
        note.annotations = [
            Annotation(
                id: UUID(),
                kind: .text,
                color: .black,
                weight: 0.15,
                points: [NormPoint(x: 0.1, y: 0.3)],
                text: "Note"
            ),
        ]
        let labeled = Engine.render(tall, state: note, applyCrop: true, bakeAnnotations: true)
        let anchor = 48
        var above = false
        var below = false
        for y in 0..<labeled.height {
            for x in 0..<labeled.width {
                let pixel = labeled.pixel(x: x, y: y)
                if pixel.r < 245 || pixel.g < 245 || pixel.b < 245 {
                    if y < anchor - 4 { above = true }
                    if y >= anchor { below = true }
                    break
                }
            }
        }
        if above { return "text drew above the anchor" }
        if !below { return "text left no ink under the anchor" }
        return nil
    }

    private static func straighten() -> String? {
        let square = StraightenMath.pixelSize(width: 100, height: 100, degrees: 0)
        if square != (100, 100) { return "zero angle changed the size" }
        let diamond = StraightenMath.pixelSize(width: 100, height: 100, degrees: 45)
        if diamond != (70, 70) { return "square at 45° is \(diamond)" }
        let wide = StraightenMath.inscribed(width: 200, height: 100, degrees: 10)
        let radians = 10 * Double.pi / 180
        let s = sin(radians)
        let c = cos(radians)
        let widthSlack = 200 - (wide.width * c + wide.height * s)
        let heightSlack = 100 - (wide.height * c + wide.width * s)
        if widthSlack < -0.05 || heightSlack < -0.05 {
            return "10° frame leaves the photo"
        }
        if wide.width >= 200 || wide.height >= 100 { return "10° frame did not shrink" }

        let moved = StraightenMath.inscribedPoint(x: 50, y: 30, degrees: 20, width: 100, height: 100)
        if moved.x <= 0.5 || moved.y >= 0.5 {
            return "clockwise point moved \(moved.x), \(moved.y)"
        }
        let back = StraightenMath.orientedPixel(moved, degrees: 20, width: 100, height: 100)
        if abs(back.x - 50) > 0.02 || abs(back.y - 30) > 0.02 {
            return "inverse missed \(back.x), \(back.y)"
        }
        let start = NormPoint(x: 0.3, y: 0.4)
        let spun = StraightenMath.remap(start, from: 0, to: 20, width: 100, height: 80)
        let home = StraightenMath.remap(spun, from: 20, to: 0, width: 100, height: 80)
        if abs(home.x - start.x) > 0.002 || abs(home.y - start.y) > 0.002 {
            return "mark did not return \(home.x), \(home.y)"
        }
        let center = StraightenMath.remap(NormPoint(x: 0.5, y: 0.5), from: 0, to: 12, width: 80, height: 40)
        if abs(center.x - 0.5) > 0.001 || abs(center.y - 0.5) > 0.001 {
            return "center drifted"
        }

        let white = PixelBuffer.filled(width: 80, height: 40, pixel: .rgb(255, 255, 255))
        var tilt = EditState()
        tilt.straighten = 15
        let framed = Engine.render(white, state: tilt, applyCrop: true)
        let expected = StraightenMath.pixelSize(width: 80, height: 40, degrees: 15)
        if framed.width != expected.width || framed.height != expected.height {
            return "render size \(framed.width)×\(framed.height)"
        }
        if framed.width >= 80 || framed.height >= 40 { return "straighten did not tighten the frame" }
        for pixel in framed.pixels where pixel != .rgb(255, 255, 255) {
            return "straighten showed a pixel outside the photo"
        }
        var half = tilt
        half.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        let cropped = Engine.render(white, state: half, applyCrop: true)
        if cropped.width * 2 > framed.width + 1 || cropped.width * 2 < framed.width - 1 {
            return "crop after straighten is \(cropped.width) of \(framed.width)"
        }
        let exact = Engine.render(white, state: EditState(), applyCrop: true)
        if exact != white { return "zero straighten changed pixels" }
        return nil
    }

    private static func grade() -> String? {
        var state = EditState()
        state.exposure = 0.4
        state.look = .warm
        state.crop = CropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        state.straighten = 3
        state.annotations = [
            Annotation(id: UUID(), kind: .line, color: .red, weight: 0.01, points: [NormPoint(x: 0.2, y: 0.2), NormPoint(x: 0.3, y: 0.2)], text: ""),
        ]
        let saved = PlateGrade.capture(state, name: "Warm")
        var fresh = EditState()
        fresh.orientation = .right
        let applied = saved.applied(to: fresh)
        if applied.exposure != 0.4 || applied.look != .warm { return "grade fields" }
        if applied.crop != .full || applied.straighten != 0 || applied.orientation != .right {
            return "grade touched the frame"
        }
        if !applied.annotations.isEmpty { return "grade copied marks" }
        let defaults = UserDefaults(suiteName: "com.tim.plate.selftest")!
        defaults.removePersistentDomain(forName: "com.tim.plate.selftest")
        if PlateGrade.load(from: defaults) != nil { return "empty defaults had a grade" }
        saved.store(in: defaults)
        guard let loaded = PlateGrade.load(from: defaults) else { return "grade did not store" }
        if loaded != saved { return "stored grade changed" }
        PlateGrade.clear(from: defaults)
        if PlateGrade.load(from: defaults) != nil { return "grade was not cleared" }
        return nil
    }

    private static func nudgeAndDuplicate() -> String? {
        let model = AppModel()
        let id = UUID()
        model.addAnnotation(
            Annotation(
                id: id,
                kind: .line,
                color: .red,
                weight: 0.01,
                points: [NormPoint(x: 0.2, y: 0.2), NormPoint(x: 0.4, y: 0.2)],
                text: ""
            )
        )
        model.nudgeSelected(dx: 0.002, dy: 0)
        model.nudgeSelected(dx: 0.002, dy: 0)
        model.finishNudge()
        let moved = model.state.annotations[0].points[0]
        if abs(moved.x - 0.204) > 0.00001 || abs(moved.y - 0.2) > 0.00001 {
            return "nudge landed at \(moved.x)"
        }
        model.undo()
        if abs(model.state.annotations[0].points[0].x - 0.2) > 0.00001 {
            return "one nudge gesture did not undo together"
        }
        model.redo()
        model.duplicateSelectedAnnotation()
        if model.state.annotations.count != 2 { return "duplicate count" }
        if model.selectedAnnotationID == id { return "duplicate stayed on the original" }
        let copy = model.state.annotations[1].points[0]
        if abs(copy.x - 0.224) > 0.00001 || abs(copy.y - 0.22) > 0.00001 {
            return "duplicate offset \(copy.x), \(copy.y)"
        }
        model.undo()
        if model.state.annotations.count != 1 { return "undo duplicate" }
        return nil
    }

    private static func isRed(_ pixel: Pixel) -> Bool {
        Int(pixel.r) > 180 && Int(pixel.g) < 140 && Int(pixel.b) < 140
    }

    private static func pattern(width: Int, height: Int) -> PixelBuffer {
        var pixels = [Pixel]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(.rgb(UInt8((x * 40) % 256), UInt8((y * 25) % 256), UInt8((x + y) % 256)))
            }
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }
}
