import AppKit
import SwiftUI

@main
struct MainEntry {
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--self-test") {
            if let err = SelfTest.run() {
                fputs("SELF-TEST FAILED: \(err)\n", stderr)
                exit(1)
            }
            print("SELF-TEST OK")
            print("Identity, grade, crop, straighten, orientation, marks, undo, PNG round-trip, captions.")
            exit(0)
        }

        if args.contains("--help") || args.contains("-h") {
            print(helpText)
            exit(0)
        }

        if args.contains("--version") {
            print("\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))")
            exit(0)
        }

        if CaptionCLI.hasWork(args) {
            if CLI.hasEdits(args) {
                CLI.runGradedCaption(args)
            } else {
                do {
                    _ = try CaptionCLI.execute(args)
                } catch {
                    fputs("error: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            exit(0)
        }

        if CLI.wantsCLI(args) {
            CLI.run(args)
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private static let helpText = """
    \(AppInfo.name) \(AppInfo.version) — image editor, with captions

    Usage:
      Plate                              Launch the app
      Plate --self-test                  Engine checks
      Plate INPUT [options]

    Edit:
      --exposure -2..2                   Stops. 0 leaves the file alone
      --brightness -1..1
      --contrast -1..1
      --highlights -1..1                 Negative pulls bright areas down
      --shadows -1..1                    Positive lifts dark areas
      --saturation -1..1                 -1 is gray
      --temperature -1..1                Positive is warmer
      --tint -1..1                       Positive is magenta
      --sharpness 0..1
      --vignette 0..1
      --look none|mono|sepia|warm|cool|fade|punch
      --rotate 0|90|180|270              Quarter-turns clockwise. Negatives work
      --straighten -45..45               Degrees clockwise. The frame stays inside the photo
      --flip-h
      --flip-v
      --crop x,y,width,height            Normalized, after rotation and straighten

    Caption:
      --top TEXT                         Line pinned to the top
      --bottom TEXT                      Line pinned to the bottom
      --at X,Y TEXT                      Extra caption. X and Y are 0...1 from the top left
      --font impact|condensed|sans|serif|mono|marker
      --size 0.02...0.25                 Letter size as a fraction of the photo width
      --width 0.2...1                    Wrap width as a fraction of the canvas width
      --fill RRGGBB|name                 Letter color
      --stroke RRGGBB|name               Outline color
      --stroke-width 0...0.45            Outline thickness as a fraction of the letter size
      --align left|center|right
      --no-caps                          Keep the typing as written
      --margin-top 0...1.5               Space above the photo, as a fraction of its height
      --margin-bottom 0...1.5            Space below the photo. The bottom line wraps inside it
      --margin-left 0...1.5              Space to the left of the photo
      --margin-right 0...1.5             Space to the right of the photo
      --mat RRGGBB|name                  Color of that space. Default white

    Output:
      --jpeg                             Write JPEG instead of PNG
      --quality 0.05..1                  JPEG quality. Default 0.92
      -o, --out PATH                     Edit default: INPUT-edited.png
                                         Caption default: INPUT-caption.png

    The original file is never overwritten. Grade flags and caption flags can
    be used together. The grade is applied first, then the words.

    Examples:
      Plate photo.jpg --exposure 0.3 --look warm -o print.jpg --jpeg
      Plate photo.png --rotate 90 --crop 0.1,0.1,0.8,0.8
      Plate photo.png --top "ONE DOES NOT SIMPLY" --bottom "WALK INTO MORDOR"
      Plate photo.jpg --exposure 0.4 --bottom "and that's the joke" --margin-bottom 0.4 --fill black
    """
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let model = AppModel()
    private let captions = CaptionModel()
    private var pendingURLs: [URL] = []
    private var captionHandoff = 0
    /// Set once a close or quit has already asked, so the following quit does not ask again.
    private var discardConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMainMenu()

        let hosting = NSHostingView(rootView: ContentView(
            model: model,
            captions: captions,
            showCaption: { [weak self] in self?.enterCaption(bringPhoto: true) },
            useEditedPhoto: { [weak self] in self?.useEditedPhoto(onlyIfFresh: false) },
            openProject: { [weak self] url in self?.openProject(url) }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.name
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.windowNS
        window.contentView = hosting
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        window.setFrameAutosaveName("PlateMainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        if !pendingURLs.isEmpty {
            accept(pendingURLs)
            pendingURLs = []
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if discardConfirmed || model.confirmDiscard(replacing: false) {
            discardConfirmed = true
            return .terminateNow
        }
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if discardConfirmed { return true }
        guard model.confirmDiscard(replacing: false) else { return false }
        discardConfirmed = true
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if window == nil {
            pendingURLs = urls
        } else {
            accept(urls)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if window == nil {
            pendingURLs = [url]
        } else {
            accept([url])
        }
        return true
    }

    private func accept(_ urls: [URL]) {
        guard let url = urls.first else { return }
        if CaptionPaths.isProject(url) {
            openProject(url)
        } else if model.workspace == .caption {
            captions.load(url: url)
        } else {
            model.load(url: url)
        }
    }

    private func openProject(_ url: URL) {
        captionHandoff += 1
        enterCaption(bringPhoto: false)
        captions.load(url: url)
    }

    private func enterCaption(bringPhoto: Bool) {
        model.showCaption()
        guard bringPhoto else { return }
        useEditedPhoto(onlyIfFresh: true)
    }

    private func useEditedPhoto(onlyIfFresh: Bool) {
        guard model.hasImage else {
            captions.status = "Open a photo in Plate first."
            return
        }
        if onlyIfFresh, !captions.isFreshCanvas { return }
        captionHandoff += 1
        let token = captionHandoff
        captions.status = "Bringing the edited photo across…"
        model.renderForCaption { [weak self] image, name in
            guard let self, self.captionHandoff == token else { return }
            guard self.model.workspace == .caption else { return }
            if onlyIfFresh, !self.captions.isFreshCanvas { return }
            guard let image else {
                self.captions.status = "Could not read the edited photo."
                return
            }
            self.captions.usePhoto(image, name: name)
        }
    }

    private func editingText() -> NSText? {
        window?.firstResponder as? NSText
    }

    @objc private func openImage(_ sender: Any?) {
        if model.workspace == .caption {
            captions.openFilePanel()
        } else {
            model.openPanel()
        }
    }

    @objc private func saveImage(_ sender: Any?) {
        if model.workspace == .caption {
            captions.saveFilePanel(jpeg: false)
        } else {
            model.savePanel()
        }
    }

    @objc private func saveJPEG(_ sender: Any?) { captions.saveFilePanel(jpeg: true) }
    @objc private func saveProject(_ sender: Any?) { captions.saveProjectPanel() }

    @objc private func copyImage(_ sender: Any?) {
        if model.workspace == .caption, let text = editingText() {
            text.copy(sender)
            return
        }
        if model.workspace == .caption {
            captions.copyImage()
        } else {
            model.copyImage()
        }
    }

    @objc private func pasteImage(_ sender: Any?) {
        if model.workspace == .caption, let text = editingText() {
            text.paste(sender)
            return
        }
        if model.workspace == .caption {
            captions.paste()
        } else {
            model.paste()
        }
    }

    @objc private func undoEdit(_ sender: Any?) {
        if model.workspace == .caption {
            if let text = editingText(), let manager = text.undoManager, manager.canUndo {
                manager.undo()
                return
            }
            captions.undo()
            return
        }
        model.undo()
    }

    @objc private func redoEdit(_ sender: Any?) {
        if model.workspace == .caption {
            if let text = editingText(), let manager = text.undoManager, manager.canRedo {
                manager.redo()
                return
            }
            captions.redo()
            return
        }
        model.redo()
    }

    @objc private func resetEdit(_ sender: Any?) {
        if model.workspace == .caption {
            captions.clearText()
        } else {
            model.resetAll()
        }
    }

    @objc private func loadSample(_ sender: Any?) {
        model.select(tool: model.tool)
        model.loadSample()
    }

    @objc private func rotateCW(_ sender: Any?) { model.apply(.rotateCW) }
    @objc private func rotateCCW(_ sender: Any?) { model.apply(.rotateCCW) }
    @objc private func flipHorizontal(_ sender: Any?) { model.apply(.flipH) }
    @objc private func flipVertical(_ sender: Any?) { model.apply(.flipV) }
    @objc private func zoomIn(_ sender: Any?) { model.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { model.zoomOut() }
    @objc private func zoomFit(_ sender: Any?) { model.zoomFit() }
    @objc private func zoomActual(_ sender: Any?) { model.zoomActual() }
    @objc private func showAdjust(_ sender: Any?) { model.select(tool: .adjust) }
    @objc private func showCrop(_ sender: Any?) { model.select(tool: .crop) }
    @objc private func showLooks(_ sender: Any?) { model.select(tool: .looks) }
    @objc private func showAnnotate(_ sender: Any?) { model.select(tool: .annotate) }
    @objc private func showCaptionMode(_ sender: Any?) { enterCaption(bringPhoto: true) }
    @objc private func deleteAnnotation(_ sender: Any?) { model.deleteSelectedAnnotation() }
    @objc private func duplicateAnnotation(_ sender: Any?) { model.duplicateSelectedAnnotation() }
    @objc private func duplicateCaption(_ sender: Any?) { captions.duplicateSelected() }
    @objc private func addCaption(_ sender: Any?) {
        model.showCaption()
        captions.addText()
    }
    @objc private func memeStyle(_ sender: Any?) {
        model.showCaption()
        captions.applyMemeStyle()
    }
    @objc private func usePhotoMenu(_ sender: Any?) {
        model.showCaption()
        useEditedPhoto(onlyIfFresh: false)
    }
    @objc private func blank(_ sender: NSMenuItem) {
        captionHandoff += 1
        model.showCaption()
        let kind = BlankKind(rawValue: sender.representedObject as? String ?? "") ?? .square
        captions.makeBlank(kind)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let captioning = model.workspace == .caption
        switch menuItem.action {
        case #selector(saveImage(_:)):
            menuItem.title = captioning ? "Save PNG…" : "Save As…"
            if captioning { return captions.hasImage && !captions.isExporting }
            return model.hasImage
        case #selector(saveJPEG(_:)), #selector(saveProject(_:)):
            return captioning && captions.hasImage && !captions.isExporting
        case #selector(undoEdit(_:)):
            if captioning {
                if let text = editingText(), text.undoManager?.canUndo == true {
                    menuItem.title = "Undo"
                    return true
                }
                let name = captions.undoActionName
                menuItem.title = name.isEmpty ? "Undo" : "Undo \(name)"
                return captions.canUndo
            }
            menuItem.title = "Undo"
            return model.canUndo
        case #selector(redoEdit(_:)):
            if captioning {
                if let text = editingText(), text.undoManager?.canRedo == true {
                    menuItem.title = "Redo"
                    return true
                }
                let name = captions.redoActionName
                menuItem.title = name.isEmpty ? "Redo" : "Redo \(name)"
                return captions.canRedo
            }
            menuItem.title = "Redo"
            return model.canRedo
        case #selector(copyImage(_:)):
            if captioning, editingText() != nil { return true }
            return captioning ? captions.hasImage && !captions.isExporting : model.hasImage
        case #selector(resetEdit(_:)):
            menuItem.title = captioning ? "Clear Captions" : "Reset Edits"
            return captioning ? captions.hasImage : model.isDirty
        case #selector(deleteAnnotation(_:)):
            return !captioning && model.selectedAnnotationID != nil
        case #selector(duplicateAnnotation(_:)):
            menuItem.keyEquivalent = captioning ? "" : "d"
            return !captioning && model.selectedAnnotationID != nil
        case #selector(duplicateCaption(_:)):
            menuItem.keyEquivalent = captioning ? "d" : ""
            return captioning && captions.selectedID != nil
        case #selector(rotateCW(_:)), #selector(rotateCCW(_:)),
             #selector(flipHorizontal(_:)), #selector(flipVertical(_:)),
             #selector(zoomIn(_:)), #selector(zoomOut(_:)),
             #selector(zoomFit(_:)), #selector(zoomActual(_:)):
            return !captioning && model.hasImage
        case #selector(usePhotoMenu(_:)):
            return model.hasImage
        default:
            return true
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: AppInfo.name,
            .version: AppInfo.version,
            .applicationVersion: "Version \(AppInfo.version) (\(AppInfo.build))",
            .credits: NSAttributedString(
                string: """
                A darkroom for one photo. Exposure, color, crop, \
                looks, and marks. Caption puts a top line, a bottom \
                line, and a margin on the picture. Closing asks \
                before discarding edits. Save writes a new 8-bit \
                sRGB file and leaves the original alone.
                """,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ]
        if let icon = NSApp.applicationIconImage {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About Plate", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Plate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Plate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let square = fileMenu.addItem(withTitle: "New Square", action: #selector(blank(_:)), keyEquivalent: "n")
        square.target = self
        square.representedObject = BlankKind.square.rawValue
        let wide = fileMenu.addItem(withTitle: "New Wide", action: #selector(blank(_:)), keyEquivalent: "")
        wide.target = self
        wide.representedObject = BlankKind.wide.rawValue
        let story = fileMenu.addItem(withTitle: "New Story", action: #selector(blank(_:)), keyEquivalent: "")
        story.target = self
        story.representedObject = BlankKind.story.rawValue
        fileMenu.addItem(NSMenuItem.separator())
        add(fileMenu, "Open…", #selector(openImage(_:)), "o")
        add(fileMenu, "Save As…", #selector(saveImage(_:)), "s")
        let jpeg = add(fileMenu, "Save JPEG…", #selector(saveJPEG(_:)), "S")
        jpeg.keyEquivalentModifierMask = [.command, .shift]
        let project = add(fileMenu, "Save Project…", #selector(saveProject(_:)), "s")
        project.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(NSMenuItem.separator())
        add(fileMenu, "Load Sample", #selector(loadSample(_:)), "l")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        add(editMenu, "Undo", #selector(undoEdit(_:)), "z")
        let redo = add(editMenu, "Redo", #selector(redoEdit(_:)), "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        add(editMenu, "Copy", #selector(copyImage(_:)), "c")
        add(editMenu, "Paste", #selector(pasteImage(_:)), "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let reset = add(editMenu, "Reset Edits", #selector(resetEdit(_:)), "k")
        reset.keyEquivalentModifierMask = [.command]

        let imageMenuItem = NSMenuItem()
        mainMenu.addItem(imageMenuItem)
        let imageMenu = NSMenu(title: "Image")
        imageMenuItem.submenu = imageMenu
        add(imageMenu, "Rotate Clockwise", #selector(rotateCW(_:)), "]")
        add(imageMenu, "Rotate Counterclockwise", #selector(rotateCCW(_:)), "[")
        add(imageMenu, "Flip Horizontal", #selector(flipHorizontal(_:)), "")
        add(imageMenu, "Flip Vertical", #selector(flipVertical(_:)), "")
        imageMenu.addItem(NSMenuItem.separator())
        add(imageMenu, "Adjust", #selector(showAdjust(_:)), "1")
        let cropItem = add(imageMenu, "Crop", #selector(showCrop(_:)), "2")
        cropItem.keyEquivalentModifierMask = [.command]
        add(imageMenu, "Looks", #selector(showLooks(_:)), "3")
        add(imageMenu, "Annotate", #selector(showAnnotate(_:)), "4")
        add(imageMenu, "Caption", #selector(showCaptionMode(_:)), "5")
        let deleteMark = add(imageMenu, "Delete Annotation", #selector(deleteAnnotation(_:)), "\u{8}")
        deleteMark.keyEquivalentModifierMask = [.command]
        add(imageMenu, "Duplicate Annotation", #selector(duplicateAnnotation(_:)), "d")

        let captionMenuItem = NSMenuItem()
        mainMenu.addItem(captionMenuItem)
        let captionMenu = NSMenu(title: "Caption")
        captionMenuItem.submenu = captionMenu
        add(captionMenu, "Add Text", #selector(addCaption(_:)), "t")
        add(captionMenu, "Duplicate", #selector(duplicateCaption(_:)), "d")
        captionMenu.addItem(NSMenuItem.separator())
        add(captionMenu, "Meme Style", #selector(memeStyle(_:)), "")
        add(captionMenu, "Use Edited Photo", #selector(usePhotoMenu(_:)), "")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        add(viewMenu, "Zoom In", #selector(zoomIn(_:)), "=")
        add(viewMenu, "Zoom Out", #selector(zoomOut(_:)), "-")
        add(viewMenu, "Fit to Window", #selector(zoomFit(_:)), "0")
        add(viewMenu, "Actual Size", #selector(zoomActual(_:)), "9")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
