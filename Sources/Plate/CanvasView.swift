import AppKit
import SwiftUI

struct CanvasView: View {
    @ObservedObject var model: AppModel
    @StateObject private var scrollMonitor = ScrollMonitor()
    @State private var dragHandle: CropHandle?
    @State private var dragCrop = CropRect.full
    @State private var panning = false
    @State private var panOrigin: CGSize = .zero
    @State private var pinchOrigin: Double?
    @State private var draft: Annotation?
    @State private var movingID: UUID?
    @State private var movingOriginal: Annotation?
    @State private var reshapeHandle: AnnotationHandle?
    @StateObject private var keyMonitor = KeyMonitor()

    var body: some View {
        GeometryReader { geo in
            let imageSize = model.displayImage?.size ?? .zero
            let fit = fitScale(image: imageSize, view: geo.size)
            let scale = model.fitToWindow ? fit : model.pixelScale
            let rect = placedRect(image: imageSize, view: geo.size, scale: scale, pan: model.fitToWindow ? .zero : model.pan)

            ZStack(alignment: .topLeading) {
                Theme.canvas
                Checkerboard()
                    .opacity(model.hasImage ? 1 : 0)

                if let image = model.displayImage, rect.width > 1, rect.height > 1 {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    if !model.showOriginal, !model.state.annotations.isEmpty || draft != nil {
                        AnnotationOverlay(
                            imageRect: rect,
                            crop: model.displayCrop,
                            annotations: model.state.annotations,
                            draft: draft,
                            selectedID: model.selectedAnnotationID,
                            showsHandles: model.tool == .annotate && model.annotateTool == .select
                        )
                    }

                    if model.tool == .crop, !model.showOriginal {
                        CropOverlay(imageRect: rect, crop: model.state.crop)
                    }
                } else if !model.hasImage {
                    emptyState
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if model.showOriginal, model.hasImage {
                    compareBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(12)
                }
            }
            .coordinateSpace(name: "canvas")
            .contentShape(Rectangle())
            .modifier(CanvasInteraction(enabled: model.hasImage, gesture: canvasGesture(imageRect: rect)))
            .onTapGesture(count: 2) {
                guard model.tool != .crop, model.tool != .annotate, model.hasImage else { return }
                model.toggleFitActual()
            }
            .background(
                WindowRectProbe { model.noteCanvasRect($0) }
            )
            .onAppear {
                model.noteFitScale(fit)
                installScroll()
                installKeys()
            }
            .onChange(of: fit) { newFit in
                model.noteFitScale(newFit)
            }
            .onDisappear {
                scrollMonitor.stop()
                keyMonitor.stop()
            }
            .onChange(of: model.annotateTool) { _ in
                draft = nil
                if movingID != nil || reshapeHandle != nil {
                    movingID = nil
                    movingOriginal = nil
                    reshapeHandle = nil
                    model.commitEdit()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.amber)
            Text("Drop a photo")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("PNG, JPEG, TIFF, or HEIC. Plate writes a new file and leaves the original alone.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) {
                Button("Open…") { model.openPanel() }
                    .buttonStyle(PlateButtonStyle(kind: .primary))
                Button("Load Sample") { model.loadSample() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
            }
            .padding(.top, 4)
        }
    }

    private var compareBadge: some View {
        Text("Original")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.amber)
            .clipShape(Capsule())
    }

    private func canvasGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if model.tool == .crop, model.hasImage, !model.showOriginal {
                    dragCrop(value, imageRect: imageRect)
                } else if model.tool == .annotate, model.hasImage, !model.showOriginal {
                    dragAnnotate(value, imageRect: imageRect)
                } else {
                    dragPan(value)
                }
            }
            .onEnded { value in
                if dragHandle != nil {
                    dragHandle = nil
                    model.commitEdit()
                }
                if movingID != nil || reshapeHandle != nil {
                    movingID = nil
                    movingOriginal = nil
                    reshapeHandle = nil
                    model.commitEdit()
                }
                if let draft {
                    finishDraft(draft)
                    self.draft = nil
                } else if model.tool == .annotate, model.annotateTool == .text, !model.showOriginal {
                    placeText(at: value.startLocation, imageRect: imageRect)
                }
                panning = false
                pinchOrigin = nil
            }
            .simultaneously(with:
                MagnificationGesture()
                    .onChanged { value in
                        if pinchOrigin == nil {
                            pinchOrigin = model.fitToWindow ? model.fitScale : model.pixelScale
                            model.fitToWindow = false
                        }
                        let origin = pinchOrigin ?? model.pixelScale
                        model.pixelScale = min(32, max(0.02, origin * Double(value)))
                    }
                    .onEnded { _ in
                        pinchOrigin = nil
                    }
            )
    }

    private func dragCrop(_ value: DragGesture.Value, imageRect: CGRect) {
        guard imageRect.width > 1, imageRect.height > 1 else { return }
        let handle: CropHandle
        let startCrop: CropRect
        if let existing = dragHandle {
            handle = existing
            startCrop = dragCrop
        } else {
            let viewCrop = CGRect(
                x: imageRect.minX + model.state.crop.x * imageRect.width,
                y: imageRect.minY + model.state.crop.y * imageRect.height,
                width: model.state.crop.width * imageRect.width,
                height: model.state.crop.height * imageRect.height
            )
            guard let hit = CropMath.hitTest(point: value.startLocation, cropRect: viewCrop, slack: 12) else {
                return
            }
            handle = hit
            startCrop = model.state.crop
            dragHandle = hit
            dragCrop = startCrop
            model.beginEdit()
        }
        let dx = Double(value.location.x - value.startLocation.x) / Double(imageRect.width)
        let dy = Double(value.location.y - value.startLocation.y) / Double(imageRect.height)
        guard let sourceSize = model.canvasOrientedSize else { return }
        let ratio = model.state.cropAspect.pixelRatio(imageWidth: sourceSize.0, imageHeight: sourceSize.1)
        let next = CropMath.resized(
            start: startCrop,
            handle: handle,
            dx: dx,
            dy: dy,
            pixelRatio: ratio,
            imageWidth: sourceSize.0,
            imageHeight: sourceSize.1
        )
        model.setCrop(next)
    }

    private func dragAnnotate(_ value: DragGesture.Value, imageRect: CGRect) {
        guard imageRect.width > 1, imageRect.height > 1 else { return }
        let crop = model.displayCrop
        let startedInside = imageRect.contains(value.startLocation)

        if model.annotateTool == .select {
            if movingID == nil {
                guard startedInside else { return }
                if let hit = AnnotationGeometry.hitHandle(
                    model.state.annotations,
                    at: value.startLocation,
                    imageRect: imageRect,
                    crop: crop
                ) {
                    movingID = hit.id
                    movingOriginal = hit.annotation
                    reshapeHandle = hit.handle
                    model.selectedAnnotationID = hit.id
                } else if let id = AnnotationGeometry.hitTest(
                    model.state.annotations,
                    at: value.startLocation,
                    imageRect: imageRect,
                    crop: crop
                ), let original = model.state.annotations.first(where: { $0.id == id }) {
                    movingID = id
                    movingOriginal = original
                    reshapeHandle = nil
                    model.selectedAnnotationID = id
                } else {
                    model.selectedAnnotationID = nil
                    reshapeHandle = nil
                    return
                }
            }
            guard let id = movingID, let original = movingOriginal else { return }
            if let handle = reshapeHandle {
                guard hypot(value.translation.width, value.translation.height) > 2 else { return }
                let unit = unitPoint(value.location, imageRect: imageRect, crop: crop)
                model.reshapeAnnotation(id: id, from: original, handle: handle, to: unit)
            } else {
                let dx = Double(value.location.x - value.startLocation.x) / Double(imageRect.width) * crop.width
                let dy = Double(value.location.y - value.startLocation.y) / Double(imageRect.height) * crop.height
                model.moveAnnotation(id: id, from: original, dx: dx, dy: dy)
            }
            return
        }

        if model.annotateTool == .text { return }
        guard let kind = model.annotateTool.kind else { return }

        if draft == nil {
            guard startedInside else { return }
            let start = unitPoint(value.startLocation, imageRect: imageRect, crop: crop)
            draft = model.makeMark(kind: kind, points: [start], text: "")
            return
        }

        let current = unitPoint(value.location, imageRect: imageRect, crop: crop)
        guard var mark = draft else { return }
        if kind == .pen || kind == .marker {
            guard let last = mark.points.last else { return }
            let dx = current.x - last.x
            let dy = current.y - last.y
            if hypot(dx, dy) >= 0.004 {
                mark.points.append(current)
                draft = mark
            }
        } else if mark.points.count == 1 {
            mark.points.append(current)
            draft = mark
        } else {
            mark.points[mark.points.count - 1] = current
            draft = mark
        }
    }

    private func finishDraft(_ mark: Annotation) {
        guard AnnotationGeometry.isSubstantial(mark) else { return }
        model.addAnnotation(mark)
    }

    private func placeText(at point: CGPoint, imageRect: CGRect) {
        guard imageRect.width > 1, imageRect.contains(point) else { return }
        let note = model.noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else {
            model.status = "Type a note, then click the photo."
            model.statusIsError = false
            return
        }
        let anchor = unitPoint(point, imageRect: imageRect, crop: model.displayCrop)
        model.addAnnotation(model.makeMark(kind: .text, points: [anchor], text: note))
        model.status = "Note added."
    }

    private func unitPoint(_ point: CGPoint, imageRect: CGRect, crop: CropRect) -> NormPoint {
        let vx = (Double(point.x) - Double(imageRect.minX)) / Double(imageRect.width)
        let vy = (Double(point.y) - Double(imageRect.minY)) / Double(imageRect.height)
        return NormPoint(x: crop.x + vx * crop.width, y: crop.y + vy * crop.height)
    }

    private func dragPan(_ value: DragGesture.Value) {
        guard model.hasImage, !model.fitToWindow else { return }
        let origin: CGSize
        if panning {
            origin = panOrigin
        } else {
            origin = model.pan
            panOrigin = origin
            panning = true
        }
        model.pan = CGSize(
            width: origin.width + value.translation.width,
            height: origin.height + value.translation.height
        )
    }

    private func installScroll() {
        scrollMonitor.install { event in
            guard model.canvasWindowRect.contains(event.locationInWindow) else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
            let zooming = event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.option)
                || model.fitToWindow
            if zooming {
                guard abs(delta) > 0.01 else { return nil }
                model.zoom(by: exp(delta * 0.01))
            } else {
                model.pan.width += event.scrollingDeltaX
                model.pan.height -= event.scrollingDeltaY
            }
            return nil
        }
    }

    private func installKeys() {
        keyMonitor.install(matching: [.keyDown, .keyUp]) { event in
            guard model.tool == .annotate else { return event }
            if let responder = NSApp.keyWindow?.firstResponder {
                if responder is NSTextView || responder is NSTextField { return event }
            }
            if let step = arrowStep(event.keyCode), model.annotateTool == .select {
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                    return event
                }
                if event.type == .keyUp {
                    guard model.isNudging else { return event }
                    model.finishNudge()
                    return nil
                }
                guard model.selectedAnnotationID != nil else { return event }
                let amount = event.modifierFlags.contains(.shift) ? 0.02 : 0.002
                model.nudgeSelected(dx: step.0 * amount, dy: step.1 * amount)
                return nil
            }
            guard event.type == .keyDown else { return event }
            guard event.keyCode == 51 || event.keyCode == 117 else { return event }
            if event.modifierFlags.contains(.command) { return event }
            guard model.selectedAnnotationID != nil else { return event }
            model.deleteSelectedAnnotation()
            return nil
        }
    }

    private func arrowStep(_ keyCode: UInt16) -> (Double, Double)? {
        switch keyCode {
        case 123: return (-1, 0)
        case 124: return (1, 0)
        case 125: return (0, 1)
        case 126: return (0, -1)
        default: return nil
        }
    }

    private func fitScale(image: CGSize, view: CGSize) -> CGFloat {
        guard image.width > 1, image.height > 1 else { return 1 }
        let availW = max(1, view.width - 36)
        let availH = max(1, view.height - 36)
        return min(availW / image.width, availH / image.height)
    }

    private func placedRect(image: CGSize, view: CGSize, scale: CGFloat, pan: CGSize) -> CGRect {
        guard image.width > 1 else { return .zero }
        let width = image.width * scale
        let height = image.height * scale
        let x = (view.width - width) / 2 + pan.width
        let y = (view.height - height) / 2 + pan.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct CropOverlay: View {
    var imageRect: CGRect
    var crop: CropRect

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(
                x: imageRect.minX + crop.x * imageRect.width,
                y: imageRect.minY + crop.y * imageRect.height,
                width: max(1, crop.width * imageRect.width),
                height: max(1, crop.height * imageRect.height)
            )
            var outside = Path()
            outside.addRect(CGRect(origin: .zero, size: size))
            outside.addRect(rect)
            context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))

            var frame = Path()
            frame.addRect(rect)
            context.stroke(frame, with: .color(Theme.amber), lineWidth: 1.5)

            var lines = Path()
            for step in 1...2 {
                let x = rect.minX + rect.width * CGFloat(step) / 3
                let y = rect.minY + rect.height * CGFloat(step) / 3
                lines.move(to: CGPoint(x: x, y: rect.minY))
                lines.addLine(to: CGPoint(x: x, y: rect.maxY))
                lines.move(to: CGPoint(x: rect.minX, y: y))
                lines.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(lines, with: .color(.white.opacity(0.35)), lineWidth: 0.6)

            let points = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.midY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]
            for point in points {
                let handle = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
                context.fill(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(Theme.amber))
                context.stroke(Path(roundedRect: handle, cornerRadius: 1.5), with: .color(Theme.ink), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 14
            let dark = Color(white: 0.16)
            let light = Color(white: 0.22)
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var col = 0
                var x: CGFloat = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    context.fill(Path(rect), with: .color((row + col).isMultiple(of: 2) ? dark : light))
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}

private struct WindowRectProbe: NSViewRepresentable {
    var onChange: (NSRect) -> Void

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
        DispatchQueue.main.async { nsView.publish() }
    }

    final class ProbeView: NSView {
        var onChange: ((NSRect) -> Void)?

        override func layout() {
            super.layout()
            publish()
        }

        func publish() {
            guard window != nil else { return }
            onChange?(convert(bounds, to: nil))
        }
    }
}

private struct CanvasInteraction<G: Gesture>: ViewModifier {
    var enabled: Bool
    var gesture: G

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.gesture(gesture)
        } else {
            content
        }
    }
}

private final class KeyMonitor: ObservableObject {
    private var token: Any?

    func install(
        matching mask: NSEvent.EventTypeMask = [.keyDown],
        _ handler: @escaping (NSEvent) -> NSEvent?
    ) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}

private final class ScrollMonitor: ObservableObject {
    private var token: Any?

    func install(_ handler: @escaping (NSEvent) -> NSEvent?) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
