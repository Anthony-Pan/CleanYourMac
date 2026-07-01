import SwiftUI
import AppKit
import Foundation
import CleanUI

// Off-screen renderer (no window / screen-recording needed).
//   swift run snapshot [outPath]          -> design preview of the Smart Scan screen
//   swift run snapshot icon [outPath]     -> 1024×1024 app icon artwork

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

let args = Array(CommandLine.arguments.dropFirst())

// Initialise AppKit headlessly so SwiftUI has an app context to render against.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

if args.first == "icon" {
    let path = args.count > 1 ? args[1] : "/tmp/cym_icon.png"
    MainActor.assumeIsolated { render(IconArtwork(), scale: 1, to: path) }
} else {
    let path = args.first ?? "/tmp/cym_snapshot.png"
    MainActor.assumeIsolated { render(SnapshotPreview(), scale: 2, to: path) }
}
