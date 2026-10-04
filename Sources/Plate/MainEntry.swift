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
            print("Identity, grade, crop, straighten, orientation, marks, undo, PNG round-trip.")
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
    \(AppInfo.name) \(AppInfo.version) — image editor

    Usage:
      Plate                              Launch the app
      Plate --self-test                  Engine checks
      Plate INPUT [options]

    Options:
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
      --jpeg                             Write JPEG instead of PNG
      --quality 0.05..1                  JPEG quality. Default 0.92
      -o, --out PATH                     Default: INPUT-edited.png

    The original file is never overwritten.

    Examples:
      Plate photo.jpg --exposure 0.3 --look warm -o print.jpg --jpeg
      Plate photo.png --rotate 90 --crop 0.1,0.1,0.8,0.8
    """
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let model = AppModel()
    private var pendingURLs: [URL] = []
    /// Set once a close or quit has already asked, so the following quit does not ask again.
    private var discardConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMainMenu()

        let hosting = NSHostingView(rootView: ContentView(model: model))
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
            model.load(url: pendingURLs[0])
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
        } else if let url = urls.first {
            model.load(url: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if window == nil {
            pendingURLs = [url]
        } else {
            model.load(url: url)
        }
        return true
    }

    @objc private func openImage(_ sender: Any?) { model.openPanel() }
    @objc private func saveImage(_ sender: Any?) { model.savePanel() }
    @objc private func copyImage(_ sender: Any?) { model.copyImage() }
    @objc private func pasteImage(_ sender: Any?) { model.paste() }
    @objc private func undoEdit(_ sender: Any?) { model.undo() }
    @objc private func redoEdit(_ sender: Any?) { model.redo() }
    @objc private func resetEdit(_ sender: Any?) { model.resetAll() }
    @objc private func loadSample(_ sender: Any?) { model.loadSample() }
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
    @objc private func deleteAnnotation(_ sender: Any?) { model.deleteSelectedAnnotation() }
    @objc private func duplicateAnnotation(_ sender: Any?) { model.duplicateSelectedAnnotation() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(deleteAnnotation(_:))
            || menuItem.action == #selector(duplicateAnnotation(_:)) {
            return model.selectedAnnotationID != nil
        }
        return true
    }

    @objc private func showAbout(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: AppInfo.name,
            .version: AppInfo.version,
            .applicationVersion: "Version \(AppInfo.version) (\(AppInfo.build))",
            .credits: NSAttributedString(
                string: """
                A darkroom for one photo. Exposure, color, crop, \
                looks, and marks. Closing asks before discarding \
                edits. Save writes a new 8-bit sRGB file and leaves \
                the original alone.
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
        add(fileMenu, "Open…", #selector(openImage(_:)), "o")
        add(fileMenu, "Save As…", #selector(saveImage(_:)), "s")
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
        add(editMenu, "Copy Image", #selector(copyImage(_:)), "c")
        add(editMenu, "Paste", #selector(pasteImage(_:)), "v")
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
        let deleteMark = add(imageMenu, "Delete Annotation", #selector(deleteAnnotation(_:)), "\u{8}")
        deleteMark.keyEquivalentModifierMask = [.command]
        add(imageMenu, "Duplicate Annotation", #selector(duplicateAnnotation(_:)), "d")

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
