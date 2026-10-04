import Foundation

struct CLIError: Error, Equatable {
    var message: String
}

enum CLI {
    struct Request: Equatable {
        var input: String
        var output: String?
        var jpeg = false
        var quality = 0.92
        var state = EditState()
    }

    static func parse(_ args: [String]) -> Result<Request, CLIError> {
        var request = Request(input: "")
        var rotate: Int?
        var flipH = false
        var flipV = false
        var sawCrop = false
        var crop = CropRect.full

        let valued: Set<String> = [
            "--exposure", "--brightness", "--contrast", "--highlights", "--shadows",
            "--saturation", "--temperature", "--tint", "--sharpness", "--vignette",
            "--rotate", "--straighten", "--crop", "--look", "--quality", "--out", "-o", "--in",
        ]

        var i = 1
        var positional: [String] = []
        while i < args.count {
            let arg = args[i]
            if valued.contains(arg) {
                guard i + 1 < args.count, isFlagValue(args[i + 1]) else {
                    return .failure(CLIError(message: "\(arg) needs a value"))
                }
                let value = args[i + 1]
                i += 2
                switch arg {
                case "--in":
                    request.input = value
                case "--out", "-o":
                    request.output = value
                case "--exposure":
                    guard let number = slider(value, range: -2...2) else {
                        return .failure(CLIError(message: "--exposure must be from -2 to 2"))
                    }
                    request.state.exposure = number
                case "--brightness":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--brightness must be from -1 to 1")) }
                    request.state.brightness = number
                case "--contrast":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--contrast must be from -1 to 1")) }
                    request.state.contrast = number
                case "--highlights":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--highlights must be from -1 to 1")) }
                    request.state.highlights = number
                case "--shadows":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--shadows must be from -1 to 1")) }
                    request.state.shadows = number
                case "--saturation":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--saturation must be from -1 to 1")) }
                    request.state.saturation = number
                case "--temperature":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--temperature must be from -1 to 1")) }
                    request.state.temperature = number
                case "--tint":
                    guard let number = unit(value) else { return .failure(CLIError(message: "--tint must be from -1 to 1")) }
                    request.state.tint = number
                case "--sharpness":
                    guard let number = positive(value) else { return .failure(CLIError(message: "--sharpness must be from 0 to 1")) }
                    request.state.sharpness = number
                case "--vignette":
                    guard let number = positive(value) else { return .failure(CLIError(message: "--vignette must be from 0 to 1")) }
                    request.state.vignette = number
                case "--quality":
                    guard let number = positive(value), number >= 0.05 else {
                        return .failure(CLIError(message: "--quality must be from 0.05 to 1"))
                    }
                    request.quality = number
                case "--rotate":
                    guard let number = Int(value), PlateOrientation.from(clockwiseDegrees: number) != nil else {
                        return .failure(CLIError(message: "--rotate must be 0, 90, 180, 270, or a negative quarter turn"))
                    }
                    rotate = number
                case "--straighten":
                    guard let number = slider(value, range: -45...45) else {
                        return .failure(CLIError(message: "--straighten must be from -45 to 45"))
                    }
                    request.state.straighten = number
                case "--look":
                    guard let look = PlateLook.parse(value) else {
                        return .failure(CLIError(message: "--look must be none, mono, sepia, warm, cool, fade, or punch"))
                    }
                    request.state.look = look
                case "--crop":
                    guard let parsed = parseCrop(value) else {
                        return .failure(CLIError(message: "--crop must be x,y,width,height in the range 0 to 1"))
                    }
                    sawCrop = true
                    crop = parsed
                default:
                    break
                }
                continue
            }
            if arg == "--jpeg" {
                request.jpeg = true
                i += 1
                continue
            }
            if arg == "--flip-h" {
                flipH = true
                i += 1
                continue
            }
            if arg == "--flip-v" {
                flipV = true
                i += 1
                continue
            }
            if arg.hasPrefix("-") {
                return .failure(CLIError(message: "unknown option \(arg)"))
            }
            positional.append(arg)
            i += 1
        }

        if request.input.isEmpty {
            guard positional.count == 1 else {
                return .failure(CLIError(message: positional.isEmpty ? "missing input image" : "expected one input image"))
            }
            request.input = positional[0]
        } else if !positional.isEmpty {
            return .failure(CLIError(message: "expected one input image"))
        }

        if let rotate {
            request.state.orientation = PlateOrientation.from(clockwiseDegrees: rotate) ?? .up
        }
        if flipH {
            request.state.orientation = request.state.orientation.applying(.flipH)
        }
        if flipV {
            request.state.orientation = request.state.orientation.applying(.flipV)
        }
        if sawCrop {
            request.state.crop = crop
        }
        return .success(request)
    }

    static func run(_ args: [String]) {
        switch parse(args) {
        case .failure(let error):
            fputs("error: \(error.message)\n", stderr)
            exit(1)
        case .success(let request):
            let inputURL = URL(fileURLWithPath: request.input)
            let buffer: PixelBuffer
            do {
                buffer = try ImageCodec.load(url: inputURL)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            let outputExt = request.output.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
            let jpeg = request.jpeg || outputExt == "jpg" || outputExt == "jpeg"
            let outputURL = request.output.map { URL(fileURLWithPath: $0) }
                ?? ExportNaming.suggestedURL(for: inputURL, jpeg: jpeg)
            if ExportNaming.overwritesSource(outputURL, source: inputURL) {
                fputs("error: \(ImageCodec.CodecError.overwrite.localizedDescription)\n", stderr)
                exit(1)
            }
            let rendered = Engine.render(buffer, state: request.state, applyCrop: true)
            do {
                let data = jpeg
                    ? try ImageCodec.jpegData(rendered, quality: request.quality)
                    : try ImageCodec.pngData(rendered)
                try ImageCodec.write(data, to: outputURL)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            print("edited \(buffer.width)×\(buffer.height) → \(rendered.width)×\(rendered.height)  \(outputURL.path)")
        }
    }

    static func wantsCLI(_ args: [String]) -> Bool {
        let flags: Set<String> = [
            "--exposure", "--brightness", "--contrast", "--highlights", "--shadows",
            "--saturation", "--temperature", "--tint", "--sharpness", "--vignette",
            "--rotate", "--straighten", "--crop", "--look", "--quality", "--out", "-o", "--in",
            "--jpeg", "--flip-h", "--flip-v",
        ]
        if args.contains(where: { flags.contains($0) }) { return true }
        return args.dropFirst().contains { !$0.hasPrefix("-") }
    }

    private static func isFlagValue(_ raw: String) -> Bool {
        if !raw.hasPrefix("-") { return true }
        return Double(raw) != nil
    }

    private static func unit(_ raw: String) -> Double? {
        guard let value = Double(raw), value >= -1, value <= 1 else { return nil }
        return value
    }

    private static func positive(_ raw: String) -> Double? {
        guard let value = Double(raw), value >= 0, value <= 1 else { return nil }
        return value
    }

    private static func slider(_ raw: String, range: ClosedRange<Double>) -> Double? {
        guard let value = Double(raw), range.contains(value) else { return nil }
        return value
    }

    private static func parseCrop(_ raw: String) -> CropRect? {
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, parts.allSatisfy({ $0 != nil }) else { return nil }
        let numbers = parts.compactMap { $0 }
        let rect = CropRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0, rect.maxX <= 1.0001, rect.maxY <= 1.0001 else {
            return nil
        }
        return rect
    }
}
