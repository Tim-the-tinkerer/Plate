import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptionContentView: View {
    @ObservedObject var model: CaptionModel
    var canUseEditedPhoto = false
    var useEditedPhoto: () -> Void = {}
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            HStack(alignment: .top, spacing: 0) {
                canvas
                Rectangle()
                    .fill(Theme.border.opacity(0.8))
                    .frame(width: 1)
                inspector
                    .frame(width: 312)
            }
            Divider().overlay(Theme.border)
            footer
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(Theme.yellow)
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: handleDrop)
        .onReceive(NotificationCenter.default.publisher(for: .captionOpen)) { _ in
            model.openFilePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionSavePNG)) { _ in
            model.saveFilePanel(jpeg: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionSaveJPEG)) { _ in
            model.saveFilePanel(jpeg: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionSaveProject)) { _ in
            model.saveProjectPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionCopy)) { _ in
            model.copyImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionPaste)) { _ in
            model.paste()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionClearText)) { _ in
            model.clearText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionCloseImage)) { _ in
            model.closeImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionAdd)) { _ in
            model.addText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionDuplicate)) { _ in
            model.duplicateSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionMemeStyle)) { _ in
            model.applyMemeStyle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captionBlank)) { note in
            let kind = BlankKind(rawValue: note.object as? String ?? "") ?? .square
            model.makeBlank(kind)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CAPTION")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.yellow)
                Text("Top line, bottom line, a margin, and any text you drag")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if canUseEditedPhoto {
                Button("Use photo") { useEditedPhoto() }
                    .buttonStyle(CaptionButtonStyle())
                    .help("Replace this picture with the photo open in Plate. The grade, crop, and marks are included. The words stay.")
            }
            if !model.summary.isEmpty {
                Text(model.summary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.yellowDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.panel)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let imageSize = model.previewPixelSize
            let fitted = CanvasMap.fitted(image: imageSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.field)
                if let image = model.preview, fitted.width > 2 {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                    if !model.marks.contains(where: \.hasVisibleText) {
                        Text("Type a top and bottom line.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .position(x: fitted.midX, y: fitted.midY)
                            .allowsHitTesting(false)
                    }
                    ForEach(model.hits) { hit in
                        hitTarget(hit, imageSize: imageSize, fitted: fitted)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Theme.yellowDim)
                        Text("Drop an image.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(targeted ? Theme.yellow : Theme.border.opacity(0.85), lineWidth: targeted ? 1.5 : 1)
            )
            .coordinateSpace(name: "canvas")
        }
        .padding(16)
        .background(Theme.bg)
    }

    private func hitTarget(_ hit: CaptionHit, imageSize: CGSize, fitted: CGRect) -> some View {
        let mapped = CanvasMap.viewRect(hit.rect, image: imageSize, fitted: fitted)
        let selected = model.selectedID == hit.id
        let width = max(mapped.width, 28)
        let height = max(mapped.height, 22)
        return Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Theme.yellow : Color.white.opacity(0.01), lineWidth: selected ? 1.5 : 1)
            )
            .position(x: mapped.midX, y: mapped.midY)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        model.dragChanged(id: hit.id, translation: value.translation, fitted: fitted.size)
                    }
                    .onEnded { _ in
                        NSCursor.openHand.set()
                        model.dragEnded()
                    }
            )
            .onTapGesture {
                model.selectedID = hit.id
            }
            .onHover { inside in
                if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
            }
            .help("Drag to place. The top and bottom lines unpin when you move them.")
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let top = model.marks.first(where: { $0.role == .top }) {
                    CaptionEditor(
                        model: model,
                        id: top.id,
                        title: top.pin == .top ? "TOP" : "TOP · PLACED",
                        prompt: "Top caption"
                    )
                }
                if let bottom = model.marks.first(where: { $0.role == .bottom }) {
                    CaptionEditor(
                        model: model,
                        id: bottom.id,
                        title: bottom.pin == .bottom ? "BOTTOM" : "BOTTOM · PLACED",
                        prompt: "Bottom caption"
                    )
                }

                sectionLabel("CAPTIONS")
                HStack(spacing: 6) {
                    choice("Add", on: false, action: model.addText)
                    choice("Duplicate", on: false, action: model.duplicateSelected)
                    choice("Delete", on: false, action: model.deleteSelected)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 4) {
                    ForEach(model.marks) { mark in
                        markRow(mark)
                    }
                }

                Divider().overlay(Theme.border)
                marginBlock
                Divider().overlay(Theme.border)
                styleBlock
            }
            .padding(14)
        }
        .background(Theme.panel)
    }

    private var marginBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MARGIN")
            HStack(spacing: 6) {
                ForEach([MarginPreset.none, .bottom, .right, .left], id: \.rawValue) { preset in
                    choice(preset.title, on: model.margins.sameEdges(as: preset.margins)) {
                        model.applyMarginPreset(preset)
                    }
                }
                Spacer(minLength: 0)
            }
            choice("Fit caption", on: false, action: model.fitSelectedInMargin)
                .help("Wrap the selected caption inside the white space")
            Text("Bottom text fits the bottom strip. Fit caption wraps the selected line into the white space. Raise Size to fill it. It stays off the photo.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            sliderRow("Bottom", value: model.marginBinding(\.bottom), range: 0...1, percent: true)
            sliderRow("Right", value: model.marginBinding(\.right), range: 0...1, percent: true)
            sliderRow("Left", value: model.marginBinding(\.left), range: 0...1, percent: true)
            sliderRow("Top", value: model.marginBinding(\.top), range: 0...1, percent: true)
            colorRow("Mat", color: model.margins.color, set: model.setMatColor)
        }
    }

    private var styleBlock: some View {
        let selected = model.selected
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("STYLE · \((selected?.role.title ?? "Caption").uppercased())")

            HStack {
                Text("Font")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Picker("Font", selection: model.binding(\.font)) {
                    ForEach(CaptionFont.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }

            sliderRow("Size", value: model.binding(\.size), range: 0.03...0.18, percent: true)
            sliderRow("Width", value: model.binding(\.width), range: 0.35...1, percent: true)
            sliderRow("Outline", value: model.binding(\.strokeWidth), range: 0...0.32, percent: true)

            HStack(spacing: 6) {
                choice("Left", on: selected?.alignment == .left) { model.binding(\.alignment).wrappedValue = .left }
                choice("Center", on: selected?.alignment == .center) { model.binding(\.alignment).wrappedValue = .center }
                choice("Right", on: selected?.alignment == .right) { model.binding(\.alignment).wrappedValue = .right }
                Spacer()
                choice("Caps", on: selected?.uppercase == true) {
                    model.binding(\.uppercase).wrappedValue.toggle()
                }
            }

            HStack(spacing: 6) {
                choice("Pin top", on: selected?.pin == .top) { model.setPin(.top) }
                choice("Pin bottom", on: selected?.pin == .bottom) { model.setPin(.bottom) }
                choice("Free", on: selected?.pin == .free) { model.setPin(.free) }
            }

            colorRow("Fill", color: selected?.fill ?? .white, set: model.setFill)
            colorRow("Outline", color: selected?.stroke ?? .black, set: model.setStroke)

            Button("Meme style") { model.applyMemeStyle() }
                .buttonStyle(CaptionButtonStyle(kind: .ghost))
                .help("Impact, white letters, black outline, centered, capitals")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open…") { model.openFilePanel() }
                .buttonStyle(CaptionButtonStyle())
            Button("Paste") { model.paste() }
                .buttonStyle(CaptionButtonStyle())
            Button("Square") { model.makeBlank(.square) }
                .buttonStyle(CaptionButtonStyle())
                .help("Blank 1080×1080")
            Button("Wide") { model.makeBlank(.wide) }
                .buttonStyle(CaptionButtonStyle())
                .help("Blank 1920×1080")
            Button("Story") { model.makeBlank(.story) }
                .buttonStyle(CaptionButtonStyle())
                .help("Blank 1080×1920")
            Spacer(minLength: 8)
            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(model.copiedFlash ? "Copied" : "Copy") { model.copyImage() }
                .buttonStyle(CaptionButtonStyle(kind: .primary))
                .disabled(!model.hasImage || model.isExporting)
            Button("Project") { model.saveProjectPanel() }
                .buttonStyle(CaptionButtonStyle())
                .disabled(!model.hasImage || model.isExporting)
                .help("Save a .caption project you can open and keep editing")
            Button("Save PNG") { model.saveFilePanel(jpeg: false) }
                .buttonStyle(CaptionButtonStyle())
                .disabled(!model.hasImage || model.isExporting)
            Button("Save JPEG") { model.saveFilePanel(jpeg: true) }
                .buttonStyle(CaptionButtonStyle())
                .disabled(!model.hasImage || model.isExporting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panel)
    }

    private func markRow(_ mark: CaptionMark) -> some View {
        let on = model.selectedID == mark.id
        return Button {
            model.selectedID = mark.id
        } label: {
            HStack(spacing: 8) {
                Text(mark.role.title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .frame(width: 58, alignment: .leading)
                Text(mark.previewLine)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Theme.ink : Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? Theme.yellow : Theme.field)
            )
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        percent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.yellow)
            }
            Slider(value: value, in: range, onEditingChanged: { editing in
                model.trackGesture(editing, name: title)
            })
                .controlSize(.small)
        }
    }

    private func colorRow(_ title: String, color: CaptionColor, set: @escaping (CaptionColor) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(color.hex)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 5) {
                ForEach(CaptionColor.swatches, id: \.name) { item in
                    Button {
                        set(item.color)
                    } label: {
                        Circle()
                            .fill(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().stroke(
                                    item.color.matches(color) ? Theme.yellow : Theme.border,
                                    lineWidth: item.color.matches(color) ? 2 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
            HexField(color: color, set: set)
        }
    }

    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(on ? Theme.ink : Theme.muted)
                .background(Capsule().fill(on ? Theme.yellow : Theme.elevated))
                .overlay(Capsule().stroke(on ? Theme.yellowDim : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let path = String(data: data, encoding: .utf8),
                   let url = URL(string: path) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty {
                model.load(urls: urls)
            }
        }
        return true
    }
}

private struct CaptionEditor: View {
    @ObservedObject var model: CaptionModel
    let id: UUID
    let title: String
    let prompt: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            ZStack(alignment: .topLeading) {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(prompt)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted.opacity(0.85))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 64)
                    .focused($focused)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(focused ? Theme.yellowDim : Theme.border.opacity(0.9), lineWidth: 1)
            )
        }
        .onAppear { pullIfNeeded(force: true) }
        .onChange(of: id) { _ in pullIfNeeded(force: true) }
        .onChange(of: draft) { value in
            model.setText(id, value)
        }
        .onChange(of: model.textToken) { _ in
            pullIfNeeded(force: false)
        }
        .onChange(of: focused) { isFocused in
            if isFocused { model.selectedID = id }
        }
    }

    private func pullIfNeeded(force: Bool) {
        let current = model.mark(id: id)?.text ?? ""
        if force || current != draft {
            draft = current
        }
    }
}

private struct HexField: View {
    let color: CaptionColor
    let set: (CaptionColor) -> Void
    @State private var draft = ""

    var body: some View {
        TextField("RRGGBB", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.border.opacity(0.8), lineWidth: 1)
            )
            .frame(width: 88)
            .onAppear { draft = color.hex }
            .onChange(of: color.hex) { hex in
                if draft.uppercased() != hex { draft = hex }
            }
            .onSubmit { apply() }
            .onChange(of: draft) { value in
                let cleaned = value.filter(\.isHexDigit)
                guard cleaned.count == 6, let parsed = CaptionColor.parse(cleaned) else { return }
                if !parsed.matches(color) { set(parsed) }
            }
            .help("Type RRGGBB and press Return")
    }

    private func apply() {
        guard let parsed = CaptionColor.parse(draft) else { return }
        set(parsed)
        draft = parsed.hex
    }
}

enum CanvasMap {
    static func fitted(image: CGSize, in view: CGSize) -> CGRect {
        let inset = CGRect(origin: .zero, size: view).insetBy(dx: 8, dy: 8)
        guard image.width > 1, image.height > 1, inset.width > 1, inset.height > 1 else {
            return .zero
        }
        let scale = min(inset.width / image.width, inset.height / image.height)
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(
            x: inset.minX + (inset.width - width) / 2,
            y: inset.minY + (inset.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func viewRect(_ rect: CGRect, image: CGSize, fitted: CGRect) -> CGRect {
        guard image.width > 1, image.height > 1 else { return .zero }
        let scaleX = fitted.width / image.width
        let scaleY = fitted.height / image.height
        return CGRect(
            x: fitted.minX + rect.minX * scaleX,
            y: fitted.minY + rect.minY * scaleY,
            width: max(1, rect.width * scaleX),
            height: max(1, rect.height * scaleY)
        )
    }
}
