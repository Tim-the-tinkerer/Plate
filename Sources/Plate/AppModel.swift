import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var state = EditState()
    @Published var tool: EditorTool = .adjust
    @Published var annotateTool: AnnotateTool = .pen
    @Published var markupColor: AnnotationColor = .amber
    @Published var strokeWeight = Annotation.defaultStroke
    @Published var markerWeight = Annotation.defaultMarker
    @Published var textWeight = Annotation.defaultText
    @Published var noteText = ""
    @Published var gradeName = ""
    @Published private(set) var savedGrade: PlateGrade?
    @Published var selectedAnnotationID: UUID?
    @Published var fileName: String?
    @Published var sourceURL: URL?
    @Published var status = "Drop a photo."
    @Published var statusIsError = false
    @Published var displayImage: NSImage?
    @Published var histogram: [Int] = Array(repeating: 0, count: 256)
    @Published var lookThumbs: [PlateLook: NSImage] = [:]
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var isRendering = false
    @Published var showOriginal = false
    @Published var fitToWindow = true
    @Published var pixelScale: Double = 1
    @Published var pan: CGSize = .zero
    @Published var fitScale: Double = 1
    @Published var hasImage = false
    @Published var canvasWindowRect: NSRect = .zero

    private var source: PixelBuffer?
    private var previewSource: PixelBuffer?
    private var originalPreview: NSImage?
    private var history = EditHistory()
    /// State last written to disk, or the untouched photo if this session has not been saved.
    private var savedState = EditState()
    private var isDragging = false
    private var checkpoint: EditState?
    private var renderGeneration = 0
    private var loadGeneration = 0
    private var nudgeOriginal: Annotation?
    private var nudgeDelta = NormPoint(x: 0, y: 0)

    init() {
        if let grade = PlateGrade.load() {
            savedGrade = grade
            gradeName = grade.name
        }
    }

    var isNudging: Bool { nudgeOriginal != nil }

    var windowTitle: String {
        if let fileName { return "Plate — \(fileName)" }
        return "Plate"
    }

    var isDirty: Bool { hasImage && state != savedState }

    var selectedAnnotation: Annotation? {
        guard let id = selectedAnnotationID else { return nil }
        return state.annotations.first { $0.id == id }
    }

    var zoomPercent: Int {
        let scale = fitToWindow ? fitScale : pixelScale
        return max(1, Int((scale * 100).rounded()))
    }

    /// Width and height of the frame the crop is drawn on, after quarter-turns and straighten.
    var canvasOrientedSize: (Int, Int)? {
        guard let source else { return nil }
        let size = Engine.frameSize(source: source, orientation: state.orientation, straighten: state.straighten)
        return (size.width, size.height)
    }

    /// Crop the on-screen photo is showing. The crop tool shows the whole oriented frame.
    var displayCrop: CropRect {
        tool == .crop ? .full : state.crop
    }

    var outputDescription: String {
        guard let source else { return "No image" }
        let oriented = Engine.orientedSize(of: source, orientation: state.orientation)
        let output = Engine.outputSize(source: source, state: state)
        if output.width == oriented.width, output.height == oriented.height {
            return "\(output.width) × \(output.height)"
        }
        return "\(oriented.width) × \(oriented.height)  →  \(output.width) × \(output.height)"
    }

    func noteFitScale(_ scale: Double) {
        if abs(fitScale - scale) > 0.0005 {
            fitScale = scale
        }
    }

    func noteCanvasRect(_ rect: NSRect) {
        if rect.integral != canvasWindowRect.integral {
            canvasWindowRect = rect
        }
    }

    func select(tool: EditorTool) {
        guard self.tool != tool else { return }
        self.tool = tool
        scheduleRender()
    }

    func beginEdit() {
        guard !isDragging else { return }
        checkpoint = state
        isDragging = true
    }

    func update(_ body: (inout EditState) -> Void) {
        beginEdit()
        body(&state)
        scheduleRender()
    }

    func commitEdit() {
        nudgeOriginal = nil
        nudgeDelta = NormPoint(x: 0, y: 0)
        guard isDragging else { return }
        if let checkpoint, checkpoint != state {
            history.push(state)
        }
        checkpoint = nil
        isDragging = false
        refreshHistory()
    }

    func commit(_ body: (inout EditState) -> Void) {
        commitEdit()
        body(&state)
        history.push(state)
        refreshHistory()
        scheduleRender()
    }

    func apply(_ op: OrientOp) {
        guard let source else { return }
        commit { state in
            guard abs(state.straighten) > 1e-8 else {
                state = state.applying(op)
                return
            }
            let angle = state.straighten
            let before = Engine.orientedSize(of: source, orientation: state.orientation)
            let located = state.annotations.map { mark in
                mark.points.map {
                    StraightenMath.orientedPixel($0, degrees: angle, width: before.width, height: before.height)
                }
            }
            var next = state
            next.orientation = state.orientation.applying(op)
            next.crop = CropMath.applying(op, to: state.crop)
            let after = Engine.orientedSize(of: source, orientation: next.orientation)
            next.annotations = zip(state.annotations, located).map { mark, pixels in
                var copy = mark
                copy.points = pixels.map { pixel in
                    let turned = Self.turned(pixel, op: op, width: before.width, height: before.height)
                    return StraightenMath.inscribedPoint(
                        x: turned.x,
                        y: turned.y,
                        degrees: angle,
                        width: after.width,
                        height: after.height
                    )
                }
                return copy
            }
            state = next
        }
    }

    func setStraighten(_ degrees: Double) {
        let degrees = StraightenMath.clamped(degrees)
        guard let source else {
            state.straighten = degrees
            return
        }
        beginEdit()
        let base = checkpoint ?? state
        let size = Engine.orientedSize(of: source, orientation: base.orientation)
        var next = base
        next.straighten = degrees
        next.annotations = base.annotations.map {
            StraightenMath.remap($0, from: base.straighten, to: degrees, width: size.width, height: size.height)
        }
        state = next
        scheduleRender()
    }

    func setAspect(_ aspect: CropAspect) {
        guard let source else { return }
        let size = Engine.frameSize(source: source, orientation: state.orientation, straighten: state.straighten)
        let ratio = aspect.pixelRatio(imageWidth: size.width, imageHeight: size.height)
        commit {
            $0.cropAspect = aspect
            $0.crop = CropMath.fitted(ratio: ratio, imageWidth: size.width, imageHeight: size.height)
        }
    }

    func setCrop(_ crop: CropRect) {
        update { $0.crop = crop }
    }

    func resetCrop() {
        commit {
            $0.crop = .full
            $0.cropAspect = .free
        }
    }

    func resetAll() {
        selectedAnnotationID = nil
        commit { $0 = EditState() }
        status = "Reset."
        statusIsError = false
    }

    func undo() {
        commitEdit()
        guard let restored = history.undo() else { return }
        state = restored
        keepSelection()
        refreshHistory()
        scheduleRender()
    }

    func redo() {
        commitEdit()
        guard let restored = history.redo() else { return }
        state = restored
        keepSelection()
        refreshHistory()
        scheduleRender()
    }

    func setMarkupColor(_ color: AnnotationColor) {
        markupColor = color
        guard annotateTool == .select, let id = selectedAnnotationID else { return }
        guard state.annotations.contains(where: { $0.id == id && $0.color != color }) else { return }
        commit { edit in
            guard let index = edit.annotations.firstIndex(where: { $0.id == id }) else { return }
            edit.annotations[index].color = color
        }
    }

    func makeMark(kind: AnnotationKind, points: [NormPoint], text: String) -> Annotation {
        let weight: Double
        switch kind {
        case .marker:
            weight = markerWeight
        case .text:
            weight = textWeight
        default:
            weight = strokeWeight
        }
        return Annotation(id: UUID(), kind: kind, color: markupColor, weight: weight, points: points, text: text)
    }

    func addAnnotation(_ annotation: Annotation) {
        commit { $0.annotations.append(annotation) }
        selectedAnnotationID = annotation.id
    }

    /// Live move. One undo step lands when the caller calls `commitEdit`.
    func moveAnnotation(id: UUID, from original: Annotation, dx: Double, dy: Double) {
        beginEdit()
        guard let index = state.annotations.firstIndex(where: { $0.id == id }) else { return }
        state.annotations[index] = AnnotationGeometry.translated(original, dx: dx, dy: dy)
    }

    /// Live reshape. One undo step lands when the caller calls `commitEdit`.
    func reshapeAnnotation(id: UUID, from original: Annotation, handle: AnnotationHandle, to point: NormPoint) {
        beginEdit()
        guard let index = state.annotations.firstIndex(where: { $0.id == id }) else { return }
        state.annotations[index] = AnnotationGeometry.reshaped(original, handle: handle, to: point)
    }

    func setSelectedWeight(_ weight: Double) {
        guard let id = selectedAnnotationID,
              let index = state.annotations.firstIndex(where: { $0.id == id })
        else { return }
        switch state.annotations[index].kind {
        case .marker:
            markerWeight = weight
        case .text:
            textWeight = weight
        default:
            strokeWeight = weight
        }
        beginEdit()
        state.annotations[index].weight = weight
    }

    func setSelectedText(_ text: String) {
        guard let id = selectedAnnotationID,
              let index = state.annotations.firstIndex(where: { $0.id == id }),
              state.annotations[index].kind == .text
        else { return }
        beginEdit()
        state.annotations[index].text = text
    }

    func finishSelectedTextEdit() {
        guard isDragging, let checkpoint else {
            commitEdit()
            return
        }
        if let mark = selectedAnnotation, mark.kind == .text,
           mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = checkpoint
            self.checkpoint = nil
            isDragging = false
            refreshHistory()
            status = "A note needs some text."
            statusIsError = false
            return
        }
        commitEdit()
    }

    func nudgeSelected(dx: Double, dy: Double) {
        guard let id = selectedAnnotationID, let current = selectedAnnotation else { return }
        if nudgeOriginal == nil {
            beginEdit()
            nudgeOriginal = current
            nudgeDelta = NormPoint(x: 0, y: 0)
        }
        nudgeDelta.x += dx
        nudgeDelta.y += dy
        guard let original = nudgeOriginal else { return }
        moveAnnotation(id: id, from: original, dx: nudgeDelta.x, dy: nudgeDelta.y)
    }

    func finishNudge() {
        guard nudgeOriginal != nil else { return }
        commitEdit()
    }

    func duplicateSelectedAnnotation() {
        guard let mark = selectedAnnotation else { return }
        var copy = mark
        copy.id = UUID()
        copy = AnnotationGeometry.translated(copy, dx: 0.02, dy: 0.02)
        commit { $0.annotations.append(copy) }
        selectedAnnotationID = copy.id
    }

    func saveGrade() {
        guard hasImage else { return }
        let trimmed = gradeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Grade" : String(trimmed.prefix(40))
        gradeName = name
        let grade = PlateGrade.capture(state, name: name)
        grade.store()
        savedGrade = grade
        status = "Saved grade “\(name)”."
        statusIsError = false
    }

    func applyGrade() {
        guard hasImage, let savedGrade else { return }
        let grade = savedGrade
        commit { state in
            state = grade.applied(to: state)
        }
        status = "Applied “\(grade.name)”."
        statusIsError = false
    }

    func clearGrade() {
        guard savedGrade != nil else { return }
        PlateGrade.clear()
        savedGrade = nil
        status = "Cleared the saved grade."
        statusIsError = false
    }

    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        selectedAnnotationID = nil
        commit { $0.annotations.removeAll { $0.id == id } }
    }

    func clearAnnotations() {
        guard !state.annotations.isEmpty else { return }
        selectedAnnotationID = nil
        commit { $0.annotations.removeAll() }
        status = "Cleared marks."
        statusIsError = false
    }

    func toggleOriginal(_ showing: Bool) {
        guard showOriginal != showing else { return }
        showOriginal = showing
        if showing {
            displayImage = originalPreview
        } else {
            scheduleRender()
        }
    }

    func zoomIn() {
        let base = fitToWindow ? fitScale : pixelScale
        fitToWindow = false
        pixelScale = min(32, max(0.02, base) * 1.25)
    }

    func zoomOut() {
        let base = fitToWindow ? fitScale : pixelScale
        fitToWindow = false
        pixelScale = max(0.02, base / 1.25)
    }

    func zoom(by factor: Double) {
        guard factor > 0, factor.isFinite else { return }
        let base = fitToWindow ? fitScale : pixelScale
        fitToWindow = false
        pixelScale = min(32, max(0.02, base * factor))
    }

    func zoomFit() {
        fitToWindow = true
        pan = .zero
    }

    func zoomActual() {
        fitToWindow = false
        pixelScale = 1
        pan = .zero
    }

    func toggleFitActual() {
        if fitToWindow || abs(pixelScale - 1) > 0.04 {
            zoomActual()
        } else {
            zoomFit()
        }
    }

    /// Ask before throwing away edits. Save writes a new file and waits until that file is on disk.
    func confirmDiscard(replacing: Bool) -> Bool {
        commitEdit()
        guard isDirty else { return true }
        let name = fileName ?? "this photo"
        let alert = NSAlert()
        alert.messageText = "Save your edits to “\(name)”?"
        alert.informativeText = replacing
            ? "These edits are only in this window. Opening another photo discards them unless you save. Plate writes a new file and leaves the original alone."
            : "These edits are only in this window. Closing Plate discards them unless you save. Plate writes a new file and leaves the original alone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Don't Save")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveAndWait()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Open a photo to edit."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        guard confirmDiscard(replacing: true) else { return }
        loadGeneration += 1
        let generation = loadGeneration
        status = "Opening \(url.lastPathComponent)…"
        statusIsError = false
        isRendering = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let buffer = try ImageCodec.load(url: url)
                let preview = Engine.downscale(buffer, maxSide: ImageCodec.previewMaxSide)
                DispatchQueue.main.async {
                    guard let self, self.loadGeneration == generation else { return }
                    self.adopt(
                        full: buffer,
                        preview: preview,
                        name: url.lastPathComponent,
                        url: url
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.loadGeneration == generation else { return }
                    self.isRendering = false
                    self.status = error.localizedDescription
                    self.statusIsError = true
                }
            }
        }
    }

    func load(nsImage: NSImage, name: String) {
        guard confirmDiscard(replacing: true) else { return }
        do {
            let buffer = try ImageCodec.load(nsImage: nsImage)
            let preview = Engine.downscale(buffer, maxSide: ImageCodec.previewMaxSide)
            adopt(full: buffer, preview: preview, name: name, url: nil)
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }

    func loadSample() {
        guard confirmDiscard(replacing: true) else { return }
        let buffer = SampleImage.make()
        let preview = Engine.downscale(buffer, maxSide: ImageCodec.previewMaxSide)
        adopt(full: buffer, preview: preview, name: "Sample", url: nil)
    }

    func paste() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else {
            status = "The clipboard has no image."
            statusIsError = true
            return
        }
        load(nsImage: image, name: "Pasted image")
    }

    func copyImage() {
        guard let source else {
            status = "Open an image first."
            statusIsError = true
            return
        }
        let state = self.state
        status = "Copying…"
        statusIsError = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rendered = Self.renderedForExport(source, state: state)
            guard let image = ImageCodec.nsImage(rendered) else {
                DispatchQueue.main.async {
                    self?.status = "Could not copy the image."
                    self?.statusIsError = true
                }
                return
            }
            let size = "\(rendered.width) × \(rendered.height)"
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
                self?.status = "Copied \(size)"
                self?.statusIsError = false
            }
        }
    }

    func savePanel() {
        guard let choice = chooseDestination() else { return }
        write(to: choice.url, jpeg: choice.jpeg)
    }

    func write(to url: URL, jpeg: Bool) {
        guard let source else { return }
        if refuseOverwrite(url) { return }
        let saving = state
        status = "Rendering…"
        statusIsError = false
        isRendering = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try Self.encode(source, state: saving, to: url, jpeg: jpeg)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.noteSaved(saving, name: url.lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRendering = false
                    self.status = error.localizedDescription
                    self.statusIsError = true
                }
            }
        }
    }

    private func adopt(full: PixelBuffer, preview: PixelBuffer, name: String, url: URL?) {
        source = full
        previewSource = preview
        originalPreview = ImageCodec.nsImage(preview)
        sourceURL = url
        fileName = name
        hasImage = true
        let initial = savedGrade.map { $0.applied(to: EditState()) } ?? EditState()
        state = initial
        savedState = initial
        history.reset(to: initial)
        selectedAnnotationID = nil
        isDragging = false
        checkpoint = nil
        showOriginal = false
        fitToWindow = true
        pan = .zero
        pixelScale = 1
        refreshHistory()
        if let savedGrade {
            status = "\(name)  ·  \(full.width) × \(full.height)  ·  \(savedGrade.name)"
        } else {
            status = "\(name)  ·  \(full.width) × \(full.height)"
        }
        statusIsError = false
        scheduleRender()
        scheduleThumbs(from: preview)
    }

    private func scheduleThumbs(from preview: PixelBuffer) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let square = Engine.centerSquare(preview, side: 180)
            var thumbs: [PlateLook: NSImage] = [:]
            for look in PlateLook.allCases {
                var edit = EditState()
                edit.look = look
                let rendered = Engine.render(square, state: edit, applyCrop: true)
                if let image = ImageCodec.nsImage(rendered) {
                    thumbs[look] = image
                }
            }
            DispatchQueue.main.async {
                self?.lookThumbs = thumbs
            }
        }
    }

    private func scheduleRender() {
        guard let previewSource else {
            displayImage = nil
            isRendering = false
            return
        }
        if showOriginal {
            displayImage = originalPreview
            histogram = Engine.lumaHistogram(previewSource)
            isRendering = false
            return
        }
        renderGeneration += 1
        let generation = renderGeneration
        let state = self.state
        let applyCrop = tool != .crop
        isRendering = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rendered = Engine.render(previewSource, state: state, applyCrop: applyCrop)
            let image = ImageCodec.nsImage(rendered)
            let bins = Engine.lumaHistogram(rendered)
            DispatchQueue.main.async {
                guard let self, self.renderGeneration == generation, !self.showOriginal else { return }
                self.displayImage = image
                self.histogram = bins
                self.isRendering = false
            }
        }
    }

    private func chooseDestination() -> (url: URL, jpeg: Bool)? {
        guard source != nil else {
            status = "Open an image first."
            statusIsError = true
            return nil
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ExportNaming.suggestedURL(for: sourceURL, jpeg: false).lastPathComponent
        panel.message = "Plate saves a new file. The original stays as it is."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        return (url, jpeg)
    }

    /// Used when the next action has to know whether the file was actually written.
    private func saveAndWait() -> Bool {
        guard let choice = chooseDestination() else { return false }
        guard let source else { return false }
        if refuseOverwrite(choice.url) { return false }
        let saving = state
        status = "Rendering…"
        statusIsError = false
        isRendering = true
        for window in NSApp.windows {
            window.contentView?.displayIfNeeded()
        }
        var failure: String?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Self.encode(source, state: saving, to: choice.url, jpeg: choice.jpeg)
            } catch {
                failure = error.localizedDescription
            }
            group.leave()
        }
        group.wait()
        if let failure {
            isRendering = false
            status = failure
            statusIsError = true
            return false
        }
        noteSaved(saving, name: choice.url.lastPathComponent)
        return true
    }

    private func refuseOverwrite(_ url: URL) -> Bool {
        guard ExportNaming.overwritesSource(url, source: sourceURL) else { return false }
        status = ImageCodec.CodecError.overwrite.localizedDescription
        statusIsError = true
        let alert = NSAlert()
        alert.messageText = "Plate will not replace the original"
        alert.informativeText = "Choose a new name. The photo you opened stays as it is."
        alert.alertStyle = .warning
        alert.runModal()
        return true
    }

    private func noteSaved(_ saving: EditState, name: String) {
        isRendering = false
        if state == saving {
            savedState = saving
        }
        status = "Saved \(name)"
        statusIsError = false
    }

    /// Save and Copy both use this. The on-screen preview is a separate, smaller buffer.
    private static func renderedForExport(_ source: PixelBuffer, state: EditState) -> PixelBuffer {
        Engine.render(source, state: state, applyCrop: true, bakeAnnotations: true)
    }

    private static func encode(_ source: PixelBuffer, state: EditState, to url: URL, jpeg: Bool) throws {
        let rendered = renderedForExport(source, state: state)
        let data = jpeg
            ? try ImageCodec.jpegData(rendered, quality: 0.92)
            : try ImageCodec.pngData(rendered)
        try ImageCodec.write(data, to: url)
    }

    private func refreshHistory() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    /// Quarter-turn a point that lives in the oriented photo, in continuous pixel coordinates.
    private static func turned(
        _ point: (x: Double, y: Double),
        op: OrientOp,
        width: Int,
        height: Int
    ) -> (x: Double, y: Double) {
        let w = Double(width)
        let h = Double(height)
        switch op {
        case .rotateCW:
            return (h - point.y, point.x)
        case .rotateCCW:
            return (point.y, w - point.x)
        case .flipH:
            return (w - point.x, point.y)
        case .flipV:
            return (point.x, h - point.y)
        }
    }

    private func keepSelection() {
        guard let id = selectedAnnotationID else { return }
        if !state.annotations.contains(where: { $0.id == id }) {
            selectedAnnotationID = nil
        }
    }
}
