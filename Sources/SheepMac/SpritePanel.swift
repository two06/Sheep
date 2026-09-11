import AppKit
public final class SpritePanel: NSPanel {
    // AppKit otherwise snaps partially offscreen panels below the menu bar. That
    // silently separates rendered position from the simulation's supporting ledge.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
    public let sprite: SpriteView
    public init(atlas: SpriteAtlas) {
        sprite = SpriteView(atlas: atlas)
        super.init(contentRect: NSRect(x: 200, y: 200, width: atlas.width, height: atlas.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone, .fullScreenDisallowsTiling]
        animationBehavior = .none; isMovable = false; becomesKeyOnlyIfNeeded = true
        contentView = sprite; ignoresMouseEvents = true
    }
    public func updateMouseAcceptance(enabled: Bool = true) {
        ignoresMouseEvents = !enabled || (!sprite.dragging && !sprite.opaque(at: convertPoint(fromScreen: NSEvent.mouseLocation)))
    }
}
public final class SpriteView: NSView {
    let atlas: SpriteAtlas
    public var frameIndex = 2 { didSet { needsDisplay = true } }
    public var mirrored = false { didSet { needsDisplay = true } }
    public var opacity: Double = 1 { didSet { needsDisplay = true } }
    public private(set) var dragging = false
    public var onDrag: ((NSPoint, Bool) -> Void)?
    public var onRelease: ((NSPoint) -> Void)?
    public var onRemove: (() -> Void)?
    public var onAdd: (() -> Void)?
    private var lastPoint = NSPoint.zero
    private var lastTime: TimeInterval = 0
    private var velocity = NSPoint.zero
    public init(atlas: SpriteAtlas) { self.atlas = atlas; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override var acceptsFirstResponder: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public func opaque(at point: NSPoint) -> Bool {
        guard bounds.width > 0, bounds.height > 0, bounds.contains(point), opacity > 0.05 else { return false }
        var x = Int(point.x / bounds.width * Double(atlas.width))
        let y = atlas.height - 1 - Int(point.y / bounds.height * Double(atlas.height))
        if mirrored { x = atlas.width - 1 - x }
        return atlas.isOpaque(frame: frameIndex, x: x, y: y)
    }
    public override func draw(_ dirtyRect: NSRect) {
        guard atlas.frames.indices.contains(frameIndex), let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.interpolationQuality = .none; c.setAlpha(opacity)
        if mirrored { c.translateBy(x: bounds.width, y: 0); c.scaleBy(x: -1, y: 1) }
        c.draw(atlas.frames[frameIndex], in: bounds); c.restoreGState()
    }
    public override func mouseDown(with event: NSEvent) {
        dragging = true; lastPoint = NSEvent.mouseLocation; lastTime = event.timestamp; velocity = .zero
        onDrag?(.zero, true)
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation, dt = max(0.001, event.timestamp - lastTime)
        let delta = NSPoint(x: p.x-lastPoint.x, y: p.y-lastPoint.y)
        velocity = NSPoint(x: delta.x/dt, y: delta.y/dt)
        if let onDrag { onDrag(delta, false) } else if let w = window { w.setFrameOrigin(NSPoint(x: w.frame.minX+delta.x, y: w.frame.minY+delta.y)) }
        lastPoint = p; lastTime = event.timestamp
    }
    public override func mouseUp(with event: NSEvent) {
        dragging = false
        onRelease?(event.timestamp-lastTime > 0.12 ? .zero : velocity)
    }
    public override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for (title, action) in [("Add Sheep", #selector(addSheep)), ("Remove Sheep", #selector(removeSheep))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func addSheep() { onAdd?() }
    @objc private func removeSheep() { onRemove?() }
}
