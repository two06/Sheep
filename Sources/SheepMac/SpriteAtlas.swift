import AppKit
import Foundation
import SheepCore
public final class SpriteAtlas {
    public let frames: [CGImage]
    public let masks: [[UInt8]]
    public let width: Int
    public let height: Int
    public init() throws {
        let xml = try XMLDocument(contentsOf: SheepResources.definitionURL)
        let root = xml.rootElement()!
        let image = root.elements(forName: "image")[0]
        let data = Data(base64Encoded: image.elements(forName: "png")[0].stringValue!, options: .ignoreUnknownCharacters)!
        guard let rep = NSBitmapImageRep(data: data) else { throw NSError(domain: "SheepAtlas", code: 1) }
        let cols = Int(image.elements(forName: "tilesx")[0].stringValue!)!
        let rows = Int(image.elements(forName: "tilesy")[0].stringValue!)!
        width = rep.pixelsWide / cols; height = rep.pixelsHigh / rows
        var images: [CGImage] = []; var alpha: [[UInt8]] = []
        for index in 0..<(cols * rows) {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            var mask = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height { for x in 0..<width {
                let c = rep.colorAt(x: (index % cols) * width + x, y: (index / cols) * height + y)!.usingColorSpace(.deviceRGB)!
                let magenta = c.redComponent > 0.98 && c.blueComponent > 0.98 && c.greenComponent < 0.02
                let a = magenta ? 0 : UInt8((c.alphaComponent * 255).rounded())
                let i = (y * width + x) * 4
                bytes[i] = UInt8((c.redComponent * Double(a)).rounded()); bytes[i+1] = UInt8((c.greenComponent * Double(a)).rounded())
                bytes[i+2] = UInt8((c.blueComponent * Double(a)).rounded()); bytes[i+3] = a; mask[y * width + x] = a
            } }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            images.append(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
            alpha.append(mask)
        }
        frames = images; masks = alpha
    }
    public func isOpaque(frame: Int, x: Int, y: Int) -> Bool {
        frames.indices.contains(frame) && x >= 0 && y >= 0 && x < width && y < height && masks[frame][y * width + x] > 16
    }
}
