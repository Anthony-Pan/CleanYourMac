// Renders installer artwork offscreen (no window server needed).
//
// Usage:
//   swift render_assets.swift dmg <out.png>
//   swift render_assets.swift pkg <light|dark> <out.png> <icon_1024.png>
//
// Palette is the ONYX brand: near-black ink + champagne accent.

import AppKit

let ink = NSColor(srgbRed: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0B / 255.0, alpha: 1)
let inkRaised = NSColor(srgbRed: 0x16 / 255.0, green: 0x16 / 255.0, blue: 0x18 / 255.0, alpha: 1)
let champagne = NSColor(srgbRed: 0xC9 / 255.0, green: 0xB8 / 255.0, blue: 0x96 / 255.0, alpha: 1)
let mist = NSColor(srgbRed: 0x9A / 255.0, green: 0x9A / 255.0, blue: 0xA0 / 255.0, alpha: 1)
let faint = NSColor(srgbRed: 0x6A / 255.0, green: 0x6A / 255.0, blue: 0x70 / 255.0, alpha: 1)

/// Bitmap whose pixel grid is `scale`x the point size, with DPI metadata set so
/// Finder / Installer draw it at the intended point size on Retina displays.
func makeBitmap(width: Int, height: Int, scale: Int) -> NSBitmapImageRep {
    guard let base = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("could not allocate bitmap")
    }
    // Tag as sRGB so the brand colors survive without color management.
    guard let rep = base.retagging(with: .sRGB) else {
        fatalError("could not retag bitmap as sRGB")
    }
    // INVARIANT: size must be set before NSGraphicsContext(bitmapImageRep:) is
    // created — the context derives its points-to-pixels scale from it.
    rep.size = NSSize(width: width, height: height)
    return rep
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create graphics context")
    }
    NSGraphicsContext.current = ctx
    body()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fatalError("could not write \(path): \(error)")
    }
}

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                tracking: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking,
    ])
}

func drawCentered(_ text: NSAttributedString, centerX: CGFloat, baselineY: CGFloat) {
    let size = text.size()
    text.draw(at: NSPoint(x: centerX - size.width / 2, y: baselineY))
}

// MARK: - DMG background (660x400 pt, drawn at 2x)

func renderDMGBackground(to path: String) {
    // The context's user space is in points; the 2x pixel grid is applied
    // automatically via the rep's DPI.
    //
    // The canvas is 2x the window's 660x400 content so that dragging the
    // window larger keeps showing ink instead of Finder's default white —
    // Finder anchors the background picture at the top-left, so the design
    // lives in the top-left 660x400 region.
    let canvasW: CGFloat = 1320
    let canvasH: CGFloat = 800
    let w: CGFloat = 660
    let yOff: CGFloat = canvasH - 400  // AppKit bottom-left origin → design strip is on top
    let rep = makeBitmap(width: 1320, height: 800, scale: 2)

    draw(into: rep) {
        NSGradient(starting: inkRaised, ending: ink)?
            .draw(in: NSRect(x: 0, y: 0, width: canvasW, height: canvasH), angle: -90)

        // Hairline accent along the top edge.
        champagne.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: canvasH - 1, width: canvasW, height: 1).fill()

        drawCentered(attributed("CleanYourMac", size: 26, weight: .semibold,
                                color: champagne, tracking: 0.5),
                     centerX: w / 2, baselineY: yOff + 338)
        drawCentered(attributed("Drag the app into Applications to install", size: 13,
                                weight: .regular, color: mist),
                     centerX: w / 2, baselineY: yOff + 312)
        drawCentered(attributed("将 CleanYourMac 拖入 Applications 完成安装", size: 12,
                                weight: .regular, color: mist),
                     centerX: w / 2, baselineY: yOff + 292)

        // Arrow between the two icon slots (icons sit at Finder y=205, i.e. AppKit y=195).
        let arrowY: CGFloat = yOff + 195
        let start = NSPoint(x: 252, y: arrowY)
        let end = NSPoint(x: 404, y: arrowY)
        let line = NSBezierPath()
        line.lineWidth = 3
        line.lineCapStyle = .round
        line.move(to: start)
        line.line(to: end)
        champagne.setStroke()
        line.stroke()

        let head = NSBezierPath()
        head.lineWidth = 3
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: NSPoint(x: end.x - 14, y: arrowY + 10))
        head.line(to: end)
        head.line(to: NSPoint(x: end.x - 14, y: arrowY - 10))
        head.stroke()

        drawCentered(attributed("Open source · MIT License · Nothing is removed without your review",
                                size: 10, weight: .regular, color: faint),
                     centerX: w / 2, baselineY: yOff + 20)
    }

    writePNG(rep, to: path)
}

// MARK: - Installer pane background (620x418 pt, drawn at 2x)

func renderPKGBackground(dark: Bool, iconPath: String, to path: String) {
    let rep = makeBitmap(width: 620, height: 418, scale: 2)
    guard let icon = NSImage(contentsOfFile: iconPath) else {
        fatalError("could not load icon at \(iconPath)")
    }

    draw(into: rep) {
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 620, height: 418).fill(using: .copy)

        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(x: 28, y: 26, width: 84, height: 84),
                  from: .zero, operation: .sourceOver, fraction: 1.0)

        let title = dark ? NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1) : ink
        attributed("CleanYourMac", size: 17, weight: .semibold, color: title)
            .draw(at: NSPoint(x: 122, y: 64))
        attributed("by ONYX · open source", size: 11, weight: .regular,
                   color: dark ? mist : faint)
            .draw(at: NSPoint(x: 122, y: 46))
    }

    writePNG(rep, to: path)
}

// MARK: - App icon master (mask full-bleed art into the macOS icon shape)

/// macOS app icons are an 824x824 rounded rect centered in a transparent 1024
/// canvas (radius ≈ 22.5% of the grid), with a soft drop shadow. Full-bleed
/// square art rendered as-is looks like a sticker in the Dock.
func renderAppIcon(from sourcePath: String, to path: String) {
    guard let source = NSImage(contentsOfFile: sourcePath) else {
        fatalError("could not load source icon at \(sourcePath)")
    }
    let canvas: CGFloat = 1024
    let grid: CGFloat = 824
    let inset = (canvas - grid) / 2
    let radius = grid * 0.225
    let rep = makeBitmap(width: 1024, height: 1024, scale: 1)

    draw(into: rep) {
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high

        let gridRect = NSRect(x: inset, y: inset, width: grid, height: grid)
        let squircle = NSBezierPath(roundedRect: gridRect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        ink.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        source.draw(in: gridRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    writePNG(rep, to: path)
}

// MARK: - Entry point

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "dmg" where args.count == 3:
    renderDMGBackground(to: args[2])
case "pkg" where args.count == 5 && (args[2] == "light" || args[2] == "dark"):
    renderPKGBackground(dark: args[2] == "dark", iconPath: args[4], to: args[3])
case "appicon" where args.count == 4:
    renderAppIcon(from: args[2], to: args[3])
default:
    FileHandle.standardError.write(Data("""
    usage:
      swift render_assets.swift dmg <out.png>
      swift render_assets.swift pkg <light|dark> <out.png> <icon_1024.png>
      swift render_assets.swift appicon <source_1024.png> <out.png>

    """.utf8))
    exit(64)
}
