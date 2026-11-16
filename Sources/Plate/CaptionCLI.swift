import Foundation

enum CaptionCLIError: LocalizedError {
    case missingInput
    case missingValue(String)
    case unknownFlag(String)
    case badFont(String)
    case badAlign(String)
    case badColor(String)
    case badNumber(String, String)
    case badPoint(String)
    case overwrite
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Missing input image."
        case .missingValue(let flag):
            return "\(flag) needs a value."
        case .unknownFlag(let flag):
            return "Unknown option \(flag)."
        case .badFont(let raw):
            return "Unknown --font \(raw). Use impact, condensed, sans, serif, mono, or marker."
        case .badAlign(let raw):
            return "Unknown --align \(raw). Use left, center, or right."
        case .badColor(let raw):
            return "Could not read color \(raw). Use RRGGBB or a name such as white."
        case .badNumber(let flag, let raw):
            return "\(flag) could not read \(raw)."
        case .badPoint(let raw):
            return "--at needs x,y between 0 and 1, then the caption. Got \(raw)."
        case .overwrite:
            return "Refusing to overwrite the original image."
        case .emptyOutput:
            return "Output path is empty."
        }
    }
}

struct CaptionJob {
    var input: String
    var output: String?
    var jpeg: Bool = false
    var top: String?
    var bottom: String?
    var free: [(x: Double, y: Double, text: String)] = []
    var font: CaptionFont = .impact
    var size: Double = 0.08
    var width: Double = 0.92
    var fill: CaptionColor = .white
    var stroke: CaptionColor = .black
    var strokeWidth: Double = 0.16
    var alignment: CaptionAlign = .center
    var uppercase: Bool = true
    var margins = CanvasMargins()

    func marks() -> [CaptionMark] {
        var topMark = CaptionMark.top()
        topMark.text = top ?? ""
        style(&topMark)
        var bottomMark = CaptionMark.bottom()
        bottomMark.text = bottom ?? ""
        style(&bottomMark)
        let extras: [CaptionMark] = free.map { item in
            var mark = CaptionMark.extra(copying: topMark)
            mark.text = item.text
            mark.pin = .free
            mark.anchorX = item.x
            mark.anchorY = item.y
            style(&mark)
            return mark
        }
        return [topMark, bottomMark] + extras
    }

    func resolveOutput(input: URL) throws -> URL {
        let jpegOut: Bool
        if let output, !output.isEmpty {
            let ext = URL(fileURLWithPath: output).pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" {
                jpegOut = true
            } else if ext == "png" {
                jpegOut = false
            } else {
                jpegOut = jpeg
            }
        } else {
            jpegOut = jpeg
        }
        let url: URL
        if let output {
            if output.isEmpty { throw CaptionCLIError.emptyOutput }
            url = URL(fileURLWithPath: output)
        } else {
            url = CaptionPaths.defaultOutput(for: input, jpeg: jpegOut)
        }
        if CaptionPaths.sameFile(input, url) {
            throw CaptionCLIError.overwrite
        }
        return url
    }

    private func style(_ mark: inout CaptionMark) {
        mark.font = font
        mark.size = size
        mark.width = width
        mark.fill = fill
        mark.stroke = stroke
        mark.strokeWidth = strokeWidth
        mark.alignment = alignment
        mark.uppercase = uppercase
    }
}

enum CaptionCLI {
    /// True for a caption flag or a bare image path. Plate does not route on this.
    /// A path with no caption flag stays an edit and writes INPUT-edited.png.
    static func wantsCLI(_ args: [String]) -> Bool {
        if args.contains(where: { valueFlags.contains($0) || boolFlags.contains($0) }) {
            return true
        }
        return positionalInput(in: args) != nil
    }

    /// True when the command is asking for words or a mat, rather than a grade.
    static func hasWork(_ args: [String]) -> Bool {
        let flags: Set<String> = [
            "--top", "--bottom", "--at", "--font", "--size", "--width",
            "--fill", "--stroke", "--stroke-width", "--align", "--no-caps",
            "--margin-top", "--margin-bottom", "--margin-left", "--margin-right", "--mat",
        ]
        return args.contains { flags.contains($0) }
    }

    /// Caption's parser does not know grade flags. Drop them, and the numbers that follow.
    static func withoutPlateFlags(_ args: [String]) -> [String] {
        let dropValue: Set<String> = [
            "--exposure", "--brightness", "--contrast", "--highlights", "--shadows",
            "--saturation", "--temperature", "--tint", "--sharpness", "--vignette",
            "--rotate", "--straighten", "--crop", "--look", "--quality",
        ]
        let dropBool: Set<String> = ["--flip-h", "--flip-v"]
        var kept: [String] = []
        var sawInput = false
        var index = 0
        while index < args.count {
            let flag = args[index]
            if flag == "--in" {
                let path = index + 1 < args.count ? args[index + 1] : nil
                index += 2
                if let path, !sawInput {
                    kept.append(path)
                    sawInput = true
                }
                continue
            }
            if dropBool.contains(flag) {
                index += 1
                continue
            }
            if dropValue.contains(flag) {
                index += 2
                continue
            }
            if index > 0, !flag.hasPrefix("-") {
                sawInput = true
            }
            kept.append(flag)
            index += 1
        }
        return kept
    }

    static func execute(_ args: [String]) throws -> URL {
        let job = try parse(args)
        let input = URL(fileURLWithPath: job.input)
        let loaded = try ImageFile.load(url: input)
        let output = try job.resolveOutput(input: input)
        if CaptionPaths.sameFile(input, output) {
            throw CaptionCLIError.overwrite
        }
        let ext = output.pathExtension.lowercased()
        let jpeg = ext == "jpg" || ext == "jpeg" || (ext.isEmpty && job.jpeg)
        let product = CaptionRenderer.render(
            source: loaded.image,
            marks: job.marks(),
            margins: job.margins,
            flatten: jpeg
        )
        try ImageFile.write(product.image, to: output, jpeg: jpeg)
        fputs(
            "captioned \(product.image.width)×\(product.image.height) → \(output.path)\n",
            stderr
        )
        return output
    }

    static func parse(_ args: [String]) throws -> CaptionJob {
        guard let input = positionalInput(in: args) else {
            throw CaptionCLIError.missingInput
        }
        var job = CaptionJob(input: input)
        var index = 1
        while index < args.count {
            let flag = args[index]
            if flag == "--" {
                break
            }
            if boolFlags.contains(flag) {
                switch flag {
                case "--jpeg": job.jpeg = true
                case "--no-caps": job.uppercase = false
                default: break
                }
                index += 1
                continue
            }
            if flag.hasPrefix("-"), !valueFlags.contains(flag) {
                throw CaptionCLIError.unknownFlag(flag)
            }
            if !valueFlags.contains(flag) {
                index += 1
                continue
            }
            if flag == "--at" {
                let point = try value(after: index, flag: flag, in: args)
                let text = try value(after: index + 1, flag: flag, in: args)
                let parts = point.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let x = Double(parts[0]),
                      let y = Double(parts[1]),
                      x >= 0, x <= 1, y >= 0, y <= 1
                else {
                    throw CaptionCLIError.badPoint(point)
                }
                job.free.append((x, y, text))
                index += 3
                continue
            }
            let raw = try value(after: index, flag: flag, in: args)
            switch flag {
            case "--top":
                job.top = raw
            case "--bottom":
                job.bottom = raw
            case "--out", "-o":
                job.output = raw
            case "--font":
                guard let font = CaptionFont.parse(raw) else { throw CaptionCLIError.badFont(raw) }
                job.font = font
            case "--align":
                guard let align = CaptionAlign.parse(raw) else { throw CaptionCLIError.badAlign(raw) }
                job.alignment = align
            case "--fill":
                guard let color = CaptionColor.parse(raw) else { throw CaptionCLIError.badColor(raw) }
                job.fill = color
            case "--stroke":
                guard let color = CaptionColor.parse(raw) else { throw CaptionCLIError.badColor(raw) }
                job.stroke = color
            case "--size":
                job.size = try number(raw, flag: flag, range: 0.02...0.25)
            case "--width":
                job.width = try number(raw, flag: flag, range: 0.2...1)
            case "--stroke-width":
                job.strokeWidth = try number(raw, flag: flag, range: 0...0.45)
            case "--margin-top":
                job.margins.top = try number(raw, flag: flag, range: 0...CanvasMargins.maxFraction)
            case "--margin-bottom":
                job.margins.bottom = try number(raw, flag: flag, range: 0...CanvasMargins.maxFraction)
            case "--margin-left":
                job.margins.left = try number(raw, flag: flag, range: 0...CanvasMargins.maxFraction)
            case "--margin-right":
                job.margins.right = try number(raw, flag: flag, range: 0...CanvasMargins.maxFraction)
            case "--mat":
                guard let color = CaptionColor.parse(raw) else { throw CaptionCLIError.badColor(raw) }
                job.margins.color = color
            default:
                throw CaptionCLIError.unknownFlag(flag)
            }
            index += 2
        }
        return job
    }

    private static let valueFlags: Set<String> = [
        "--top", "--bottom", "--at", "--font", "--size", "--width",
        "--fill", "--stroke", "--stroke-width", "--align", "--out", "-o",
        "--margin-top", "--margin-bottom", "--margin-left", "--margin-right", "--mat",
    ]

    private static let boolFlags: Set<String> = ["--jpeg", "--no-caps"]

    private static let skipPairs: Set<String> = [
        "--top", "--bottom", "--font", "--size", "--width",
        "--fill", "--stroke", "--stroke-width", "--align", "--out", "-o",
        "--margin-top", "--margin-bottom", "--margin-left", "--margin-right", "--mat",
    ]

    private static func positionalInput(in args: [String]) -> String? {
        var index = 1
        while index < args.count {
            let flag = args[index]
            if flag == "--at" {
                index += 3
                continue
            }
            if skipPairs.contains(flag) {
                index += 2
                continue
            }
            if flag.hasPrefix("-") {
                index += 1
                continue
            }
            return flag
        }
        return nil
    }

    private static func value(after index: Int, flag: String, in args: [String]) throws -> String {
        let next = index + 1
        guard next < args.count else { throw CaptionCLIError.missingValue(flag) }
        let raw = args[next]
        if raw.hasPrefix("-") { throw CaptionCLIError.missingValue(flag) }
        return raw
    }

    private static func number(_ raw: String, flag: String, range: ClosedRange<Double>) throws -> Double {
        guard let value = Double(raw), range.contains(value) else {
            throw CaptionCLIError.badNumber(flag, raw)
        }
        return value
    }
}
