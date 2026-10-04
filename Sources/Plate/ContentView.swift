import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            toolRail
            VStack(spacing: 0) {
                header
                ZStack {
                    CanvasView(model: model)
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.amber, lineWidth: 2)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                bottomBar
            }
            Divider().overlay(Theme.line)
            InspectorView(model: model)
                .frame(width: 292)
        }
        .background(Theme.bg)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .background(WindowTitle(title: model.windowTitle, representedURL: model.sourceURL))
    }

    private var toolRail: some View {
        VStack(spacing: 8) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button {
                    model.select(tool: tool)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 16, weight: .medium))
                        Text(tool.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PlateButtonStyle(kind: .tool, selected: model.tool == tool))
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 84)
        .background(Theme.panel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isDirty ? Theme.amber : Color.clear)
                .frame(width: 7, height: 7)
            Text(model.fileName ?? "Plate")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            Text(model.hasImage ? model.outputDescription : "Image editor")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Theme.bg)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button("Undo") { model.undo() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.canUndo)
            Button("Redo") { model.redo() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.canRedo)
            Button("Reset") { model.resetAll() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.isDirty)

            Spacer()

            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(model.statusIsError ? Theme.danger : Theme.muted)
                .lineLimit(1)

            Spacer()

            Button("−") { model.zoomOut() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.hasImage)
            Button(model.fitToWindow ? "Fit \(model.zoomPercent)%" : "\(model.zoomPercent)%") {
                model.zoomFit()
            }
            .buttonStyle(PlateButtonStyle(kind: .ghost))
            .disabled(!model.hasImage)
            Button("100%") { model.zoomActual() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.hasImage)
            Button("+") { model.zoomIn() }
                .buttonStyle(PlateButtonStyle(kind: .ghost))
                .disabled(!model.hasImage)

            compareButton
            Button("Save…") { model.savePanel() }
                .buttonStyle(PlateButtonStyle(kind: .primary))
                .disabled(!model.hasImage)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Theme.bg)
    }

    private var compareButton: some View {
        Text("Original")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(model.showOriginal ? Theme.ink : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(model.showOriginal ? Theme.amber : Theme.elevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(model.showOriginal ? Theme.amber : Theme.line, lineWidth: 1))
            .opacity(model.hasImage ? 1 : 0.4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.toggleOriginal(true) }
                    .onEnded { _ in model.toggleOriginal(false) }
            )
            .help("Hold to compare with the original")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let fileURL = item as? URL {
                url = fileURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let text = item as? String {
                url = URL(string: text)
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                model.load(url: url)
            }
        }
        return true
    }
}

private struct WindowTitle: NSViewRepresentable {
    var title: String
    var representedURL: URL?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
            nsView.window?.representedURL = representedURL
        }
    }
}
