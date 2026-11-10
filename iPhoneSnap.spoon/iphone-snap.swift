// Takes a photo with the iPhone through Continuity Camera and shows it in a
// preview window, Quick Look style: icon buttons for the actions plus one
// labelled button, run by Return, for the default action.
//
//   iphone-snap [--save-dir DIR] [--default ACTION] [--mock [IMAGE]]
//
// ACTION is delete, edit, copy, save or saveCopy (default save). Save writes
// into DIR (default ~/Downloads), Edit writes a temporary copy for
// Hammerspoon's editor, Copy puts the photo on the clipboard. --mock skips the
// iPhone and previews IMAGE, or a generated placeholder, for trying designs.
//
// AppKit fills a menu item tagged NSMenuItem.importFromDeviceIdentifier with
// the same "Import from iPhone" submenu Finder shows, but only while a menu is
// open. So this opens that menu, fires "Take Photo" as soon as it appears and
// closes the menu. The photo arrives through NSServicesMenuRequestor on a 1x1
// window in the middle of the screen, which is where macOS anchors its prompt.
//
// Prints the chosen action and a path, tab-separated: "save <saved file>",
// "saveCopy <saved file>", "edit <temporary copy>", "copy", "delete".
// Exit codes: 0 action printed, 2 no device offered, 3 cancelled (on the
// iPhone or the Mac) or no photo within two minutes, 4 photo unreadable,
// 64 bad arguments.
import AppKit

// The device submenu lists Take Photo, Scan Documents, Add Sketch; all share
// this action, Take Photo first.
let importAction = NSSelectorFromString("importFromDevice:")

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

func finish(_ action: Action, _ path: String = "") -> Never {
    print("\(action.rawValue)\t\(path)")
    exit(0)
}

enum Action: String, CaseIterable {
    case delete, edit, copy, save, saveCopy

    var title: String {
        switch self {
        case .delete: "Delete"
        case .edit: "Edit"
        case .copy: "Copy"
        case .save: "Save"
        case .saveCopy: "Save & Copy"
        }
    }

    var symbol: String {
        switch self {
        case .delete: "trash"
        case .edit: "pencil.tip.crop.circle"
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .saveCopy: "square.and.arrow.down.on.square"
        }
    }

    /// Shortcut that works whether or not the action is the default.
    var key: (character: String, modifiers: NSEvent.ModifierFlags, label: String) {
        switch self {
        case .delete: ("\u{1b}", [], "Esc")
        case .edit: ("e", .command, "⌘E")
        case .copy: ("c", .command, "⌘C")
        case .save: ("s", .command, "⌘S")
        case .saveCopy: ("s", [.command, .shift], "⇧⌘S")
        }
    }
}

struct Options {
    var saveDir = URL(fileURLWithPath: NSString(string: "~/Downloads").expandingTildeInPath, isDirectory: true)
    var primary = Action.save
    /// Set for --mock; empty means the generated placeholder.
    var mock: String?

    init(_ arguments: [String]) {
        var args = arguments.dropFirst()
        while let arg = args.popFirst() {
            switch arg {
            case "--save-dir":
                guard let dir = args.popFirst() else { fail("--save-dir needs a folder", 64) }
                saveDir = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath, isDirectory: true)
            case "--default":
                guard let name = args.popFirst(), let action = Action(rawValue: name) else {
                    fail("--default needs one of: \(Action.allCases.map(\.rawValue).joined(separator: ", "))", 64)
                }
                primary = action
            case "--mock":
                if let image = args.first, !image.hasPrefix("--") {
                    mock = NSString(string: image).expandingTildeInPath
                    args.removeFirst()
                } else {
                    mock = ""
                }
            default:
                fail("unknown argument \(arg)", 64)
            }
        }
    }
}

let options = Options(CommandLine.arguments)

func jpegData(_ image: NSImage) -> Data? {
    image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [:]) }
}

/// `name`, or `name 2`, `name 3`… if a file by that name is already in `dir`.
func freeURL(in dir: URL, name: String) -> URL {
    var url = dir.appendingPathComponent("\(name).jpg")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dir.appendingPathComponent("\(name) \(n).jpg")
        n += 1
    }
    return url
}

func mockPhoto(_ path: String) -> (NSImage, Data) {
    if !path.isEmpty {
        guard let image = NSImage(contentsOfFile: path),
              let jpeg = ["jpg", "jpeg"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
                ? FileManager.default.contents(atPath: path) : jpegData(image)
        else { fail("could not read \(path)", 4) }
        return (image, jpeg)
    }
    // Portrait 3:4, the shape of an iPhone photo.
    let image = NSImage(size: NSSize(width: 1440, height: 1920), flipped: false) { rect in
        NSGradient(colors: [.systemIndigo, .systemTeal])?.draw(in: rect, angle: 60)
        let text = "Mock photo" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 160), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        return true
    }
    guard let jpeg = jpegData(image) else { fail("could not draw the mock photo", 4) }
    return (image, jpeg)
}

final class Receiver: NSView, NSServicesMenuRequestor {
    var onPhoto: ((NSImage, Data) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == nil, let returnType, NSImage.imageTypes.contains(returnType.rawValue) { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pasteboard: NSPasteboard) -> Bool {
        guard let image = NSImage(pasteboard: pasteboard),
              let jpeg = pasteboard.data(forType: .init("public.jpeg")) ?? jpegData(image)
        else { fail("could not read the photo", 4) }
        DispatchQueue.main.async { self.onPhoto?(image, jpeg) }
        return true
    }
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Runs every action's shortcut, whether or not it has a button, and Return
/// for the default action.
final class KeyPanel: NSPanel {
    var onAction: ((Action) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            onAction?(options.primary)
            return true
        }
        let character = event.keyCode == 53 ? "\u{1b}" : (event.charactersIgnoringModifiers ?? "").lowercased()
        if let action = Action.allCases.first(where: { $0.key.character == character && $0.key.modifiers == modifiers }) {
            onAction?(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Dragging the photo moves the window, like the rest of the background.
final class DragImageView: NSImageView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class Preview: NSObject, NSWindowDelegate {
    let image: NSImage
    let jpeg: Data
    let name: String
    let panel: KeyPanel

    init(image: NSImage, jpeg: Data, on screen: NSScreen) {
        self.image = image
        self.jpeg = jpeg
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        name = "iPhone Photo \(stamp.string(from: Date()))"

        let limit = min(520, screen.visibleFrame.height - 180)
        let scale = min(limit / image.size.width, limit / image.size.height, 1)
        let shown = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        panel = KeyPanel(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        super.init()
        panel.title = name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        // Panels hide whenever their app is not frontmost by default.
        panel.hidesOnDeactivate = false
        // Above other apps' floating windows, on every Space and over
        // full-screen apps, until a button decides.
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.onAction = { [unowned self] in perform($0) }
        // Delete (Esc) stands in for the close button.
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }

        let imageView = DragImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: shown.width).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: shown.height).isActive = true

        // Quick Look style: icons on the left; on the right Copy as a split
        // button whose menu holds Save & Copy. Whichever of the pair is the
        // default sits on the button and the other in the menu. Return runs
        // the default; a default icon button is also drawn blue.
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 6
        for action in [Action.delete, .edit, .save] {
            bar.addView(iconButton(action), in: .leading)
        }
        bar.addView(splitButton(), in: .trailing)

        let stack = NSStackView(views: [bar, imageView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        bar.widthAnchor.constraint(equalTo: imageView.widthAnchor).isActive = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.layoutIfNeeded()
        panel.setContentSize(background.fittingSize)

        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
    }

    private func iconButton(_ action: Action) -> NSButton {
        let button: NSButton
        if let symbol = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.title) {
            button = NSButton(image: symbol, target: self, action: #selector(clicked))
        } else {
            button = NSButton(title: action.title, target: self, action: #selector(clicked))
        }
        button.bezelStyle = .push
        button.controlSize = .large
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalTo: button.heightAnchor, multiplier: 1.25).isActive = true
        button.tag = Action.allCases.firstIndex(of: action)!
        markDefault(button, action)
        return button
    }

    /// Copy, or Save & Copy when that is the default, with the other in the
    /// split button's menu.
    private func splitButton() -> NSView {
        let main = options.primary == .saveCopy ? Action.saveCopy : .copy
        let other = main == .copy ? Action.saveCopy : .copy

        let item = NSMenuItem(title: other.title, action: #selector(clicked), keyEquivalent: other.key.character)
        item.keyEquivalentModifierMask = other.key.modifiers
        item.image = NSImage(systemSymbolName: other.symbol, accessibilityDescription: nil)
        item.target = self
        item.tag = Action.allCases.firstIndex(of: other)!
        let menu = NSMenu()
        menu.addItem(item)

        let button = NSComboButton(title: main.title,
                                   image: NSImage(systemSymbolName: main.symbol, accessibilityDescription: nil)!,
                                   menu: menu, target: self, action: #selector(clicked))
        button.style = .split
        button.controlSize = .large
        button.tag = Action.allCases.firstIndex(of: main)!
        button.toolTip = main == options.primary
            ? "\(main.title)  ↩ or \(main.key.label)" : "\(main.title)  \(main.key.label)"
        return button
    }

    /// Return itself goes through KeyPanel; the key equivalent here only turns
    /// the default icon button blue.
    private func markDefault(_ button: NSButton, _ action: Action) {
        if action == options.primary {
            button.keyEquivalent = "\r"
            button.toolTip = "\(action.title)  ↩ or \(action.key.label)"
        } else {
            button.toolTip = "\(action.title)  \(action.key.label)"
        }
    }

    @objc private func clicked(_ sender: Any) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as! NSControl).tag
        perform(Action.allCases[tag])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Keeps the focus ring off the first button, so Space does nothing.
        panel.makeFirstResponder(nil)
    }

    private func write(to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .withoutOverwriting)
            return true
        } catch {
            NSAlert(error: error).beginSheetModal(for: panel)
            return false
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(jpeg, forType: .init("public.jpeg"))
    }

    func perform(_ action: Action) {
        switch action {
        case .delete:
            finish(.delete)
        case .copy:
            copyToClipboard()
            finish(.copy)
        case .edit:
            let url = freeURL(in: FileManager.default.temporaryDirectory, name: name)
            if write(to: url) { finish(.edit, url.path) }
        case .save, .saveCopy:
            let url = freeURL(in: options.saveDir, name: name)
            guard write(to: url) else { return }
            if action == .saveCopy { copyToClipboard() }
            finish(action, url.path)
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(.delete)
    }
}

final class Snap: NSObject, NSApplicationDelegate {
    let menu = NSMenu()
    var window: NSWindow?
    var preview: Preview?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main!
        if let mock = options.mock {
            let (image, jpeg) = mockPhoto(mock)
            showPreview(image, jpeg, on: screen)
            return
        }

        // macOS hangs its prompt, about 240pt tall, from this window's top
        // edge; this centres the prompt on the screen.
        let visible = screen.visibleFrame
        let receiver = Receiver()
        let window = KeyWindow(contentRect: NSRect(x: visible.midX, y: visible.midY + 120, width: 1, height: 1),
                               styleMask: .borderless, backing: .buffered, defer: false)
        self.window = window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.contentView = receiver
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(receiver)
        NSApp.activate(ignoringOtherApps: true)
        receiver.onPhoto = { image, jpeg in
            self.showPreview(image, jpeg, on: screen)
        }

        // The system only wires the item up once it sits in the main menu.
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.identifier = NSMenuItem.importFromDeviceIdentifier
        menu.addItem(item)
        let top = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        top.submenu = menu
        let main = NSMenu()
        main.addItem(top)
        NSApp.mainMenu = main

        // Runs while popUp tracks the menu.
        let opened = Date()
        let poll = Timer(timeInterval: 0.02, repeats: true) { timer in
            if let submenu = item.submenu,
               let index = submenu.items.firstIndex(where: { $0.action == importAction && $0.isEnabled }) {
                timer.invalidate()
                self.menu.cancelTrackingWithoutAnimation()
                DispatchQueue.main.async { submenu.performActionForItem(at: index) }
            } else if Date().timeIntervalSince(opened) > 3 {
                timer.invalidate()
                self.menu.cancelTrackingWithoutAnimation()
                DispatchQueue.main.async { fail("no iPhone offered Take Photo", 2) }
            }
        }
        RunLoop.main.add(poll, forMode: .eventTracking)
        DispatchQueue.main.async {
            self.menu.popUp(positioning: nil, at: cursor, in: nil)
        }

        // macOS shows its "Take Photo" prompt as a sheet on the window; it ends
        // on cancel from either side and around a successful import, so only
        // give up if no photo follows shortly.
        NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.giveUpWithoutPhoto() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { self.giveUpWithoutPhoto() }
    }

    func showPreview(_ image: NSImage, _ jpeg: Data, on screen: NSScreen) {
        // Hammerspoon stops a capture still waiting when the hotkey is pressed
        // again; a photo on screen stays until a button decides.
        signal(SIGTERM, SIG_IGN)
        window?.orderOut(nil)
        preview = Preview(image: image, jpeg: jpeg, on: screen)
        preview?.show()
    }

    func giveUpWithoutPhoto() {
        if preview == nil { exit(3) }
    }
}

let app = NSApplication.shared
let snap = Snap()
app.delegate = snap
app.setActivationPolicy(.accessory)
app.run()
