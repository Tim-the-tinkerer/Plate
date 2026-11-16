import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class CaptionModel: ObservableObject {
    @Published var marks: [CaptionMark] = [] {
        didSet { refreshPreview() }
    }
    /// White (or another color) grown around the photo, as fractions of the photo.
    @Published var margins = CanvasMargins() {
        didSet {
            let next = margins.clamped()
            if next != margins {
                margins = next
                return
            }
            publishCanvasSize()
            if !restoring, remappedFreeAnchors(from: oldValue) { return }
            refreshPreview()
        }
    }
    @Published var selectedID: UUID?
    @Published var status = "Drop a photo, or type a top and bottom line."
    @Published var imageName = ""
    @Published var preview: NSImage?
    @Published var hits: [CaptionHit] = []
    @Published var previewPixelSize: CGSize = .zero
    @Published var hasImage = false
    @Published var isExporting = false
    @Published var copiedFlash = false
    @Published var pixelWidth = 0
    @Published var pixelHeight = 0

    private var full: CGImage?
    private var previewSource: CGImage?
    private var sourceURL: URL?
    private var photoWidth = 0
    private var photoHeight = 0
    private var dragStart: (UUID, Double, Double)?
    private var copyReset: DispatchWorkItem?
    private let undoManager = UndoManager()
    private var restoring = false
    private var gesture: Arrangement?
    private var gestureName = ""
    /// True after a real picture is chosen. A fresh blank canvas can take the Plate photo.
    private var keepsItsPicture = false

    private struct Arrangement: Equatable {
        var marks: [CaptionMark]
        var margins: CanvasMargins
        var selectedID: UUID?
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }
    var undoActionName: String { undoManager.undoActionName }
    var redoActionName: String { undoManager.redoActionName }

    /// The blank canvas, with no words and no mat. Plate can hand its photo across.
    var isFreshCanvas: Bool {
        guard !keepsItsPicture, sourceURL == nil, margins.isEmpty else { return false }
        return !marks.contains { $0.hasVisibleText || $0.role == .extra }
    }

    var summary: String {
        guard hasImage else { return "" }
        let name = (imageName as NSString).deletingPathExtension
        if name.isEmpty { return "\(pixelWidth)×\(pixelHeight)" }
        return "\(name) · \(pixelWidth)×\(pixelHeight)"
    }

    var selected: CaptionMark? {
        guard let selectedID else { return nil }
        return marks.first { $0.id == selectedID }
    }

    var extras: [CaptionMark] {
        marks.filter { $0.role == .extra }
    }

    var styleToken: String {
        guard let selected else { return "" }
        return "\(selected.id.uuidString) \(selected.fill.hex) \(selected.stroke.hex)"
    }

    var textToken: String {
        marks.map { "\($0.id.uuidString):\($0.text)" }.joined(separator: "\n")
    }

    init() {
        let top = CaptionMark.top()
        let bottom = CaptionMark.bottom()
        marks = [top, bottom]
        selectedID = top.id
        applyBlank(.square)
        status = "Drop a photo, or type a top and bottom line."
        undoManager.levelsOfUndo = 80
    }

    deinit {
        undoManager.removeAllActions()
    }

    func mark(id: UUID) -> CaptionMark? {
        marks.first { $0.id == id }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<CaptionMark, Value>) -> Binding<Value> {
        Binding(
            get: {
                guard let mark = self.selected else {
                    return CaptionMark.top()[keyPath: keyPath]
                }
                return mark[keyPath: keyPath]
            },
            set: { newValue in
                guard let id = self.selectedID else { return }
                let apply = { self.update(id) { $0[keyPath: keyPath] = newValue } }
                if self.gesture != nil {
                    apply()
                } else {
                    self.edit("Style", apply)
                }
            }
        )
    }

    func setText(_ id: UUID, _ text: String) {
        update(id) { $0.text = text }
    }

    func setFill(_ color: CaptionColor) {
        guard let id = selectedID else { return }
        edit("Fill Color") { update(id) { $0.fill = color } }
    }

    func setStroke(_ color: CaptionColor) {
        guard let id = selectedID else { return }
        edit("Outline Color") { update(id) { $0.stroke = color } }
    }

    func marginBinding(_ keyPath: WritableKeyPath<CanvasMargins, Double>) -> Binding<Double> {
        Binding(
            get: { self.margins[keyPath: keyPath] },
            set: { value in
                let apply = {
                    var next = self.margins
                    next[keyPath: keyPath] = value
                    let clamped = next.clamped()
                    if clamped == self.margins { return }
                    self.margins = clamped
                }
                if self.gesture != nil {
                    apply()
                } else {
                    self.edit("Margin", apply)
                }
            }
        )
    }

    func setMatColor(_ color: CaptionColor) {
        edit("Mat Color") {
            var next = margins
            next.color = color
            if next == margins { return }
            margins = next
        }
    }

    /// Presets set the four edges. Only Bottom, and only on a white mat, turns a
    /// still-white bottom line black. Dragging a slider does not recolor anything.
    func applyMarginPreset(_ preset: MarginPreset) {
        edit("Margin") {
            let previous = margins
            var next = preset.margins
            next.color = previous.color
            recolorBottomLine(to: next, from: previous)
            margins = next
            status = marginStatus(for: preset)
        }
    }

    /// Put the selected caption in the roomiest white strip, wrapped to that strip.
    func fitSelectedInMargin() {
        guard let id = selectedID else {
            status = "Select a caption, then fit it."
            return
        }
        guard photoWidth > 0, photoHeight > 0 else {
            status = "Open a photo first."
            return
        }
        let layout = margins.layout(photoWidth: photoWidth, photoHeight: photoHeight, maxSide: ImageFile.maxSide)
        guard let edge = layout.largestMargin() else {
            status = "Add a margin first. Bottom, Right, or Left."
            return
        }
        let anchor = layout.anchor(in: edge)
        edit("Fit Caption") {
            update(id) { mark in
                switch edge {
                case .bottom where mark.role == .bottom:
                    mark.pin = .bottom
                case .top where mark.role == .top:
                    mark.pin = .top
                default:
                    mark.pin = .free
                    mark.anchorX = min(1, max(0, anchor.x))
                    mark.anchorY = min(1, max(0, anchor.y))
                }
            }
        }
        switch edge {
        case .bottom:
            status = "Fitted in the bottom strip. Raise Size to fill it."
        case .top:
            status = "Fitted in the top strip. Raise Size to fill it."
        case .left:
            status = "Fitted in the left strip. The line wraps to that column."
        case .right:
            status = "Fitted in the right strip. The line wraps to that column."
        }
    }

    func setPin(_ pin: CaptionPin) {
        guard let id = selectedID else { return }
        edit("Pin") {
            update(id) { mark in
                if pin == .free, mark.pin != .free, let hit = self.hits.first(where: { $0.id == id }) {
                    mark.anchorX = min(1, max(0, hit.center.x))
                    mark.anchorY = min(1, max(0, hit.center.y))
                }
                mark.pin = pin
            }
            status = pin == .free ? "Drag the caption to place it." : "Pinned to the \(pin.rawValue)."
        }
    }

    func applyMemeStyle() {
        guard let id = selectedID else { return }
        edit("Meme Style") {
            update(id) { $0.applyMemeStyle() }
            status = "Meme style: Impact, white, black outline."
        }
    }

    func addText() {
        edit("Add Caption") {
            let style = selected ?? marks.first ?? CaptionMark.top()
            var mark = CaptionMark.extra(copying: style)
            if let hit = hits.first(where: { $0.id == style.id }) {
                mark.anchorX = min(0.94, hit.center.x + 0.04)
                mark.anchorY = min(0.94, hit.center.y + 0.06)
            }
            marks.append(mark)
            selectedID = mark.id
            status = "Added a caption."
        }
    }

    func duplicateSelected() {
        guard let id = selectedID, let source = mark(id: id) else { return }
        edit("Duplicate") {
            var copy = CaptionMark.extra(copying: source)
            if source.hasVisibleText { copy.text = source.text }
            if let hit = hits.first(where: { $0.id == id }) {
                copy.anchorX = min(1, max(0, hit.center.x + 0.03))
                copy.anchorY = min(1, max(0, hit.center.y + 0.04))
            }
            marks.append(copy)
            selectedID = copy.id
            status = "Duplicated."
        }
    }

    func deleteSelected() {
        guard let id = selectedID, let source = mark(id: id), source.role == .extra else {
            status = "The top and bottom lines stay. Clear them, or delete an extra caption."
            return
        }
        edit("Delete Caption") {
            marks.removeAll { $0.id == id }
            selectedID = marks.first { $0.role == .top }?.id ?? marks.first?.id
            status = "Deleted that caption."
        }
    }

    func clearText() {
        edit("Clear Captions") {
            var next = marks.filter { $0.role != .extra }
            if next.count < 2 {
                next = [CaptionMark.top(), CaptionMark.bottom()]
            }
            for index in next.indices {
                next[index].text = ""
                if next[index].role == .top { next[index].pin = .top }
                if next[index].role == .bottom { next[index].pin = .bottom }
            }
            marks = next
            selectedID = next.first?.id
            status = "Captions cleared."
        }
    }

    func closeImage() {
        full = nil
        previewSource = nil
        sourceURL = nil
        imageName = ""
        hasImage = false
        preview = nil
        hits = []
        previewPixelSize = .zero
        photoWidth = 0
        photoHeight = 0
        pixelWidth = 0
        pixelHeight = 0
        status = "Image closed. Captions kept."
    }

    func makeBlank(_ kind: BlankKind) {
        applyBlank(kind)
        let size = kind.size
        status = "Blank \(kind.title.lowercased()), \(size.width)×\(size.height)."
    }

    /// Replace the picture and keep the words. Plate hands its rendered photo across this way.
    func usePhoto(_ image: CGImage, name: String) {
        let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        do {
            let loaded = try ImageFile.load(nsImage: ns)
            adopt(loaded, name: name, url: nil, keepPicture: true)
            var note = "Using \(name), \(loaded.image.width)×\(loaded.image.height)."
            if loaded.capped {
                note += " Long edge capped at \(ImageFile.maxSide)."
            }
            status = note
        } catch {
            status = error.localizedDescription
        }
    }

    func load(url: URL) {
        if CaptionPaths.isProject(url) {
            loadProject(url: url)
            return
        }
        do {
            let loaded = try ImageFile.load(url: url)
            adopt(loaded, name: url.lastPathComponent, url: url)
            var note = "Opened \(url.lastPathComponent), \(loaded.image.width)×\(loaded.image.height)."
            if loaded.capped {
                note += " Long edge capped at \(ImageFile.maxSide)."
            }
            status = note
        } catch {
            status = error.localizedDescription
        }
    }

    func load(urls: [URL]) {
        guard let url = urls.first(where: { CaptionPaths.isProject($0) || isImageFile($0) }) else {
            status = "Drop a photo, or a Caption project."
            return
        }
        load(url: url)
    }

    func paste() {
        let pasteboard = NSPasteboard.general
        if let data = pastedImageData(pasteboard) {
            do {
                notePaste(try ImageFile.load(data: data))
                return
            } catch {
                // The pasteboard may still hold an NSImage if the file bytes were odd.
            }
        }
        if let image = NSImage(pasteboard: pasteboard) {
            do {
                notePaste(try ImageFile.load(nsImage: image))
            } catch {
                status = error.localizedDescription
            }
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            load(urls: urls)
            return
        }
        status = "Clipboard has no image."
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.png, .jpeg, .tiff, .gif, .bmp, .webP, .image]
        if let heic = UTType("public.heic") { types.append(heic) }
        types.append(CaptionFiles.projectType)
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open"
        if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(url: url)
        }
    }

    func saveFilePanel(jpeg: Bool) {
        guard hasImage else {
            status = "Nothing to save."
            return
        }
        if isExporting {
            status = "Still rendering."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [jpeg ? .jpeg : .png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = jpeg ? "Save JPEG" : "Save PNG"
        panel.nameFieldStringValue = CaptionPaths.suggest(sourceURL: sourceURL, imageName: imageName, jpeg: jpeg)
        if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.save(to: url, jpeg: jpeg)
        }
    }

    func save(to url: URL, jpeg: Bool) {
        if let sourceURL, CaptionPaths.sameFile(url, sourceURL) {
            status = "That would overwrite the original. Choose another name."
            return
        }
        guard let full, hasImage else {
            status = "Nothing to save."
            return
        }
        if isExporting {
            status = "Still rendering."
            return
        }
        isExporting = true
        let marks = self.marks
        let margins = self.margins
        let layout = margins.layout(photoWidth: full.width, photoHeight: full.height, maxSide: ImageFile.maxSide)
        status = "Rendering \(layout.width)×\(layout.height)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = CaptionRenderer.render(
                source: full,
                marks: marks,
                margins: margins,
                flatten: jpeg
            ).image
            do {
                try ImageFile.write(image, to: url, jpeg: jpeg)
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.status = "Saved \(url.lastPathComponent)."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    func copyImage() {
        guard let full, hasImage else {
            status = "Nothing to copy."
            return
        }
        if isExporting {
            status = "Still rendering."
            return
        }
        isExporting = true
        let marks = self.marks
        let margins = self.margins
        let layout = margins.layout(photoWidth: full.width, photoHeight: full.height, maxSide: ImageFile.maxSide)
        status = "Rendering \(layout.width)×\(layout.height)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = CaptionRenderer.render(
                source: full,
                marks: marks,
                margins: margins,
                flatten: false
            ).image
            do {
                let png = try ImageFile.pngData(image)
                DispatchQueue.main.async {
                    guard let self else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.declareTypes([.png, .tiff], owner: nil)
                    pasteboard.setData(png, forType: .png)
                    if let tiff = ImageFile.nsImage(image).tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                    }
                    self.isExporting = false
                    self.status = "Copied \(image.width)×\(image.height)."
                    self.copiedFlash = true
                    self.copyReset?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        self?.copiedFlash = false
                    }
                    self.copyReset = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    func dragChanged(id: UUID, translation: CGSize, fitted: CGSize) {
        guard fitted.width > 1, fitted.height > 1 else { return }
        if dragStart?.0 != id {
            guard let hit = hits.first(where: { $0.id == id }) else { return }
            beginGesture("Move Caption")
            dragStart = (id, hit.center.x, hit.center.y)
            selectedID = id
        }
        guard let start = dragStart, start.0 == id else { return }
        let dx = Double(translation.width / fitted.width)
        let dy = Double(translation.height / fitted.height)
        update(id) { mark in
            mark.pin = .free
            mark.anchorX = min(1, max(0, start.1 + dx))
            mark.anchorY = min(1, max(0, start.2 + dy))
        }
    }

    func dragEnded() {
        dragStart = nil
        endGesture()
    }

    /// One undo step for a slider drag or a caption drag. The snapshot is taken
    /// on the way in, and recorded once on the way out.
    func trackGesture(_ editing: Bool, name: String) {
        if editing { beginGesture(name) } else { endGesture() }
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
    }

    private func applyBlank(_ kind: BlankKind) {
        let size = kind.size
        guard let image = ImageFile.solid(width: size.width, height: size.height, color: .canvas) else {
            status = "Could not make a canvas."
            return
        }
        adopt(LoadedImage(image: image, capped: false), name: kind.fileName, url: nil, keepPicture: false)
    }

    private func adopt(_ loaded: LoadedImage, name: String, url: URL?, keepPicture: Bool = true) {
        full = loaded.image
        previewSource = ImageFile.scaled(loaded.image, maxSide: ImageFile.previewMaxSide)
        sourceURL = url
        imageName = name
        photoWidth = loaded.image.width
        photoHeight = loaded.image.height
        hasImage = true
        keepsItsPicture = keepPicture
        publishCanvasSize()
        refreshPreview()
        undoManager.removeAllActions()
    }

    private func refreshPreview() {
        guard let previewSource else {
            preview = nil
            hits = []
            previewPixelSize = .zero
            return
        }
        let product = CaptionRenderer.render(
            source: previewSource,
            marks: marks,
            margins: margins,
            flatten: false,
            maxSide: ImageFile.previewMaxSide
        )
        preview = ImageFile.nsImage(product.image)
        hits = product.hits
        previewPixelSize = CGSize(width: product.image.width, height: product.image.height)
    }

    /// Header size is the export canvas, including the mat, capped at 8192.
    private func publishCanvasSize() {
        guard photoWidth > 0, photoHeight > 0 else {
            pixelWidth = 0
            pixelHeight = 0
            return
        }
        let layout = margins.layout(photoWidth: photoWidth, photoHeight: photoHeight, maxSide: ImageFile.maxSide)
        pixelWidth = layout.width
        pixelHeight = layout.height
    }

    /// A free caption keeps its place on the photo when the mat grows. A caption
    /// already sitting in the mat keeps its offset past the photo edge. Pinned
    /// top and bottom lines are left alone, so a bottom line follows the new bar.
    private func remappedFreeAnchors(from old: CanvasMargins) -> Bool {
        if old.sameEdges(as: margins) { return false }
        var next = marks
        var changed = false
        for index in next.indices where next[index].pin == .free {
            let point = old.remap(anchorX: next[index].anchorX, anchorY: next[index].anchorY, to: margins)
            if abs(point.0 - next[index].anchorX) > 0.0001 || abs(point.1 - next[index].anchorY) > 0.0001 {
                next[index].anchorX = point.0
                next[index].anchorY = point.1
                changed = true
            }
        }
        if changed { marks = next }
        return changed
    }

    private func recolorBottomLine(to next: CanvasMargins, from previous: CanvasMargins) {
        guard let index = marks.firstIndex(where: { $0.role == .bottom }) else { return }
        let hadWhiteBar = previous.bottom > 0.001 && previous.color.matches(.white)
        let getsWhiteBar = next.bottom > 0.001 && next.color.matches(.white)
        var updated = marks
        if getsWhiteBar, !hadWhiteBar, updated[index].fill.matches(.white) {
            updated[index].fill = .black
            marks = updated
        } else if hadWhiteBar, !getsWhiteBar, updated[index].fill.matches(.black) {
            updated[index].fill = .white
            marks = updated
        }
    }

    private func marginStatus(for preset: MarginPreset) -> String {
        let white = margins.color.matches(.white)
        switch preset {
        case .none:
            return "Margin removed."
        case .bottom:
            let black = marks.first { $0.role == .bottom }?.fill.matches(.black) ?? false
            if white, black {
                return "White bar under the photo. The bottom line is black."
            }
            return white
                ? "White bar under the photo. The bottom line sits in it."
                : "Bar under the photo. The bottom line sits in it."
        case .right:
            return white
                ? "White column on the right. Select a caption and click Fit caption."
                : "Column on the right. Select a caption and click Fit caption."
        case .left:
            return white
                ? "White column on the left. Select a caption and click Fit caption."
                : "Column on the left. Select a caption and click Fit caption."
        }
    }

    func loadProject(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            try readProject(data)
            status = "Opened \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    func saveProjectPanel() {
        guard hasImage, full != nil else {
            status = "Nothing to save."
            return
        }
        if isExporting {
            status = "Still rendering."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [CaptionFiles.projectType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save Project"
        panel.nameFieldStringValue = CaptionPaths.suggestProject(sourceURL: sourceURL, imageName: imageName)
        if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.saveProject(to: url)
        }
    }

    func saveProject(to url: URL) {
        if let sourceURL, CaptionPaths.sameFile(url, sourceURL) {
            status = "That would overwrite the original. Choose another name."
            return
        }
        guard let full, hasImage else {
            status = "Nothing to save."
            return
        }
        if isExporting {
            status = "Still rendering."
            return
        }
        isExporting = true
        let project = CaptionProject(
            imageName: imageName,
            imagePNG: Data(),
            margins: margins,
            selected: selectedID,
            marks: marks
        )
        let name = url.lastPathComponent
        status = "Saving \(name)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let png = try ImageFile.pngData(full)
                var written = project
                written.imagePNG = png
                let data = try written.encode()
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.status = "Saved \(name). Open it later to keep editing."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isExporting = false
                    self?.status = error.localizedDescription
                }
            }
        }
    }

    func projectData() throws -> Data {
        guard let full else { throw ProjectError.noImage }
        let png = try ImageFile.pngData(full)
        return try CaptionProject(
            imageName: imageName,
            imagePNG: png,
            margins: margins,
            selected: selectedID,
            marks: marks
        ).encode()
    }

    func readProject(_ data: Data) throws {
        let project = try CaptionProject.decode(data)
        let loaded = try ImageFile.load(data: project.imagePNG)
        let name = project.imageName.isEmpty ? "Project.png" : project.imageName
        adopt(loaded, name: name, url: nil)
        restoring = true
        var next = project.captionMarks()
        if !next.contains(where: { $0.role == .top }) {
            next.insert(CaptionMark.top(), at: 0)
        }
        if !next.contains(where: { $0.role == .bottom }) {
            next.append(CaptionMark.bottom())
        }
        marks = next
        if let selected = project.selected, next.contains(where: { $0.id == selected }) {
            selectedID = selected
        } else {
            selectedID = next.first { $0.role == .top }?.id ?? next.first?.id
        }
        margins = project.canvasMargins()
        restoring = false
        refreshPreview()
        undoManager.removeAllActions()
    }

    private func pastedImageData(_ pasteboard: NSPasteboard) -> Data? {
        let types: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
        ]
        for type in types {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private func notePaste(_ loaded: LoadedImage) {
        adopt(loaded, name: "Clipboard.png", url: nil)
        var note = "Pasted image, \(loaded.image.width)×\(loaded.image.height)."
        if loaded.capped {
            note += " Long edge capped at \(ImageFile.maxSide)."
        }
        status = note
    }

    func beginGesture(_ name: String) {
        if gesture == nil {
            gesture = capture()
            gestureName = name
        }
    }

    func endGesture() {
        guard let before = gesture else { return }
        let name = gestureName
        gesture = nil
        gestureName = ""
        guard before != capture() else { return }
        push(before, name: name.isEmpty ? "Edit" : name)
    }

    private func edit(_ name: String, _ body: () -> Void) {
        if restoring || gesture != nil {
            body()
            return
        }
        let before = capture()
        body()
        guard before != capture() else { return }
        push(before, name: name)
    }

    private func capture() -> Arrangement {
        Arrangement(marks: marks, margins: margins, selectedID: selectedID)
    }

    private func push(_ before: Arrangement, name: String) {
        undoManager.registerUndo(withTarget: self) { target in
            let current = target.capture()
            target.restore(before)
            target.status = target.undoManager.isUndoing ? "Undid \(name)." : "Redid \(name)."
            target.push(current, name: name)
        }
        undoManager.setActionName(name)
    }

    private func restore(_ state: Arrangement) {
        restoring = true
        marks = state.marks
        selectedID = state.selectedID
        margins = state.margins
        restoring = false
        refreshPreview()
    }

    private func update(_ id: UUID, _ body: (inout CaptionMark) -> Void) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        var next = marks
        body(&next[index])
        if next[index] == marks[index] { return }
        marks = next
    }

    private func isImageFile(_ url: URL) -> Bool {
        ImageFile.openExtensions.contains(url.pathExtension.lowercased())
    }
}
