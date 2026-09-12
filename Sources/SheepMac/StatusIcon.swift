import AppKit
import SheepCore

/// Status item appearance: the emoji title, or a monochrome template glyph that macOS tints like system icons.
public enum StatusIconStyle: String, CaseIterable {
    case emoji, monochrome
    public var title: String {
        switch self { case .emoji: return "Emoji 🐑"; case .monochrome: return "Monochrome" }
    }
}

/// Binary alpha mask of the classic eSheep icon embedded in the pinned definition. Dark outline pixels are
/// punched out so the eye, horn and legs stay legible once macOS renders the mask as a template image.
public struct StatusGlyph {
    public let width: Int, height: Int
    public let alpha: [UInt8]
    public static func bundled() throws -> StatusGlyph { try StatusGlyph(definitionURL: SheepResources.definitionURL) }
    public init(definitionURL: URL) throws {
        let doc = try XMLDocument(contentsOf: definitionURL, options: [.nodeLoadExternalEntitiesNever])
        guard let text = doc.rootElement()?.elements(forName: "header").first?.elements(forName: "icon").first?.stringValue,
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { throw DefinitionError.invalid("Missing header icon") }
        try self.init(iconData: data)
    }
    public init(iconData: Data) throws {
        guard let cg = NSBitmapImageRep(data: iconData)?.cgImage, cg.width > 0, cg.height > 0,
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { throw DefinitionError.invalid("Undecodable icon") }
        width = cg.width; height = cg.height
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width*height*4)
        var mask = [UInt8](repeating: 0, count: width*height)
        for i in 0..<(width*height) {
            let a = Double(pixels[i*4+3]); guard a > 16 else { continue }
            let luminance = (0.299*Double(pixels[i*4]) + 0.587*Double(pixels[i*4+1]) + 0.114*Double(pixels[i*4+2])) / a
            mask[i] = luminance < 0.30 ? 0 : 255
        }
        alpha = mask
    }
    /// A template image; only the alpha channel matters, AppKit supplies the colour.
    public func image(pointSize: CGFloat) -> NSImage {
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        for i in 0..<(width*height) where alpha[i] == 255 { bytes[i*4+3] = 255 }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high; context.draw(cg, in: rect); return true
        }
        image.isTemplate = true
        return image
    }
}
