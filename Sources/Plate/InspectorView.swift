import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: AppModel
    @FocusState private var editingNote: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.tool.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if model.isRendering {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.tool {
                    case .adjust:
                        adjust
                    case .crop:
                        crop
                    case .looks:
                        looks
                    case .annotate:
                        annotate
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .background(Theme.panel)
    }

    private var adjust: some View {
        VStack(alignment: .leading, spacing: 14) {
            HistogramView(bins: model.histogram)
            slider("Exposure", value: \.exposure, range: -2...2) { String(format: "%+.2f", $0) }
            slider("Brightness", value: \.brightness, range: -1...1, asPercent: true)
            slider("Contrast", value: \.contrast, range: -1...1, asPercent: true)
            slider("Highlights", value: \.highlights, range: -1...1, asPercent: true)
            slider("Shadows", value: \.shadows, range: -1...1, asPercent: true)
            slider("Saturation", value: \.saturation, range: -1...1, asPercent: true)
            slider("Temperature", value: \.temperature, range: -1...1, asPercent: true)
            slider("Tint", value: \.tint, range: -1...1, asPercent: true)
            slider("Sharpness", value: \.sharpness, range: 0...1, asPercent: true)
            slider("Vignette", value: \.vignette, range: 0...1, asPercent: true)
            Text("Double-click a label to reset it.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            Button("Reset Color") { resetColor() }
                .buttonStyle(PlateButtonStyle(kind: .secondary))
                .disabled(!model.hasImage)
            grade
        }
    }

    private var grade: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grade")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
            TextField("Grade name", text: $model.gradeName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.field)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
            HStack(spacing: 6) {
                Button("Save") { model.saveGrade() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(!model.hasImage)
                Button("Apply") { model.applyGrade() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(!model.hasImage || model.savedGrade == nil)
                Button("Clear") { model.clearGrade() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(model.savedGrade == nil)
            }
            Text(gradeHelp)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gradeHelp: String {
        if let name = model.savedGrade?.name {
            return "Saved as “\(name)”. The next photo starts with these sliders and this look."
        }
        return "Save keeps these sliders and the look under one name. The next photo starts there."
    }

    private var crop: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.outputDescription)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text("Aspect")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    Button(aspect.title) { model.setAspect(aspect) }
                        .buttonStyle(PlateButtonStyle(kind: .tool, selected: model.state.cropAspect == aspect))
                        .disabled(!model.hasImage)
                }
            }
            HStack(spacing: 6) {
                iconButton("rotate.left", help: "Rotate Left") { model.apply(.rotateCCW) }
                iconButton("rotate.right", help: "Rotate Right") { model.apply(.rotateCW) }
                iconButton("arrow.left.and.right", help: "Flip Horizontal") {
                    model.apply(.flipH)
                }
                iconButton("arrow.up.and.down", help: "Flip Vertical") {
                    model.apply(.flipV)
                }
            }
            PlateSlider(
                title: "Straighten",
                value: Binding(
                    get: { model.state.straighten },
                    set: { model.setStraighten($0) }
                ),
                range: -45...45,
                text: { String(format: "%+.1f°", $0) },
                onEdit: { editing in
                    if editing { model.beginEdit() } else { model.commitEdit() }
                },
                onReset: {
                    model.setStraighten(0)
                    model.commitEdit()
                }
            )
            .disabled(!model.hasImage)
            Button("Reset Crop") { model.resetCrop() }
                .buttonStyle(PlateButtonStyle(kind: .secondary))
                .disabled(!model.hasImage)
            Text("Straighten turns the photo a few degrees and keeps the frame inside the picture. Double-click the label to reset it. Drag inside the frame to move the crop. Rotate and flip keep the same pixels inside it.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var looks: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PlateLook.allCases, id: \.self) { look in
                    Button {
                        model.commit { $0.look = look }
                    } label: {
                        VStack(spacing: 6) {
                            thumb(look)
                            Text(look.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlateButtonStyle(kind: .tool, selected: model.state.look == look))
                    .disabled(!model.hasImage)
                }
            }
            Text("A look stacks with the sliders. None clears the look and leaves the sliders.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var annotate: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(AnnotateTool.allCases, id: \.self) { tool in
                    Button {
                        model.annotateTool = tool
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 13, weight: .medium))
                            Text(tool.title)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(PlateButtonStyle(kind: .tool, selected: model.annotateTool == tool))
                    .help(tool.title)
                }
            }

            Text("Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button {
                        model.setMarkupColor(color)
                    } label: {
                        Circle()
                            .fill(color.swiftColor)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                            .padding(2)
                            .background(Circle().fill(Theme.field))
                            .padding(1)
                            .background(
                                Circle().fill(model.markupColor == color ? Theme.amber : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                }
            }

            if model.annotateTool == .select, let mark = model.selectedAnnotation {
                switch mark.kind {
                case .marker:
                    weightSlider(
                        "Marker",
                        value: selectedWeight,
                        range: 0.01...0.08,
                        reset: Annotation.defaultMarker,
                        recordsHistory: true
                    )
                case .text:
                    weightSlider(
                        "Size",
                        value: selectedWeight,
                        range: 0.02...0.12,
                        reset: Annotation.defaultText,
                        recordsHistory: true
                    )
                    noteField(selectedNote, placeholder: "Selected note", commitsSelection: true)
                default:
                    weightSlider(
                        "Stroke",
                        value: selectedWeight,
                        range: 0.002...0.04,
                        reset: Annotation.defaultStroke,
                        recordsHistory: true
                    )
                }
            } else if model.annotateTool == .marker {
                weightSlider("Marker", value: $model.markerWeight, range: 0.01...0.08, reset: Annotation.defaultMarker)
            } else if model.annotateTool == .text {
                weightSlider("Size", value: $model.textWeight, range: 0.02...0.12, reset: Annotation.defaultText)
                noteField($model.noteText, placeholder: "Note", commitsSelection: false)
            } else if model.annotateTool != .select {
                weightSlider("Stroke", value: $model.strokeWeight, range: 0.002...0.04, reset: Annotation.defaultStroke)
            }

            HStack(spacing: 6) {
                Button("Delete") { model.deleteSelectedAnnotation() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(model.selectedAnnotationID == nil)
                Button("Duplicate") { model.duplicateSelectedAnnotation() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(model.selectedAnnotationID == nil)
                Button("Clear") { model.clearAnnotations() }
                    .buttonStyle(PlateButtonStyle(kind: .secondary))
                    .disabled(model.state.annotations.isEmpty)
            }

            Text("Draw on the photo. Select a mark to move it, nudge it with the arrow keys, or duplicate it. Drag a handle to reshape a line, arrow, box, or oval, change its width, or edit its text. Marks follow rotate, flip, and straighten. Save and Copy paint them into the new picture.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedWeight: Binding<Double> {
        Binding(
            get: { model.selectedAnnotation?.weight ?? model.strokeWeight },
            set: { model.setSelectedWeight($0) }
        )
    }

    private var selectedNote: Binding<String> {
        Binding(
            get: { model.selectedAnnotation?.text ?? "" },
            set: { model.setSelectedText($0) }
        )
    }

    private func noteField(_ text: Binding<String>, placeholder: String, commitsSelection: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .focused($editingNote)
            .onSubmit {
                if commitsSelection { model.finishSelectedTextEdit() }
            }
            .onChange(of: editingNote) { focused in
                if commitsSelection, !focused { model.finishSelectedTextEdit() }
            }
    }

    private func weightSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        reset: Double,
        recordsHistory: Bool = false
    ) -> some View {
        PlateSlider(
            title: title,
            value: value,
            range: range,
            text: { String(format: "%.1f", $0 * 100) },
            onEdit: { editing in
                if recordsHistory, !editing { model.commitEdit() }
            },
            onReset: {
                value.wrappedValue = reset
                if recordsHistory { model.commitEdit() }
            }
        )
        .disabled(!model.hasImage)
    }

    private func thumb(_ look: PlateLook) -> some View {
        Group {
            if let image = model.lookThumbs[look] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.field
            }
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func slider(
        _ title: String,
        value keyPath: WritableKeyPath<EditState, Double>,
        range: ClosedRange<Double>,
        asPercent: Bool = false,
        format: ((Double) -> String)? = nil
    ) -> some View {
        PlateSlider(
            title: title,
            value: Binding(
                get: { model.state[keyPath: keyPath] },
                set: { newValue in
                    model.update { $0[keyPath: keyPath] = newValue }
                }
            ),
            range: range,
            text: format ?? { value in
                asPercent ? "\(Int((value * 100).rounded()))" : String(format: "%+.2f", value)
            },
            onEdit: { editing in
                if editing { model.beginEdit() } else { model.commitEdit() }
            },
            onReset: {
                model.commit { $0[keyPath: keyPath] = 0 }
            }
        )
        .disabled(!model.hasImage)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(PlateButtonStyle(kind: .tool))
        .help(help)
        .disabled(!model.hasImage)
    }

    private func resetColor() {
        model.commit {
            $0.exposure = 0
            $0.brightness = 0
            $0.contrast = 0
            $0.highlights = 0
            $0.shadows = 0
            $0.saturation = 0
            $0.temperature = 0
            $0.tint = 0
            $0.sharpness = 0
            $0.vignette = 0
            $0.look = .none
        }
    }
}

private struct PlateSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var text: (Double) -> String
    var onEdit: (Bool) -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .onTapGesture(count: 2) { onReset() }
                Spacer()
                Text(text(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Slider(value: $value, in: range, onEditingChanged: onEdit)
                .tint(Theme.amber)
        }
    }
}

private struct HistogramView: View {
    var bins: [Int]

    var body: some View {
        Canvas { context, size in
            let peak = max(bins.max() ?? 0, 1)
            let slot = size.width / CGFloat(max(bins.count, 1))
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, bin) in bins.enumerated() {
                let x = CGFloat(index) * slot
                let h = CGFloat(bin) / CGFloat(peak) * (size.height - 2)
                path.addLine(to: CGPoint(x: x, y: size.height - h))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(Theme.amber.opacity(0.85)))
        }
        .frame(height: 64)
        .background(Theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}
