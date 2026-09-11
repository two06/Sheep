import AppKit
import SheepCore
import SheepMac
if CommandLine.arguments.contains("--self-check") {
    do {
        let definition = try Definition.bundled(), atlas = try SpriteAtlas()
        print("Sheep resources OK: \(definition.animations.count) animations, \(atlas.frames.count) frames, \(atlas.width) × \(atlas.height) points")
        print("Resource: \(SheepResources.definitionURL.path)")
        exit(0)
    } catch { fputs("Sheep self-check failed: \(error)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
