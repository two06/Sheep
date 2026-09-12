import AppKit
// Renders the eSheep icon embedded in animations.xml into an .iconset directory for iconutil.
// Usage: make-icon <animations.xml> <output.iconset>
let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write(Data("Usage: make-icon <animations.xml> <output.iconset>\n".utf8)); exit(2) }
let doc = try XMLDocument(contentsOf: URL(fileURLWithPath: args[1]), options: [.nodeLoadExternalEntitiesNever])
guard let text = doc.rootElement()?.elements(forName: "header").first?.elements(forName: "icon").first?.stringValue,
      let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
      let icon = NSBitmapImageRep(data: data)?.cgImage else { FileHandle.standardError.write(Data("No decodable <header><icon> in the definition\n".utf8)); exit(1) }
let out = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
func render(_ size: Int) throws -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Integer nearest-neighbour multiples keep the pixel art crisp and leave the usual icon margin.
    // Sizes below one multiple fill the canvas and downsample smoothly.
    let multiple = Int(Double(size) * 0.84) / icon.width
    let side = multiple >= 1 ? icon.width * multiple : size
    context.interpolationQuality = multiple >= 1 ? .none : .high
    context.draw(icon, in: CGRect(x: (size-side)/2, y: (size-side)/2, width: side, height: side))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points*2).write(to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("Wrote \(out.path)")
