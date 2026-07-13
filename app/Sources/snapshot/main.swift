import SwiftUI
import AppKit
import Foundation
import CleanUI

// Off-screen renderer (no window / screen-recording needed).
//   swift run snapshot                        -> every screen to /tmp/cym-<case>.png
//   swift run snapshot all                    -> same
//   swift run snapshot <caseName> [outPath]   -> one screen (e.g. systemJunkResults)
//   swift run snapshot icon [outPath]         -> 1024×1024 app icon artwork

@MainActor
func writePNG(_ nsImage: NSImage, to path: String) {
    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("render failed: PNG encode"); exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(png.count) bytes)")
    } catch {
        print("write failed: \(error)"); exit(1)
    }
}

@MainActor
func render<V: View>(_ view: V, scale: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let nsImage = renderer.nsImage else { print("render failed: nil image"); exit(1) }
    writePNG(nsImage, to: path)
}

/// Render through a real (offscreen) window instead of ImageRenderer, which
/// skips lazy containers (LazyVGrid/LazyVStack in ScrollViews) and platform-
/// backed controls like TextField — the app's actual screens need both.
@MainActor
func renderInWindow<V: View>(_ view: V, size: CGSize, scale: CGFloat, to path: String) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: size)

    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.colorSpace = .sRGB
    window.contentView = hosting

    // Let SwiftUI run its first layout / appear pass so lazy lists materialise.
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    hosting.layoutSubtreeIfNeeded()

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(size.width * scale),
                                     pixelsHigh: Int(size.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        print("render failed: bitmap rep"); exit(1)
    }
    rep.size = size
    hosting.cacheDisplay(in: hosting.bounds, to: rep)

    let image = NSImage(size: size)
    image.addRepresentation(rep)
    writePNG(image, to: path)
}

@MainActor
func renderScreen(_ screen: SnapshotScreen, to path: String? = nil) {
    renderInWindow(screen.view, size: CGSize(width: 1180, height: 780), scale: 2,
                   to: path ?? "/tmp/cym-\(screen.rawValue).png")
}

let args = Array(CommandLine.arguments.dropFirst())

// Initialise AppKit headlessly so SwiftUI has an app context to render against.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

MainActor.assumeIsolated {
    switch args.first {
    case "icon":
        render(IconArtwork(), scale: 1, to: args.count > 1 ? args[1] : "/tmp/cym_icon.png")
    case nil, "all":
        for screen in SnapshotScreen.allCases { renderScreen(screen) }
    case let name?:
        guard let screen = SnapshotScreen(rawValue: name) else {
            let options = SnapshotScreen.allCases.map(\.rawValue).joined(separator: ", ")
            print("unknown screen “\(name)” — expected one of: all, icon, \(options)")
            exit(2)
        }
        renderScreen(screen, to: args.count > 1 ? args[1] : nil)
    }
}
