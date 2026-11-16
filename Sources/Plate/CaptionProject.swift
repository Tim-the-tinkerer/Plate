import Foundation
import UniformTypeIdentifiers

enum CaptionFiles {
    static var projectType: UTType {
        UTType("com.tim.caption.project")
            ?? UTType(filenameExtension: CaptionPaths.projectExtension)
            ?? .json
    }
}

enum ProjectError: LocalizedError {
    case newer
    case damaged
    case noImage

    var errorDescription: String? {
        switch self {
        case .newer:
            return "That project is from a newer Caption."
        case .damaged:
            return "That project file is damaged."
        case .noImage:
            return "Nothing to save."
        }
    }
}

/// One editable Caption document. The photo is stored inside the file, so
/// reopening it does not depend on the original image still being in place.
struct CaptionProject: Codable {
    static let formatVersion = 1

    var format: Int = formatVersion
    var imageName: String
    var imagePNG: Data
    var margins: MarginRecord
    var selected: UUID?
    var marks: [MarkRecord]

    struct MarginRecord: Codable {
        var top: Double = 0
        var bottom: Double = 0
        var left: Double = 0
        var right: Double = 0
        var color: String = "FFFFFF"
    }

    struct MarkRecord: Codable {
        var id: UUID
        var role: String
        var text: String
        var pin: String
        var font: String
        var size: Double
        var width: Double
        var fill: String
        var stroke: String
        var strokeWidth: Double
        var align: String
        var caps: Bool
        var x: Double
        var y: Double
    }

    init(imageName: String, imagePNG: Data, margins: CanvasMargins, selected: UUID?, marks: [CaptionMark]) {
        self.imageName = imageName
        self.imagePNG = imagePNG
        self.margins = MarginRecord(
            top: margins.top,
            bottom: margins.bottom,
            left: margins.left,
            right: margins.right,
            color: margins.color.hex
        )
        self.selected = selected
        self.marks = marks.map(MarkRecord.init)
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> CaptionProject {
        let decoder = JSONDecoder()
        let project: CaptionProject
        do {
            project = try decoder.decode(CaptionProject.self, from: data)
        } catch {
            throw ProjectError.damaged
        }
        guard project.format == formatVersion else { throw ProjectError.newer }
        guard !project.imagePNG.isEmpty else { throw ProjectError.noImage }
        return project
    }

    func canvasMargins() -> CanvasMargins {
        var margins = CanvasMargins(
            top: self.margins.top,
            bottom: self.margins.bottom,
            left: self.margins.left,
            right: self.margins.right
        )
        if let color = CaptionColor.parse(self.margins.color) {
            margins.color = color
        }
        return margins.clamped()
    }

    func captionMarks() -> [CaptionMark] {
        marks.map { $0.mark() }
    }
}

private extension CaptionProject.MarkRecord {
    init(_ mark: CaptionMark) {
        id = mark.id
        role = mark.role.rawValue
        text = mark.text
        pin = mark.pin.rawValue
        font = mark.font.rawValue
        size = mark.size
        width = mark.width
        fill = mark.fill.hex
        stroke = mark.stroke.hex
        strokeWidth = mark.strokeWidth
        align = mark.alignment.rawValue
        caps = mark.uppercase
        x = mark.anchorX
        y = mark.anchorY
    }

    func mark() -> CaptionMark {
        var mark = CaptionMark(
            id: id,
            role: CaptionRole(rawValue: role) ?? .extra,
            pin: CaptionPin(rawValue: pin) ?? .free
        )
        mark.text = text
        mark.font = CaptionFont(rawValue: font) ?? .impact
        mark.size = size
        mark.width = width
        mark.fill = CaptionColor.parse(fill) ?? .white
        mark.stroke = CaptionColor.parse(stroke) ?? .black
        mark.strokeWidth = strokeWidth
        mark.alignment = CaptionAlign(rawValue: align) ?? .center
        mark.uppercase = caps
        mark.anchorX = min(1, max(0, x))
        mark.anchorY = min(1, max(0, y))
        return mark
    }
}
