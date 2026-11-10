// Helpers for screenshot.sh.
//   screenshot-tools find sheet|preview  waits for an iphone-snap window (the
//                                        macOS prompt or the preview) and prints
//                                        "id x y width height" in points
//   screenshot-tools arrow OUT.png       renders the arrow.right SF Symbol at 2x
//   screenshot-tools backdrop            fills the screen with dark gray until
//                                        killed, so the preview's translucent
//                                        background looks the same every time
import AppKit

let args = CommandLine.arguments

if args.count == 3, args[1] == "arrow" {
    let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(white: 0.56, alpha: 1)]))
    let symbol = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(symbol.size.width * 2),
                               pixelsHigh: Int(symbol.size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = symbol.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

if args.count == 2, args[1] == "backdrop" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let screen = NSScreen.main!
    let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.backgroundColor = NSColor(white: 0.12, alpha: 1)
    window.level = .floating
    window.orderFrontRegardless()
    app.run()
}
guard args.count == 3, args[1] == "find", ["sheet", "preview"].contains(args[2]) else {
    FileHandle.standardError.write(Data("usage: screenshot-tools find sheet|preview | arrow OUT.png | backdrop\n".utf8))
    exit(64)
}
let wantPreview = args[2] == "preview"
for _ in 0..<300 {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows where window[kCGWindowOwnerName as String] as? String == "iphone-snap" {
        let isPreview = (window[kCGWindowName as String] as? String ?? "").hasPrefix("iPhone Photo")
        let bounds = window[kCGWindowBounds as String] as! [String: Double]
        // The prompt's window is a sheet; the 1x1 window it hangs from is not.
        if wantPreview ? isPreview : (!isPreview && bounds["Height"]! > 100) {
            print(window[kCGWindowNumber as String]!, Int(bounds["X"]!), Int(bounds["Y"]!),
                  Int(bounds["Width"]!), Int(bounds["Height"]!))
            exit(0)
        }
    }
    usleep(100_000)
}
FileHandle.standardError.write(Data("no \(args[2]) window within 30s\n".utf8))
exit(1)
