import AppKit
import SheepMac
final class FixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class Probe: NSObject, NSApplicationDelegate {
    var fixture: FixtureWindow?
    var panel: SpritePanel!; var timer: Timer!; var status: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if CommandLine.arguments.contains("--fixture") {
                let screen = NSScreen.main!.visibleFrame
                let window = FixtureWindow(contentRect:NSRect(x:screen.midX-220,y:screen.midY-80,width:440,height:160),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed = false; window.title = "Sheep window-support check (closes automatically)"
                window.backgroundColor = .systemBlue; window.orderFrontRegardless(); fixture = window
                try JSONSerialization.data(withJSONObject:["windowID":window.windowNumber]).write(to:URL(fileURLWithPath:"/tmp/sheep-fixture.json"))
                DispatchQueue.main.asyncAfter(deadline:.now()+15) { window.setFrameOrigin(NSPoint(x:window.frame.minX+100,y:window.frame.minY+60)) }
                DispatchQueue.main.asyncAfter(deadline:.now()+25) { window.close() }
                DispatchQueue.main.asyncAfter(deadline:.now()+35) { NSApp.terminate(nil) }
                return
            }
            let atlas = try SpriteAtlas(); panel = SpritePanel(atlas: atlas)
            if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)) }
            panel.orderFrontRegardless()
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); status.button?.title = "🐑 Probe"
            let menu = NSMenu(); let quit = menu.addItem(withTitle: "Quit Sheep Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); quit.target = NSApp; status.menu = menu
            timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.panel.updateMouseAcceptance() }; RunLoop.main.add(timer, forMode: .common)
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? Int32) != getpid() }
            let report: [String: Any] = ["visibleOrdinaryWindows": windows.count, "windowsWithBounds": windows.filter { $0[kCGWindowBounds as String] != nil }.count, "frameWidth": atlas.width, "frameHeight": atlas.height, "frames": atlas.frames.count, "canBecomeKey": panel.canBecomeKey, "canBecomeMain": panel.canBecomeMain, "collectionBehavior": panel.collectionBehavior.rawValue, "displays": NSScreen.screens.count, "screenRecordingAlreadyGranted": CGPreflightScreenCaptureAccess()]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]); try data.write(to: URL(fileURLWithPath: "/tmp/sheep-probe.json"))
        } catch { NSLog("Sheep probe: %@", String(describing: error)); NSApp.terminate(nil) }
    }
}
if CommandLine.arguments.contains("--export-atlas") {
    let atlas = try SpriteAtlas(), width = 16*80, height = 11*80
    let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray:0.85,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height)); context.interpolationQuality = .none
    for (i,frame) in atlas.frames.enumerated() {
        context.draw(frame,in:CGRect(x:(i%16)*80,y:height-(i/16+1)*80,width:80,height:80))
    }
    let bitmap = NSBitmapImageRep(cgImage:context.makeImage()!)
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/sheep-atlas.png"))
    print("/tmp/sheep-atlas.png"); exit(0)
}
if CommandLine.arguments.contains("--panel-bounds-check") {
    _ = NSApplication.shared
    let panel = SpritePanel(atlas:try SpriteAtlas()), top = NSScreen.screens.first!.frame.maxY
    for y in [-150.0,-6.0,33.0,100.0] {
        let desired = NSRect(x:200,y:top-y-40,width:40,height:40)
        panel.setFrame(desired,display:false); panel.orderFrontRegardless()
        print("desired global y=\(y), actual global y=\(top-panel.frame.maxY)")
    }
    panel.close(); exit(0)
}
if CommandLine.arguments.contains("--list-windows") {
    let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
    let rows = raw.map { info in
        Dictionary(uniqueKeysWithValues: [kCGWindowOwnerName,kCGWindowOwnerPID,kCGWindowNumber,kCGWindowLayer,kCGWindowBounds,kCGWindowAlpha].compactMap { key -> (String,Any)? in
            guard let value = info[key as String] else { return nil }; return (key as String,value)
        })
    }
    if let data = try? JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]), let text = String(data:data,encoding:.utf8) { print(text) }
    exit(0)
}
let app = NSApplication.shared; let delegate = Probe(); app.setActivationPolicy(.accessory); app.delegate = delegate; app.run()
