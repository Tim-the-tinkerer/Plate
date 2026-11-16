import AppKit
import Foundation

enum CaptionSelfTest {
    static func run() -> String? {
        if let err = readerOrientation() { return err }
        if let err = fontsResolve() { return err }
        if let err = emptyIsIdentity() { return err }
        if let err = repeatable() { return err }
        if let err = dimensionsHeld() { return err }
        if let err = topSitsHigh() { return err }
        if let err = bottomSitsLow() { return err }
        if let err = bothLeaveTheMiddle() { return err }
        if let err = strokePaintsBlack() { return err }
        if let err = noStrokeSkipsBlack() { return err }
        if let err = largerPaintsMore() { return err }
        if let err = twoLinesAreTaller() { return err }
        if let err = uppercaseMatches() { return err }
        if let err = alignmentMovesInk() { return err }
        if let err = anchorMovesInk() { return err }
        if let err = colorParse() { return err }
        if let err = cliParse() { return err }
        if let err = cliRoundTrip() { return err }
        if let err = cliRefusesOverwrite() { return err }
        if let err = bottomMarginAddsWhiteBar() { return err }
        if let err = rightMarginAddsWhiteColumn() { return err }
        if let err = bottomCaptionSitsInTheBar() { return err }
        if let err = marginRemapKeepsThePhotoPoint() { return err }
        if let err = marginCLI() { return err }
        if let err = longBottomCaptionStaysInTheBar() { return err }
        if let err = sideCaptionStaysInTheColumn() { return err }
        if let err = pastedImageIsCapped() { return err }
        if let err = projectRoundTrip() { return err }
        if let err = projectRefusesOverwrite() { return err }
        if let err = undoHistory() { return err }
        return nil
    }

    private static let background = CaptionColor(r: 30 / 255, g: 80 / 255, b: 140 / 255)

    private static func readerOrientation() -> String? {
        guard let solid = ImageFile.solid(width: 4, height: 4, color: .init(r: 1, g: 0, b: 0)),
              let bytes = ImageFile.rgbaTopDown(solid)
        else { return "could not read a solid image" }
        let pixel = (bytes[0], bytes[1], bytes[2], bytes[3])
        if pixel.0 < 250 || pixel.1 > 5 || pixel.2 > 5 || pixel.3 < 250 {
            return "solid red read as \(pixel.0),\(pixel.1),\(pixel.2),\(pixel.3)"
        }
        guard let banded = ImageFile.banded(
            width: 8,
            height: 8,
            band: 2,
            top: CaptionColor(r: 1, g: 0, b: 0),
            rest: CaptionColor(r: 0, g: 0, b: 1)
        ), let bandBytes = ImageFile.rgbaTopDown(banded) else {
            return "could not build a banded image"
        }
        let top = sample(bandBytes, width: 8, x: 1, y: 0)
        let bottom = sample(bandBytes, width: 8, x: 1, y: 7)
        if top.0 < 250 || top.2 > 5 {
            return "visual top of the band was \(top.0),\(top.1),\(top.2), expected red"
        }
        if bottom.2 < 250 || bottom.0 > 5 {
            return "visual bottom of the band was \(bottom.0),\(bottom.1),\(bottom.2), expected blue"
        }
        return nil
    }

    private static func fontsResolve() -> String? {
        for font in CaptionFont.allCases {
            let name = font.resolvedPostScriptName
            if name.isEmpty {
                return "\(font.rawValue) did not resolve a font"
            }
            if font.nsFont(size: 18).pointSize < 17 {
                return "\(font.rawValue) ignored the requested size"
            }
        }
        return nil
    }

    private static func emptyIsIdentity() -> String? {
        guard let source = ImageFile.solid(width: 40, height: 24, color: background),
              let before = ImageFile.rgbaTopDown(source)
        else { return "empty test image failed" }
        let product = CaptionRenderer.render(
            source: source,
            marks: [CaptionMark.top(), CaptionMark.bottom()],
            flatten: false
        )
        guard let after = ImageFile.rgbaTopDown(product.image) else { return "empty render unreadable" }
        if before != after { return "empty captions changed the image" }
        if !product.hits.isEmpty { return "empty captions reported a hit box" }
        return nil
    }

    private static func repeatable() -> String? {
        guard let source = card(480, 320) else { return "repeat card failed" }
        let marks = [top("HELLO"), bottom("WORLD")]
        let a = CaptionRenderer.render(source: source, marks: marks, flatten: false)
        let b = CaptionRenderer.render(source: source, marks: marks, flatten: false)
        guard let left = ImageFile.rgbaTopDown(a.image),
              let right = ImageFile.rgbaTopDown(b.image)
        else { return "repeat render unreadable" }
        if left != right { return "the same captions rendered differently" }
        return nil
    }

    private static func dimensionsHeld() -> String? {
        guard let source = card(37, 19) else { return "odd card failed" }
        var mark = CaptionMark.top()
        mark.text = "HI"
        mark.size = 0.2
        let product = CaptionRenderer.render(source: source, marks: [mark], flatten: false)
        if product.image.width != 37 || product.image.height != 19 {
            return "dimensions became \(product.image.width)×\(product.image.height)"
        }
        return nil
    }

    private static func topSitsHigh() -> String? {
        guard let source = card(480, 360),
              let bytes = renderBytes(source, marks: [top("HELLO")])
        else { return "top render failed" }
        let ink = scan(bytes, width: 480, height: 360)
        if ink.white == 0 { return "top caption painted no white" }
        if ink.centroidY > 100 {
            return "top caption centroid y was \(fmt(ink.centroidY)), expected near the top"
        }
        if ink.maxY > 140 {
            return "top caption reached row \(ink.maxY)"
        }
        if countBackground(bytes, width: 480, y: 280, height: 70) != 480 * 70 {
            return "top caption painted into the bottom band"
        }
        return nil
    }

    private static func bottomSitsLow() -> String? {
        guard let source = card(480, 360),
              let bytes = renderBytes(source, marks: [bottom("WORLD")])
        else { return "bottom render failed" }
        let ink = scan(bytes, width: 480, height: 360)
        if ink.white == 0 { return "bottom caption painted no white" }
        if ink.centroidY < 260 {
            return "bottom caption centroid y was \(fmt(ink.centroidY)), expected near the bottom"
        }
        if countBackground(bytes, width: 480, y: 0, height: 70) != 480 * 70 {
            return "bottom caption painted into the top band"
        }
        return nil
    }

    private static func bothLeaveTheMiddle() -> String? {
        guard let source = card(480, 360),
              let bytes = renderBytes(source, marks: [top("HELLO"), bottom("WORLD")])
        else { return "both render failed" }
        let topBand = scan(bytes, width: 480, height: 360, y: 0, rows: 90)
        let bottomBand = scan(bytes, width: 480, height: 360, y: 270, rows: 90)
        if topBand.white == 0 || bottomBand.white == 0 {
            return "paired captions missed a band (top white \(topBand.white), bottom white \(bottomBand.white))"
        }
        if countBackground(bytes, width: 480, y: 150, height: 60) != 480 * 60 {
            return "paired captions painted the middle"
        }
        return nil
    }

    private static func strokePaintsBlack() -> String? {
        guard let source = card(480, 320),
              let bytes = renderBytes(source, marks: [top("STROKE")])
        else { return "stroke render failed" }
        let ink = scan(bytes, width: 480, height: 320)
        if ink.black < 20 { return "outline painted \(ink.black) black pixels" }
        if ink.white < 20 { return "fill painted \(ink.white) white pixels" }
        return nil
    }

    private static func noStrokeSkipsBlack() -> String? {
        guard let source = card(480, 320) else { return "nostroke card failed" }
        var mark = top("STROKE")
        mark.strokeWidth = 0
        guard let bytes = renderBytes(source, marks: [mark]) else { return "nostroke render failed" }
        let ink = scan(bytes, width: 480, height: 320)
        if ink.white == 0 { return "fill disappeared when the outline was off" }
        if ink.black != 0 { return "outline off still painted \(ink.black) black pixels" }
        return nil
    }

    private static func largerPaintsMore() -> String? {
        guard let source = card(480, 320) else { return "size card failed" }
        var small = top("MEME")
        small.size = 0.05
        var large = top("MEME")
        large.size = 0.14
        guard let smallBytes = renderBytes(source, marks: [small]),
              let largeBytes = renderBytes(source, marks: [large])
        else { return "size render failed" }
        let smallInk = scan(smallBytes, width: 480, height: 320)
        let largeInk = scan(largeBytes, width: 480, height: 320)
        if largeInk.count <= smallInk.count {
            return "larger type painted \(largeInk.count) pixels, smaller painted \(smallInk.count)"
        }
        return nil
    }

    private static func twoLinesAreTaller() -> String? {
        guard let source = card(640, 400) else { return "line card failed" }
        var one = top("AB")
        one.size = 0.08
        one.width = 0.8
        var two = one
        two.text = "A\nB"
        guard let oneBytes = renderBytes(source, marks: [one]),
              let twoBytes = renderBytes(source, marks: [two])
        else { return "line render failed" }
        let oneInk = scan(oneBytes, width: 640, height: 400)
        let twoInk = scan(twoBytes, width: 640, height: 400)
        let oneSpan = oneInk.maxY - oneInk.minY
        let twoSpan = twoInk.maxY - twoInk.minY
        if twoSpan <= oneSpan + 8 {
            return "two lines spanned \(twoSpan) rows, one line spanned \(oneSpan)"
        }
        return nil
    }

    private static func uppercaseMatches() -> String? {
        guard let source = card(480, 240) else { return "case card failed" }
        var lower = top("hi")
        lower.uppercase = true
        var upper = top("HI")
        upper.uppercase = true
        var raw = top("hi")
        raw.uppercase = false
        guard let lowerBytes = renderBytes(source, marks: [lower]),
              let upperBytes = renderBytes(source, marks: [upper]),
              let rawBytes = renderBytes(source, marks: [raw])
        else { return "case render failed" }
        if lowerBytes != upperBytes { return "uppercase hi and HI rendered differently" }
        if rawBytes == lowerBytes { return "lowercase hi matched the uppercase render" }
        return nil
    }

    private static func alignmentMovesInk() -> String? {
        guard let source = card(600, 200) else { return "align card failed" }
        func placed(_ align: CaptionAlign) -> Ink? {
            var mark = top("HI")
            mark.alignment = align
            mark.size = 0.12
            mark.width = 0.9
            guard let bytes = renderBytes(source, marks: [mark]) else { return nil }
            return scan(bytes, width: 600, height: 200)
        }
        guard let left = placed(.left), let center = placed(.center), let right = placed(.right) else {
            return "align render failed"
        }
        if !(left.minX < center.minX && center.minX < right.minX) {
            return "alignment minX left \(left.minX), center \(center.minX), right \(right.minX)"
        }
        return nil
    }

    private static func anchorMovesInk() -> String? {
        guard let source = card(500, 300) else { return "anchor card failed" }
        func placed(_ x: Double) -> Ink? {
            var mark = CaptionMark.extra(copying: CaptionMark.top())
            mark.text = "NO"
            mark.pin = .free
            mark.anchorX = x
            mark.anchorY = 0.5
            mark.size = 0.07
            guard let bytes = renderBytes(source, marks: [mark]) else { return nil }
            return scan(bytes, width: 500, height: 300)
        }
        guard let left = placed(0.2), let right = placed(0.8) else { return "anchor render failed" }
        if left.centroidX + 100 >= right.centroidX {
            return "anchors landed at \(fmt(left.centroidX)) and \(fmt(right.centroidX))"
        }
        let topRows = countBackground(
            renderBytes(source, marks: {
                var mark = CaptionMark.extra(copying: CaptionMark.top())
                mark.text = "NO"
                mark.pin = .free
                mark.anchorX = 0.5
                mark.anchorY = 0.85
                mark.size = 0.05
                return [mark]
            }()) ?? [],
            width: 500,
            y: 0,
            height: 12
        )
        if topRows != 500 * 12 { return "a low free caption painted the top row" }
        return nil
    }

    private static func colorParse() -> String? {
        guard let white = CaptionColor.parse("white"), white.matches(.white) else {
            return "white name failed"
        }
        guard let hex = CaptionColor.parse("#FFE14A") else { return "hex parse failed" }
        if hex.hex != "FFE14A" { return "hex normalized to \(hex.hex)" }
        if CaptionColor.parse("zz") != nil { return "zz was accepted as a color" }
        if CaptionColor.parse("FFF") != nil { return "short hex was accepted" }
        return nil
    }

    private static func cliParse() -> String? {
        do {
            let job = try CaptionCLI.parse([
                "caption", "photo.png",
                "--top", "HELLO",
                "--bottom", "WORLD",
                "--at", "0.25,0.7", "LOOK",
                "--font", "serif",
                "--size", "0.1",
                "--fill", "yellow",
                "--stroke", "000000",
                "--no-caps",
                "--align", "left",
                "-o", "out.png",
            ])
            if job.top != "HELLO" || job.bottom != "WORLD" { return "top or bottom was dropped" }
            if job.free.count != 1 || abs(job.free[0].x - 0.25) > 0.0001 || job.free[0].text != "LOOK" {
                return "free caption was parsed wrong"
            }
            if job.font != .serif || job.uppercase || job.alignment != .left {
                return "style flags were parsed wrong"
            }
            if job.output != "out.png" { return "output path was \(job.output ?? "nil")" }
            let marks = job.marks()
            if marks.count != 3 || marks[2].pin != .free { return "job did not build three marks" }
            if marks[0].uppercase { return "no-caps did not reach the marks" }
        } catch {
            return "parse failed: \(error.localizedDescription)"
        }

        do {
            _ = try CaptionCLI.parse(["caption", "photo.png", "--size", "2"])
            return "--size 2 was accepted"
        } catch {
            // expected
        }
        do {
            _ = try CaptionCLI.parse(["caption", "--font", "impact"])
            return "a font flag without an image was accepted"
        } catch {
            // expected
        }

        let output = CaptionPaths.defaultOutput(for: URL(fileURLWithPath: "/tmp/photo.png"), jpeg: false)
        if output.lastPathComponent != "photo-caption.png" {
            return "default name was \(output.lastPathComponent)"
        }
        return nil
    }

    private static func cliRoundTrip() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("caption-selftest-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            guard let source = card(320, 200) else { return "cli card failed" }
            let input = dir.appendingPathComponent("photo.png")
            let output = dir.appendingPathComponent("photo-caption.png")
            try ImageFile.write(source, to: input, jpeg: false)
            let before = try Data(contentsOf: input)
            _ = try CaptionCLI.execute([
                "caption", input.path,
                "--top", "HI",
                "--bottom", "THERE",
                "-o", output.path,
            ])
            let after = try Data(contentsOf: input)
            if before != after { return "cli rewrote the original" }
            guard FileManager.default.fileExists(atPath: output.path) else { return "cli wrote no file" }
            let loaded = try ImageFile.load(url: output)
            if loaded.image.width != 320 || loaded.image.height != 200 {
                return "cli output was \(loaded.image.width)×\(loaded.image.height)"
            }
            guard let bytes = ImageFile.rgbaTopDown(loaded.image) else { return "cli output unreadable" }
            let ink = scan(bytes, width: 320, height: 200)
            if ink.white == 0 { return "cli output had no white caption" }
            let header = [UInt8](try Data(contentsOf: output).prefix(8))
            if header != [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
                return "cli png header was wrong"
            }
        } catch {
            return "cli round trip: \(error.localizedDescription)"
        }
        return nil
    }

    private static func cliRefusesOverwrite() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("caption-selftest-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            guard let source = card(32, 24) else { return "overwrite card failed" }
            let input = dir.appendingPathComponent("photo.png")
            try ImageFile.write(source, to: input, jpeg: false)
            let before = try Data(contentsOf: input)
            do {
                _ = try CaptionCLI.execute([
                    "caption", input.path,
                    "--top", "NO",
                    "-o", input.path,
                ])
                return "cli overwrote the original"
            } catch {
                // expected
            }
            let after = try Data(contentsOf: input)
            if before != after { return "a refused overwrite changed the original" }
        } catch {
            return "overwrite check: \(error.localizedDescription)"
        }
        return nil
    }

    private static func bottomMarginAddsWhiteBar() -> String? {
        guard let photo = card(160, 80) else { return "margin photo failed" }
        let product = CaptionRenderer.render(
            source: photo,
            marks: [CaptionMark.top(), CaptionMark.bottom()],
            margins: CanvasMargins(bottom: 0.5),
            flatten: false
        )
        if product.image.width != 160 || product.image.height != 120 {
            return "bottom margin was \(product.image.width)×\(product.image.height), expected 160×120"
        }
        guard let bytes = ImageFile.rgbaTopDown(product.image) else { return "margin bytes failed" }
        if !isBackground(sample(bytes, width: 160, x: 8, y: 4)) {
            return "the top of a bottom margin lost the photo"
        }
        if !isWhite(sample(bytes, width: 160, x: 8, y: 110)) {
            return "the bottom bar was not white"
        }
        return nil
    }

    private static func rightMarginAddsWhiteColumn() -> String? {
        guard let photo = card(160, 80) else { return "column photo failed" }
        let product = CaptionRenderer.render(
            source: photo,
            marks: [],
            margins: CanvasMargins(right: 0.5),
            flatten: false
        )
        if product.image.width != 240 || product.image.height != 80 {
            return "right margin was \(product.image.width)×\(product.image.height), expected 240×80"
        }
        guard let bytes = ImageFile.rgbaTopDown(product.image) else { return "column bytes failed" }
        if !isBackground(sample(bytes, width: 240, x: 4, y: 40)) {
            return "the left of a right margin lost the photo"
        }
        if !isWhite(sample(bytes, width: 240, x: 230, y: 40)) {
            return "the right column was not white"
        }
        return nil
    }

    private static func bottomCaptionSitsInTheBar() -> String? {
        guard let photo = card(200, 100) else { return "bar card failed" }
        var top = CaptionMark.top()
        top.text = "HI"
        top.fill = CaptionColor(r: 1, g: 0.882, b: 0.290)
        top.strokeWidth = 0
        top.size = 0.12
        var bottom = CaptionMark.bottom()
        bottom.text = "JOKE"
        bottom.fill = .black
        bottom.strokeWidth = 0
        bottom.size = 0.12
        let product = CaptionRenderer.render(
            source: photo,
            marks: [top, bottom],
            margins: CanvasMargins(bottom: 1),
            flatten: false
        )
        if product.image.width != 200 || product.image.height != 200 {
            return "bar canvas was \(product.image.width)×\(product.image.height), expected 200×200"
        }
        guard let bytes = ImageFile.rgbaTopDown(product.image) else { return "bar unreadable" }
        if !isBackground(sample(bytes, width: 200, x: 2, y: 2)) {
            return "the photo corner was covered by the bar"
        }
        if !isWhite(sample(bytes, width: 200, x: 2, y: 198)) {
            return "the bar corner was not white"
        }
        var yellowN = 0
        var yellowY = 0
        var blackN = 0
        var blackY = 0
        for row in 0..<200 {
            for col in 0..<200 {
                let pixel = sample(bytes, width: 200, x: col, y: row)
                if pixel.0 > 180, pixel.1 > 140, pixel.2 < 140 {
                    yellowN += 1
                    yellowY += row
                }
                if pixel.0 < 80, pixel.1 < 80, pixel.2 < 80 {
                    blackN += 1
                    blackY += row
                }
            }
        }
        if yellowN < 15 { return "top caption painted no yellow on the photo" }
        if blackN < 15 { return "bottom caption painted no black in the bar" }
        let yellowCentroid = Double(yellowY) / Double(yellowN)
        let blackCentroid = Double(blackY) / Double(blackN)
        if yellowCentroid >= 100 {
            return "top caption centroid y was \(fmt(yellowCentroid)), expected on the photo"
        }
        if blackCentroid <= 100 {
            return "bottom caption centroid y was \(fmt(blackCentroid)), expected in the bar"
        }
        return nil
    }

    private static func longBottomCaptionStaysInTheBar() -> String? {
        guard let photo = card(240, 160) else { return "fit bar card failed" }
        var bottom = CaptionMark.bottom()
        bottom.text = "A longer caption that has to wrap inside the white bar"
        bottom.fill = .black
        bottom.strokeWidth = 0
        bottom.size = 0.18
        bottom.width = 0.92
        let product = CaptionRenderer.render(
            source: photo,
            marks: [bottom],
            margins: CanvasMargins(bottom: 0.35),
            flatten: false
        )
        let bar = Int((Double(photo.height) * 0.35).rounded())
        let canvasH = photo.height + bar
        if product.image.width != photo.width || product.image.height != canvasH {
            return "fit bar canvas was \(product.image.width)×\(product.image.height)"
        }
        guard let bytes = ImageFile.rgbaTopDown(product.image) else { return "fit bar unreadable" }
        var inkOnPhoto = 0
        var inkInBar = 0
        let photoBottom = photo.height - 3
        for row in 0..<canvasH {
            for col in 0..<photo.width {
                let pixel = sample(bytes, width: photo.width, x: col, y: row)
                guard pixel.0 < 80, pixel.1 < 80, pixel.2 < 80 else { continue }
                if row < photoBottom { inkOnPhoto += 1 } else if row >= photo.height { inkInBar += 1 }
            }
        }
        if inkInBar < 30 { return "long bottom caption did not paint the bar" }
        if inkOnPhoto > 0 { return "long bottom caption spilled \(inkOnPhoto) px onto the photo" }
        return nil
    }

    private static func sideCaptionStaysInTheColumn() -> String? {
        guard let photo = card(200, 140) else { return "fit column card failed" }
        var mark = CaptionMark.extra(copying: CaptionMark.top())
        mark.text = "Side caption that wraps down the white column"
        mark.pin = .free
        mark.anchorX = 0.83
        mark.anchorY = 0.45
        mark.fill = .black
        mark.strokeWidth = 0
        mark.size = 0.16
        mark.width = 0.92
        let product = CaptionRenderer.render(
            source: photo,
            marks: [mark],
            margins: CanvasMargins(right: 0.5),
            flatten: false
        )
        let column = Int((Double(photo.width) * 0.5).rounded())
        let canvasW = photo.width + column
        if product.image.width != canvasW || product.image.height != photo.height {
            return "fit column canvas was \(product.image.width)×\(product.image.height)"
        }
        guard let bytes = ImageFile.rgbaTopDown(product.image) else { return "fit column unreadable" }
        var inkOnPhoto = 0
        var inkInColumn = 0
        let photoRight = photo.width - 3
        for row in 0..<photo.height {
            for col in 0..<canvasW {
                let pixel = sample(bytes, width: canvasW, x: col, y: row)
                guard pixel.0 < 80, pixel.1 < 80, pixel.2 < 80 else { continue }
                if col < photoRight { inkOnPhoto += 1 } else if col >= photo.width { inkInColumn += 1 }
            }
        }
        if inkInColumn < 30 { return "side caption did not paint the column" }
        if inkOnPhoto > 0 { return "side caption spilled \(inkOnPhoto) px onto the photo" }
        let anchor = CanvasMargins(right: 0.5)
            .layout(photoWidth: photo.width, photoHeight: photo.height, maxSide: 8192)
            .anchor(in: .right)
        if anchor.x <= 0.66 || abs(anchor.y - 0.5) > 0.001 {
            return "right column anchor was \(fmt(anchor.x)), \(fmt(anchor.y))"
        }
        return nil
    }

    private static func marginRemapKeepsThePhotoPoint() -> String? {
        let (x, y) = CanvasMargins().remap(anchorX: 0.5, anchorY: 0.5, to: CanvasMargins(bottom: 1))
        if abs(x - 0.5) > 0.001 || abs(y - 0.25) > 0.001 {
            return "remap moved the center to \(fmt(x)), \(fmt(y))"
        }
        let low = CanvasMargins().remap(anchorX: 0.5, anchorY: 0.92, to: CanvasMargins(bottom: 0.5))
        let expected = 0.92 / 1.5
        if abs(low.0 - 0.5) > 0.001 || abs(low.1 - expected) > 0.001 {
            return "remap of 0.92 was \(fmt(low.1)), expected \(fmt(expected))"
        }
        if low.1 > 1 / 1.5 {
            return "a caption near the bottom of the photo left the photo"
        }
        return nil
    }

    private static func marginCLI() -> String? {
        do {
            let job = try CaptionCLI.parse([
                "caption",
                "--margin-bottom", "0.4",
                "--margin-right", "0.25",
                "--margin-top", "0.1",
                "--margin-left", "0",
                "--mat", "#112233",
                "photo.png",
                "--bottom", "joke",
            ])
            if job.input != "photo.png" { return "margin flags hid the input, got \(job.input)" }
            if abs(job.margins.bottom - 0.4) > 0.0001 || abs(job.margins.right - 0.25) > 0.0001 {
                return "margin amounts were parsed wrong"
            }
            if abs(job.margins.top - 0.1) > 0.0001 || job.margins.left != 0 {
                return "top or left margin was parsed wrong"
            }
            if job.margins.color.hex != "112233" { return "mat color was \(job.margins.color.hex)" }
            if job.bottom != "joke" { return "bottom caption was dropped beside a margin" }
        } catch {
            return "margin parse failed: \(error.localizedDescription)"
        }
        do {
            _ = try CaptionCLI.parse(["caption", "photo.png", "--margin-bottom", "2"])
            return "--margin-bottom 2 was accepted"
        } catch {
            // expected
        }
        do {
            _ = try CaptionCLI.parse(["caption", "photo.png", "--mat", "zz"])
            return "--mat zz was accepted"
        } catch {
            // expected
        }
        return nil
    }

    private static func card(_ width: Int, _ height: Int) -> CGImage? {
        ImageFile.solid(width: width, height: height, color: background)
    }

    private static func top(_ text: String) -> CaptionMark {
        var mark = CaptionMark.top()
        mark.text = text
        mark.size = 0.07
        return mark
    }

    private static func bottom(_ text: String) -> CaptionMark {
        var mark = CaptionMark.bottom()
        mark.text = text
        mark.size = 0.07
        return mark
    }

    private static func renderBytes(_ source: CGImage, marks: [CaptionMark]) -> [UInt8]? {
        let product = CaptionRenderer.render(source: source, marks: marks, flatten: false)
        return ImageFile.rgbaTopDown(product.image)
    }

    private static func sample(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }

    private struct Ink {
        var minX = Int.max
        var minY = Int.max
        var maxX = 0
        var maxY = 0
        var count = 0
        var white = 0
        var black = 0
        var sumX = 0
        var sumY = 0
        var centroidX: Double { count == 0 ? 0 : Double(sumX) / Double(count) }
        var centroidY: Double { count == 0 ? 0 : Double(sumY) / Double(count) }
    }

    private static func scan(_ bytes: [UInt8], width: Int, height: Int, y: Int = 0, rows: Int? = nil) -> Ink {
        var ink = Ink()
        let rowCount = rows ?? height
        let yEnd = min(height, y + rowCount)
        guard !bytes.isEmpty else { return ink }
        for row in y..<yEnd {
            for col in 0..<width {
                let pixel = sample(bytes, width: width, x: col, y: row)
                if isBackground(pixel) { continue }
                ink.count += 1
                ink.sumX += col
                ink.sumY += row
                ink.minX = min(ink.minX, col)
                ink.minY = min(ink.minY, row)
                ink.maxX = max(ink.maxX, col)
                ink.maxY = max(ink.maxY, row)
                if isWhite(pixel) { ink.white += 1 }
                if isBlack(pixel) { ink.black += 1 }
            }
        }
        if ink.count == 0 {
            ink.minX = 0
            ink.minY = 0
        }
        return ink
    }

    private static func countBackground(_ bytes: [UInt8], width: Int, y: Int, height: Int) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var count = 0
        for row in y..<(y + height) {
            for col in 0..<width {
                if isBackground(sample(bytes, width: width, x: col, y: row)) {
                    count += 1
                }
            }
        }
        return count
    }

    private static func pastedImageIsCapped() -> String? {
        guard let huge = ImageFile.solid(width: 9000, height: 100, color: background) else {
            return "could not build a 9000-wide image"
        }
        do {
            let pasted = try ImageFile.load(nsImage: ImageFile.nsImage(huge))
            if !pasted.capped {
                return "a 9000-wide paste was not capped"
            }
            if pasted.image.width != 8192 || pasted.image.height != 91 {
                return "paste cap became \(pasted.image.width)×\(pasted.image.height), expected 8192×91"
            }
            let png = try ImageFile.pngData(huge)
            let fromData = try ImageFile.load(data: png)
            if !fromData.capped || fromData.image.width != 8192 || fromData.image.height != 91 {
                return "file-data cap became \(fromData.image.width)×\(fromData.image.height)"
            }
        } catch {
            return "paste cap failed: \(error.localizedDescription)"
        }
        guard let small = ImageFile.solid(width: 40, height: 20, color: background) else {
            return "could not build a small image"
        }
        do {
            let loaded = try ImageFile.load(nsImage: ImageFile.nsImage(small))
            if loaded.capped || loaded.image.width != 40 || loaded.image.height != 20 {
                return "a 40×20 paste became \(loaded.image.width)×\(loaded.image.height), capped \(loaded.capped)"
            }
        } catch {
            return "small paste failed: \(error.localizedDescription)"
        }
        return nil
    }

    private static func projectRoundTrip() -> String? {
        let model = CaptionModel()
        guard let bottom = model.marks.first(where: { $0.role == .bottom }) else {
            return "a new canvas has no bottom line"
        }
        model.setText(bottom.id, "KEEP THIS SENTENCE")
        model.applyMarginPreset(.bottom)
        if abs(model.margins.bottom - 0.45) > 0.001 {
            return "bottom preset was \(fmt(model.margins.bottom))"
        }
        let data: Data
        let photo: LoadedImage
        do {
            data = try model.projectData()
            let decoded = try CaptionProject.decode(data)
            photo = try ImageFile.load(data: decoded.imagePNG)
        } catch {
            return "project encode failed: \(error.localizedDescription)"
        }
        if photo.image.width != 1080 || photo.image.height != 1080 {
            return "project photo became \(photo.image.width)×\(photo.image.height)"
        }
        model.setText(bottom.id, "CHANGED")
        do {
            try model.readProject(data)
        } catch {
            return "project read failed: \(error.localizedDescription)"
        }
        let restored = model.marks.first { $0.role == .bottom }?.text ?? ""
        if restored != "KEEP THIS SENTENCE" {
            return "reopened project said \(restored)"
        }
        if abs(model.margins.bottom - 0.45) > 0.001 {
            return "reopened margin was \(fmt(model.margins.bottom))"
        }
        if model.pixelWidth != 1080 || model.pixelHeight != 1566 {
            return "reopened canvas was \(model.pixelWidth)×\(model.pixelHeight)"
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("caption-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("Starfleet.caption")
            try data.write(to: url)
            model.setText(bottom.id, "CHANGED AGAIN")
            model.load(url: url)
        } catch {
            return "project file failed: \(error.localizedDescription)"
        }
        if model.status != "Opened Starfleet.caption." {
            return "opening a project said \(model.status)"
        }
        let opened = model.marks.first { $0.role == .bottom }?.text ?? ""
        if opened != "KEEP THIS SENTENCE" {
            return "opened project said \(opened)"
        }
        return nil
    }

    private static func projectRefusesOverwrite() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("caption-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let image = ImageFile.solid(width: 32, height: 24, color: background) else {
                return "overwrite card failed"
            }
            let url = dir.appendingPathComponent("photo.png")
            try ImageFile.write(image, to: url, jpeg: false)
            let before = try Data(contentsOf: url)
            let model = CaptionModel()
            model.load(url: url)
            if !model.status.hasPrefix("Opened photo.png") {
                return "could not open the photo: \(model.status)"
            }
            model.saveProject(to: url)
            if model.status != "That would overwrite the original. Choose another name." {
                return "saving a project onto the photo said \(model.status)"
            }
            let after = try Data(contentsOf: url)
            if before != after {
                return "the overwrite guard changed the original"
            }
        } catch {
            return "overwrite guard failed: \(error.localizedDescription)"
        }
        return nil
    }

    private static func undoHistory() -> String? {
        let pin = CaptionModel()
        guard let bottom = pin.marks.first(where: { $0.role == .bottom }) else {
            return "undo test has no bottom line"
        }
        pin.selectedID = bottom.id
        pin.setPin(.free)
        if pin.mark(id: bottom.id)?.pin != .free {
            return "pin did not free the bottom line"
        }
        pin.undo()
        if pin.mark(id: bottom.id)?.pin != .bottom {
            return "undo did not restore the bottom pin"
        }
        if pin.canUndo {
            return "undo left another caption step"
        }
        pin.redo()
        if pin.mark(id: bottom.id)?.pin != .free {
            return "redo did not free the bottom line"
        }

        let drag = CaptionModel()
        guard let line = drag.marks.first(where: { $0.role == .bottom }) else {
            return "drag test has no bottom line"
        }
        drag.setText(line.id, "HELLO")
        if !drag.hits.contains(where: { $0.id == line.id }) {
            return "the bottom line had no hit box"
        }
        let fitted = drag.previewPixelSize
        drag.dragChanged(id: line.id, translation: CGSize(width: 30, height: 12), fitted: fitted)
        drag.dragChanged(id: line.id, translation: CGSize(width: 80, height: 24), fitted: fitted)
        drag.dragEnded()
        if drag.mark(id: line.id)?.pin != .free {
            return "dragging did not free the caption"
        }
        drag.undo()
        if drag.mark(id: line.id)?.pin != .bottom {
            return "one undo did not put the caption back"
        }
        if drag.canUndo {
            return "a drag or a keystroke recorded an extra undo step"
        }
        drag.redo()
        if drag.mark(id: line.id)?.pin != .free {
            return "redo did not restore the move"
        }

        let slider = CaptionModel()
        guard let top = slider.marks.first(where: { $0.role == .top }) else {
            return "slider test has no top line"
        }
        slider.selectedID = top.id
        let original = slider.mark(id: top.id)?.size ?? -1
        slider.beginGesture("Size")
        slider.binding(\.size).wrappedValue = 0.12
        slider.binding(\.size).wrappedValue = 0.18
        slider.endGesture()
        if abs((slider.mark(id: top.id)?.size ?? -1) - 0.18) > 0.0001 {
            return "the size slider did not apply"
        }
        slider.undo()
        if abs((slider.mark(id: top.id)?.size ?? -1) - original) > 0.0001 {
            return "one undo did not restore the size"
        }
        if slider.canUndo {
            return "the size slider recorded more than one step"
        }

        let mat = CaptionModel()
        guard let caption = mat.marks.first(where: { $0.role == .top }) else {
            return "margin undo has no top line"
        }
        mat.selectedID = caption.id
        mat.setPin(.free)
        let anchor = mat.mark(id: caption.id)?.anchorY ?? -1
        mat.applyMarginPreset(.bottom)
        mat.undo()
        if mat.margins.bottom > 0.001 {
            return "undo did not clear the margin"
        }
        let restored = mat.mark(id: caption.id)?.anchorY ?? -1
        if abs(restored - anchor) > 0.0001 {
            return "undo moved the caption from \(fmt(anchor)) to \(fmt(restored))"
        }
        return nil
    }

    private static func isBackground(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        abs(Int(pixel.0) - 30) <= 8 && abs(Int(pixel.1) - 80) <= 8 && abs(Int(pixel.2) - 140) <= 12
    }

    private static func isWhite(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        pixel.0 > 230 && pixel.1 > 230 && pixel.2 > 230
    }

    private static func isBlack(_ pixel: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        pixel.0 < 35 && pixel.1 < 35 && pixel.2 < 35
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
