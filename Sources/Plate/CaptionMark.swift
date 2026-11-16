import AppKit
import CoreGraphics
import Foundation

struct CaptionColor: Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let white = CaptionColor(r: 1, g: 1, b: 1)
    static let black = CaptionColor(r: 0, g: 0, b: 0)
    static let canvas = CaptionColor(r: 0.086, g: 0.086, b: 0.086)

    static let swatches: [(name: String, color: CaptionColor)] = [
        ("White", .white),
        ("Black", .black),
        ("Yellow", CaptionColor(r: 1, g: 0.882, b: 0.290)),
        ("Red", CaptionColor(r: 0.886, g: 0.239, b: 0.239)),
        ("Orange", CaptionColor(r: 0.941, g: 0.541, b: 0.141)),
        ("Green", CaptionColor(r: 0.235, g: 0.710, b: 0.416)),
        ("Cyan", CaptionColor(r: 0.180, g: 0.784, b: 0.839)),
        ("Blue", CaptionColor(r: 0.235, g: 0.435, b: 0.878)),
        ("Pink", CaptionColor(r: 0.910, g: 0.353, b: 0.627)),
        ("Purple", CaptionColor(r: 0.541, g: 0.353, b: 0.878)),
    ]

    private static let names: [String: CaptionColor] = {
        var map: [String: CaptionColor] = [
            "white": .white,
            "black": .black,
        ]
        for item in swatches {
            map[item.name.lowercased()] = item.color
        }
        return map
    }()

    var hex: String {
        String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    func matches(_ other: CaptionColor) -> Bool {
        abs(r - other.r) < 0.01 && abs(g - other.g) < 0.01 && abs(b - other.b) < 0.01
    }

    static func parse(_ raw: String) -> CaptionColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = names[trimmed.lowercased()] {
            return named
        }
        var hex = trimmed
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        guard let value = Int(hex, radix: 16) else { return nil }
        return CaptionColor(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    private func byte(_ channel: Double) -> Int {
        Int((min(1, max(0, channel)) * 255).rounded())
    }
}

enum CaptionFont: String, CaseIterable, Identifiable, Equatable {
    case impact
    case condensed
    case sans
    case serif
    case mono
    case marker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .impact: return "Impact"
        case .condensed: return "Condensed"
        case .sans: return "Sans"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .marker: return "Marker"
        }
    }

    private static let candidates: [CaptionFont: [String]] = [
        .impact: ["Impact", "Arial-Black", "HelveticaNeue-CondensedBlack", "Helvetica-Bold"],
        .condensed: ["HelveticaNeue-CondensedBlack", "AvenirNextCondensed-Heavy", "ArialNarrow-Bold", "Impact"],
        .sans: ["HelveticaNeue-Bold", "Arial-BoldMT", "AvenirNext-Heavy", "Helvetica-Bold"],
        .serif: ["Georgia-Bold", "TimesNewRomanPS-BoldMT", "Times-Bold"],
        .mono: ["Menlo-Bold", "CourierNewPS-BoldMT", "Courier-Bold"],
        .marker: ["MarkerFelt-Wide", "Noteworthy-Bold", "BradleyHandITCTT-Bold"],
    ]

    func nsFont(size: CGFloat) -> NSFont {
        let safe = max(4, size)
        for name in Self.candidates[self] ?? [] {
            if let font = NSFont(name: name, size: safe) {
                return font
            }
        }
        return NSFont.boldSystemFont(ofSize: safe)
    }

    var resolvedPostScriptName: String {
        nsFont(size: 12).fontName
    }

    static func parse(_ raw: String) -> CaptionFont? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CaptionFont(rawValue: key)
    }
}

enum CaptionAlign: String, CaseIterable, Identifiable, Equatable {
    case left
    case center
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    static func parse(_ raw: String) -> CaptionAlign? {
        CaptionAlign(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum CaptionPin: String, Equatable {
    case top
    case bottom
    case free
}

enum CaptionRole: String, Equatable {
    case top
    case bottom
    case extra

    var title: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .extra: return "Text"
        }
    }
}

struct CanvasMargins: Equatable {
    var top: Double = 0
    var bottom: Double = 0
    var left: Double = 0
    var right: Double = 0
    var color: CaptionColor = .white

    static let maxFraction = 1.5

    var isEmpty: Bool {
        top <= 0.0001 && bottom <= 0.0001 && left <= 0.0001 && right <= 0.0001
    }

    func clamped() -> CanvasMargins {
        var copy = self
        copy.top = Self.clamp(top)
        copy.bottom = Self.clamp(bottom)
        copy.left = Self.clamp(left)
        copy.right = Self.clamp(right)
        return copy
    }

    func sameEdges(as other: CanvasMargins) -> Bool {
        let a = clamped()
        let b = other.clamped()
        return abs(a.top - b.top) < 0.001
            && abs(a.bottom - b.bottom) < 0.001
            && abs(a.left - b.left) < 0.001
            && abs(a.right - b.right) < 0.001
    }

    /// Keep a free caption on the same spot of the photo when the mat changes.
    /// Anchors are 0...1 on the whole canvas, y grows downward.
    func remap(anchorX: Double, anchorY: Double, to newer: CanvasMargins) -> (Double, Double) {
        let old = clamped()
        let new = newer.clamped()
        let oldWidth = 1 + old.left + old.right
        let oldHeight = 1 + old.top + old.bottom
        let photoX = anchorX * oldWidth - old.left
        let photoY = anchorY * oldHeight - old.top
        let newWidth = 1 + new.left + new.right
        let newHeight = 1 + new.top + new.bottom
        return (
            min(1, max(0, (new.left + photoX) / newWidth)),
            min(1, max(0, (new.top + photoY) / newHeight))
        )
    }

    /// Pixel layout before drawing. Core Graphics y grows upward, so the photo's
    /// origin y is the bottom mat, not the top mat.
    func layout(photoWidth: Int, photoHeight: Int, maxSide: Int) -> CanvasLayout {
        let m = clamped()
        let left0 = Int((Double(photoWidth) * m.left).rounded())
        let right0 = Int((Double(photoWidth) * m.right).rounded())
        let top0 = Int((Double(photoHeight) * m.top).rounded())
        let bottom0 = Int((Double(photoHeight) * m.bottom).rounded())
        let rawWidth = max(1, photoWidth + left0 + right0)
        let rawHeight = max(1, photoHeight + top0 + bottom0)
        let long = max(rawWidth, rawHeight)
        let scale = long > maxSide ? Double(maxSide) / Double(long) : 1
        func px(_ value: Int) -> Int {
            max(0, Int((Double(value) * scale).rounded()))
        }
        let contentWidth = max(1, px(photoWidth))
        let contentHeight = max(1, px(photoHeight))
        let left = px(left0)
        let right = px(right0)
        let top = px(top0)
        let bottom = px(bottom0)
        return CanvasLayout(
            width: max(1, left + contentWidth + right),
            height: max(1, top + contentHeight + bottom),
            contentWidth: contentWidth,
            photo: CGRect(x: left, y: bottom, width: contentWidth, height: contentHeight)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(maxFraction, max(0, value))
    }
}

struct CanvasLayout: Equatable {
    var width: Int
    var height: Int
    var contentWidth: Int
    /// Photo rect in Core Graphics points, origin at the bottom left.
    var photo: CGRect

    /// The roomiest margin that is at least 8 px thick, if any.
    func largestMargin() -> MarginEdge? {
        let canvasW = Double(max(width, 1))
        let canvasH = Double(max(height, 1))
        let bottom = Double(photo.minY)
        let top = canvasH - Double(photo.maxY)
        let left = Double(photo.minX)
        let right = canvasW - Double(photo.maxX)
        let candidates: [(MarginEdge, Double, Double)] = [
            (.bottom, bottom, bottom * canvasW),
            (.top, top, top * canvasW),
            (.left, left, left * canvasH),
            (.right, right, right * canvasH),
        ]
        return candidates.filter { $0.1 >= 8 }.max { $0.2 < $1.2 }?.0
    }

    /// Center of a margin, as a free-caption anchor. Y grows downward.
    func anchor(in edge: MarginEdge) -> (x: Double, y: Double) {
        let canvasW = Double(max(width, 1))
        let canvasH = Double(max(height, 1))
        let midX = (Double(photo.minX) + Double(photo.width) / 2) / canvasW
        switch edge {
        case .bottom:
            let bar = Double(photo.minY)
            return (midX, 1 - (bar / 2) / canvasH)
        case .top:
            let bar = canvasH - Double(photo.maxY)
            return (midX, (bar / 2) / canvasH)
        case .left:
            return ((Double(photo.minX) / 2) / canvasW, 0.5)
        case .right:
            let right = canvasW - Double(photo.maxX)
            return ((Double(photo.maxX) + right / 2) / canvasW, 0.5)
        }
    }
}

enum MarginEdge {
    case top
    case bottom
    case left
    case right
}

enum MarginPreset: String {
    case none
    case bottom
    case right
    case left

    var margins: CanvasMargins {
        switch self {
        case .none:
            return CanvasMargins()
        case .bottom:
            return CanvasMargins(bottom: 0.45)
        case .right:
            return CanvasMargins(right: 0.5)
        case .left:
            return CanvasMargins(left: 0.5)
        }
    }

    var title: String {
        switch self {
        case .none: return "None"
        case .bottom: return "Bottom"
        case .right: return "Right"
        case .left: return "Left"
        }
    }
}

enum BlankKind: String {
    case square
    case wide
    case story

    var size: (width: Int, height: Int) {
        switch self {
        case .square: return (1080, 1080)
        case .wide: return (1920, 1080)
        case .story: return (1080, 1920)
        }
    }

    var title: String {
        switch self {
        case .square: return "Square"
        case .wide: return "Wide"
        case .story: return "Story"
        }
    }

    var fileName: String {
        switch self {
        case .square: return "Square.png"
        case .wide: return "Wide.png"
        case .story: return "Story.png"
        }
    }
}

struct CaptionMark: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: CaptionRole
    var text: String = ""
    var pin: CaptionPin
    var font: CaptionFont = .impact
    var size: Double = 0.08
    var width: Double = 0.92
    var fill: CaptionColor = .white
    var stroke: CaptionColor = .black
    var strokeWidth: Double = 0.16
    var alignment: CaptionAlign = .center
    var uppercase: Bool = true
    var anchorX: Double = 0.5
    var anchorY: Double = 0.5

    var hasVisibleText: Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }

    var previewLine: String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if line.isEmpty { return "Empty" }
        if line.count > 42 { return String(line.prefix(41)) + "…" }
        return line
    }

    static func top() -> CaptionMark {
        CaptionMark(role: .top, pin: .top, anchorY: 0.12)
    }

    static func bottom() -> CaptionMark {
        CaptionMark(role: .bottom, pin: .bottom, anchorY: 0.88)
    }

    static func extra(copying style: CaptionMark) -> CaptionMark {
        var mark = style
        mark.id = UUID()
        mark.role = .extra
        mark.pin = .free
        mark.text = "TEXT"
        mark.anchorX = 0.5
        mark.anchorY = 0.5
        return mark
    }

    mutating func applyMemeStyle() {
        font = .impact
        size = 0.08
        width = 0.92
        fill = .white
        stroke = .black
        strokeWidth = 0.16
        alignment = .center
        uppercase = true
    }
}

struct CaptionHit: Identifiable, Equatable {
    var id: UUID
    /// Ink bounds in preview pixels. Origin is the top left, y grows downward.
    var rect: CGRect
    /// Ink center, 0...1, y grows downward.
    var center: CGPoint
}

enum CaptionPaths {
    static let projectExtension = "caption"

    static func isProject(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == projectExtension
    }

    static func suggestProject(sourceURL: URL?, imageName: String) -> String {
        let stem: String
        if let sourceURL {
            stem = sourceURL.deletingPathExtension().lastPathComponent
        } else {
            stem = (imageName as NSString).deletingPathExtension
        }
        let clean = stem.isEmpty ? "caption" : stem
        return "\(clean).\(projectExtension)"
    }

    static func suggest(sourceURL: URL?, imageName: String, jpeg: Bool) -> String {
        let stem: String
        if let sourceURL {
            stem = sourceURL.deletingPathExtension().lastPathComponent
        } else {
            stem = (imageName as NSString).deletingPathExtension
        }
        let clean = stem.isEmpty ? "caption" : stem
        return "\(clean)-caption.\(jpeg ? "jpg" : "png")"
    }

    static func defaultOutput(for input: URL, jpeg: Bool) -> URL {
        let name = suggest(sourceURL: input, imageName: "", jpeg: jpeg)
        let output = input.deletingLastPathComponent().appendingPathComponent(name)
        if sameFile(input, output) {
            let stem = input.deletingPathExtension().lastPathComponent
            let fallback = "\(stem)-caption-2.\(jpeg ? "jpg" : "png")"
            return input.deletingLastPathComponent().appendingPathComponent(fallback)
        }
        return output
    }

    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path
            == b.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
