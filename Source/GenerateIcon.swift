import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: GenerateIcon <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let outerRect = NSRect(x: 82, y: 82, width: 860, height: 860)
let outer = NSBezierPath(roundedRect: outerRect, xRadius: 205, yRadius: 205)
let gradient = NSGradient(colors: [
    NSColor(red: 0.20, green: 0.57, blue: 1.00, alpha: 1),
    NSColor(red: 0.17, green: 0.31, blue: 0.84, alpha: 1)
])!
gradient.draw(in: outer, angle: -52)

let highlight = NSBezierPath(roundedRect: NSRect(x: 128, y: 518, width: 768, height: 330), xRadius: 140, yRadius: 140)
NSColor.white.withAlphaComponent(0.09).setFill()
highlight.fill()

let terminalRect = NSRect(x: 230, y: 270, width: 564, height: 484)
let terminal = NSBezierPath(roundedRect: terminalRect, xRadius: 72, yRadius: 72)
NSColor(red: 0.045, green: 0.070, blue: 0.13, alpha: 0.90).setFill()
terminal.fill()

let topBar = NSBezierPath(roundedRect: NSRect(x: 230, y: 650, width: 564, height: 104), xRadius: 72, yRadius: 72)
NSColor.white.withAlphaComponent(0.10).setFill()
topBar.fill()
NSRect(x: 230, y: 650, width: 564, height: 52).fill()

for (index, color) in [
    NSColor.systemRed,
    NSColor.systemYellow,
    NSColor.systemGreen
].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 282 + CGFloat(index) * 58, y: 682, width: 28, height: 28)).fill()
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 185, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
NSString(string: ">_").draw(in: NSRect(x: 278, y: 360, width: 470, height: 220), withAttributes: attributes)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)

