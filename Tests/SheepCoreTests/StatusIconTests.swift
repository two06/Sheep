import Testing
import AppKit
@testable import SheepCore
@testable import SheepMac

@Suite struct StatusIconTests {
    @Test func testGlyphIsPunchedTemplateBuiltFromEmbeddedIcon() throws {
        let glyph = try StatusGlyph.bundled()
        #expect(glyph.width == 48)
        #expect(glyph.height == 48)
        let opaque = glyph.alpha.filter { $0 == 255 }.count
        #expect(opaque > 400, "the sheep body should cover a substantial part of the 48 × 48 icon")
        #expect(glyph.alpha.allSatisfy { $0 == 0 || $0 == 255 }, "template glyph is binary: body or hole")
        // Dark outline pixels inside the body become holes: transparent pixels with opaque neighbours left and right.
        var interiorHoles = 0
        for y in 0..<glyph.height { for x in 1..<(glyph.width-1) where glyph.alpha[y*glyph.width+x] == 0 && glyph.alpha[y*glyph.width+x-1] == 255 && glyph.alpha[y*glyph.width+x+1] == 255 { interiorHoles += 1 } }
        #expect(interiorHoles > 20, "eye, horn and leg outlines should be cut out of the silhouette")
        // Corners of the source icon are transparent background and must stay transparent.
        #expect(glyph.alpha[0] == 0)
        #expect(glyph.alpha[glyph.width-1] == 0)
    }
    @Test func testGlyphImageIsMenuBarTemplateAtRequestedPointSize() throws {
        let image = try StatusGlyph.bundled().image(pointSize: 18)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        // Rendering must produce visible pixels, not an empty image.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 36*4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        var covered = 0
        for y in 0..<36 { for x in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { covered += 1 } }
        #expect(covered > 300)
    }
    @Test func testStatusIconStylePersistsAndDefaultsToEmoji() throws {
        let domain = "SheepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = FlockPreferences(defaults: defaults)
        #expect(settings.statusIconStyle == .emoji)
        settings.save(statusIconStyle: .monochrome)
        #expect(FlockPreferences(defaults: defaults).statusIconStyle == .monochrome)
        defaults.set("not-a-style", forKey: "statusIconStyle")
        #expect(FlockPreferences(defaults: defaults).statusIconStyle == .emoji, "unknown stored values fall back to the emoji")
    }
    @Test func testStatusIconStyleTitlesAreDistinct() {
        #expect(StatusIconStyle.allCases.count == 2)
        #expect(Set(StatusIconStyle.allCases.map(\.title)).count == 2)
        #expect(StatusIconStyle.emoji.title.contains("🐑"))
    }
}
