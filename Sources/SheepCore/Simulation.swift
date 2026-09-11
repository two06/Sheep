import Foundation

public struct RenderState {
    public let id: UInt64, animationID: Int, frame: Int
    public let position: Point, width: Double, height: Double, flipped: Bool, opacity: Double, isEffect: Bool
}
public enum SimulationEvent: Equatable { case spawned(UInt64), removed(UInt64) }
public enum Interaction { case beginDrag(UInt64), drag(UInt64, Point), release(UInt64, Point), remove(UInt64) }

public struct SheepState {
    public let id: UInt64, isEffect: Bool
    public var position: Point
    public fileprivate(set) var animationID = 1, step = 0, totalSteps = 1
    public fileprivate(set) var flipped = false, dragging = false, support: Ledge? = nil, displayID: UInt32
    fileprivate var random: SeededRandom, spawnRandom: Double, remaining = 0.0, toss: Point? = nil, tossTime = 0.0
    fileprivate var start = Values(x: 0,y: 0,interval: 0.1,offsetY: 0,opacity: 1)
    fileprivate var end = Values(x: 0,y: 0,interval: 0.1,offsetY: 0,opacity: 1)
    fileprivate var pendingChildren = false, age = 0.0
    fileprivate var values: Values { start.interpolated(to: end, movementProgress: Double(step)/Double(max(1,totalSteps-1)), visualProgress: Double(step)/Double(totalSteps)) }
}

/// Pure simulation: elapsed seconds and immutable environment in; render states and lifetime events out.
/// Each sheep owns its PRNG. The host supplies time and seed; no timers, AppKit, I/O or global randomness.
public final class Simulation {
    public let definition: Definition, frameWidth: Double, frameHeight: Double
    public private(set) var sheep: [UInt64: SheepState] = [:]
    public private(set) var environment: Environment
    public private(set) var scale: Double
    public var paused = false
    public var inactiveDisplays: Set<UInt32> = []
    public private(set) var events: [SimulationEvent] = []
    private var nextID: UInt64 = 1
    public init(definition: Definition, width: Double, height: Double, environment: Environment, scale: Double = 1) {
        self.definition = definition; frameWidth = width; frameHeight = height; self.environment = environment; self.scale = scale
    }
    public var count: Int { sheep.values.filter { !$0.isEffect }.count }
    public var width: Double { frameWidth*scale }; public var height: Double { frameHeight*scale }
    public var renders: [RenderState] {
        sheep.values.sorted { $0.id < $1.id }.map { s in
            let v = s.values
            return RenderState(id: s.id, animationID: s.animationID, frame: definition.animations[s.animationID]!.frame(at: s.step), position: Point(x: s.position.x,y: s.position.y+v.offsetY*scale), width: width,height: height,flipped: s.flipped,opacity: max(0,min(1,v.opacity)),isEffect: s.isEffect)
        }
    }
    public func drainEvents() -> [SimulationEvent] { defer { events.removeAll(keepingCapacity: true) }; return events }
    @discardableResult public func add(seed: UInt64, on displayID: UInt32? = nil) throws -> UInt64? {
        guard let display = environment.displays.first(where: { $0.id == displayID }) ?? environment.displays.first else { return nil }
        let id = nextID; nextID += 1
        var rng = SeededRandom(seed: seed); let spawnRandom = Double(rng.integer(100))
        var s = SheepState(id: id,isEffect: false,position: .zero,displayID: display.id,random: rng,spawnRandom: spawnRandom)
        try spawn(&s, display: display); sheep[id] = s; events.append(.spawned(id)); return id
    }
    public func remove(_ id: UInt64) { if sheep.removeValue(forKey: id) != nil { events.append(.removed(id)) } }
    public func removeEffects() { for s in sheep.values where s.isEffect { remove(s.id) } }
    public func setScale(_ value: Double) throws {
        let oldHeight = height; scale = max(0.5,min(3,value))
        for id in sheep.keys.sorted() { var s = sheep[id]!; s.position.y += oldHeight-height; sheep[id] = s }
        try updateEnvironment(environment)
    }
    private func variables(_ s: SheepState, display: Display, mirroredChild: Bool = false) -> [String: Double] {
        ["screenW": display.frame.width/scale,"screenH": display.frame.height/scale,"areaW": display.usable.width/scale,"areaH": (display.usable.bottom-display.frame.y)/scale,"imageW": frameWidth * (mirroredChild && s.flipped ? -1 : 1),"imageH": frameHeight,"imageX": (s.position.x-display.frame.x)/scale,"imageY": (s.position.y-display.frame.y)/scale,"randS": s.spawnRandom,"scale": scale]
    }
    private func enter(_ id: Int, _ s: inout SheepState) throws {
        guard let a = definition.animations[id], let display = environment.displays.first(where: { $0.id == s.displayID }) ?? environment.nearestDisplay(to: s.position) else { return }
        s.animationID = id; s.step = 0
        var vars = variables(s,display: display); vars["random"] = Double(s.random.integer(100))
        s.totalSteps = try a.totalSteps(variables: vars); s.start = try a.start.evaluate(vars); s.end = try a.end.evaluate(vars)
        s.remaining = s.start.interval; s.pendingChildren = true
    }
    private func spawn(_ s: inout SheepState, display: Display) throws {
        s.spawnRandom = Double(s.random.integer(100)); s.flipped = false; s.support = nil; s.toss = nil; s.displayID = display.id
        var ticket = s.random.integer(definition.spawns.reduce(0) { $0+$1.weight }); var chosen = definition.spawns[0]
        for spawn in definition.spawns { if ticket < spawn.weight { chosen = spawn; break }; ticket -= spawn.weight }
        var vars = variables(s,display: display); vars["random"] = Double(s.random.integer(100))
        s.position = try Point(x: display.frame.x+Double(chosen.x.integer(vars))*scale,y: display.frame.y+Double(chosen.y.integer(vars))*scale)
        try enter(Transition.choose(chosen.next,at: [],random: &s.random) ?? 1,&s)
    }
    public func selectAnimation(_ animation: Int, for id: UInt64) throws {
        guard var s = sheep[id], definition.animations[animation] != nil else { return }
        s.toss = nil; try enter(animation,&s); sheep[id] = s
    }
    /// Useful for a deterministic animation inspector and tests, and for platform-driven relocation.
    public func place(_ id: UInt64, at point: Point) {
        guard var s = sheep[id] else { return }; s.position = point
        s.support = environment.support(at: point,width: width,height: height); sheep[id] = s
    }
    public func interact(_ event: Interaction) throws {
        switch event {
        case .remove(let id): remove(id)
        case .beginDrag(let id):
            guard var s = sheep[id], !s.isEffect else { return }; s.dragging = true; s.support = nil; s.toss = nil; try enter(4,&s); sheep[id] = s
        case .drag(let id,let delta):
            guard var s = sheep[id], s.dragging else { return }; s.position.x += delta.x; s.position.y += delta.y; sheep[id] = s
        case .release(let id,let velocity):
            guard var s = sheep[id], s.dragging else { return }; s.dragging = false; s.tossTime = 0
            s.toss = Point(x: max(-1800,min(1800,velocity.x)), y: max(-1800,min(1800,velocity.y)))
            try enter(5,&s); sheep[id] = s
        }
    }
    public func updateEnvironment(_ new: Environment) throws {
        let old = environment; environment = new
        for id in sheep.keys.sorted() {
            var s = sheep[id]!
            guard let display = new.displays.first(where: { $0.id == s.displayID }) else {
                if let display = new.nearestDisplay(to: s.position) {
                    if s.isEffect { remove(id); continue }
                    s.displayID = display.id; s.position = Point(x: display.usable.x+display.usable.width/2-width/2,y: display.usable.y+20); s.support = nil; try enter(5,&s)
                }
                sheep[id] = s; continue
            }
            if !s.dragging, let support = s.support {
                if let windowID = support.windowID, let before = old.windows.first(where: { $0.id == windowID }), let after = new.windows.first(where: { $0.id == windowID }) {
                    s.position.x += after.frame.x-before.frame.x; s.position.y += after.frame.y-before.frame.y
                } else if support.windowID == nil {
                    s.position.y = display.usable.bottom-height
                }
                s.support = new.support(at: s.position,width: width,height: height)
                if s.support == nil { try enter(5,&s) }
            }
            sheep[id] = s
        }
    }
    public func advance(by elapsed: Double) throws {
        guard !paused, elapsed.isFinite, elapsed > 0, !environment.displays.isEmpty else { return }
        // Bounded catch-up protects against wake stalls; callers pause the clock on sleep.
        let dt = min(elapsed,0.25)
        for id in sheep.keys.sorted() {
            guard var s = sheep[id], !inactiveDisplays.contains(s.displayID) else { continue }; s.age += dt
            if s.isEffect && s.age > 600 { remove(id); continue }
            try createChildren(&s)
            if s.toss != nil && !s.dragging { try toss(&s,dt: dt) }
            s.remaining -= dt
            var steps = 0, alive = true
            while s.remaining <= 0 && steps < 128 {
                let overshoot = s.remaining
                alive = try step(&s); if !alive { break }
                s.remaining = overshoot + max(0.01,s.values.interval); steps += 1
                try createChildren(&s)
            }
            if alive { sheep[id] = s } else { remove(id) }
        }
    }
    private func createChildren(_ s: inout SheepState) throws {
        guard s.pendingChildren else { return }; s.pendingChildren = false
        guard !s.isEffect, sheep.count < count+128, let display = environment.displays.first(where: { $0.id == s.displayID }) else { return }
        for child in definition.children where child.parentAnimation == s.animationID {
            let id = nextID; nextID += 1
            var vars = variables(s,display: display,mirroredChild: true); vars["random"] = Double(s.random.integer(100))
            let position = try Point(x: display.frame.x+Double(child.x.integer(vars))*scale,y: display.frame.y+Double(child.y.integer(vars))*scale)
            var c = SheepState(id: id,isEffect: true,position: position,displayID: display.id,random: SeededRandom(seed: s.random.next()),spawnRandom: s.spawnRandom)
            c.flipped = s.flipped; try enter(child.next,&c); sheep[id] = c; events.append(.spawned(id))
        }
    }
    private func step(_ s: inout SheepState) throws -> Bool {
        let a = definition.animations[s.animationID]!
        if !s.dragging && s.toss == nil {
            let v = s.values, delta = Point(x: v.x*scale*(s.flipped ? -1 : 1),y: v.y*scale)
            if try move(&s,delta: delta,animation: a) { return true }
        }
        s.step += 1
        if s.step >= s.totalSteps {
            if s.dragging { try enter(4,&s); return true }
            if s.toss != nil { try enter(6,&s); return true }
            if a.flipAtEnd { s.flipped.toggle() }
            let condition = s.support?.condition ?? []
            if let next = Transition.choose(a.next,at: condition,random: &s.random), next > 0 {
                try enter(next,&s)
            } else if s.isEffect { return false }
            else if let d = environment.nearestDisplay(to: s.position) { try spawn(&s,display: d) }
        }
        if !s.dragging && !s.isEffect && s.toss == nil, let d = environment.displays.first(where: { $0.id == s.displayID }) {
            // Preserve authored offscreen entrances, but recycle sheep which have fully exited.
            if s.position.x < d.frame.x-width*2 || s.position.x > d.frame.right+width*2 || s.position.y > d.frame.bottom+height*2 {
                try spawn(&s,display: d)
            }
        }
        return true
    }
    /// Returns true when collision/gravity changed the animation.
    private func move(_ s: inout SheepState, delta: Point, animation a: Animation) throws -> Bool {
        let before = s.position; var target = Point(x: before.x+delta.x,y: before.y+delta.y)
        let foot = Point(x: before.x+width/2,y: before.y+height-1)
        guard let display = environment.display(at: foot) ?? environment.displays.first(where: { $0.id == s.displayID }) else { return false }
        s.displayID = display.id
        if let support = s.support, delta.y == 0, !support.supports(centerX: target.x+width/2,footY: target.y+height) {
            let continuation = environment.support(at: target,width: width,height: height)
            let crossesDisplay = environment.canCross(from: display,to: Point(x: target.x+width/2,y: target.y+height-1))
            if support.windowID == nil && crossesDisplay {
                // A neighbour may have a lower floor because its Dock reservation differs.
                // Cross the seam and fall to that floor rather than treating it as a wall.
                s.support = continuation
            } else if let continuation, continuation.windowID == support.windowID, crossesDisplay {
                s.support = continuation
            } else if let next = Transition.choose(a.border,at: support.condition,random: &s.random), next > 0 {
                s.position.x = delta.x < 0 ? support.left-width/2 : support.right-width/2-0.1
                try enter(next,&s); return true
            }
            else { s.support = nil }
        }
        let horizontalCross = Point(x: delta.x < 0 ? target.x : target.x+width,y: target.y+height-1)
        let exitingSide = (delta.x < 0 && target.x < display.usable.x && before.x >= display.usable.x-1) || (delta.x > 0 && target.x+width > display.usable.right && before.x+width <= display.usable.right+1)
        if exitingSide && !environment.canCross(from: display,to: horizontalCross) {
            if let next = Transition.choose(a.border,at: .vertical,random: &s.random), next > 0 {
                s.position.x = delta.x < 0 ? display.usable.x : display.usable.right-width
                try enter(next,&s); return true
            }
        }
        if delta.y < 0 && target.y < display.usable.y && before.y >= display.usable.y-1 && !environment.canCross(from: display,to: Point(x: target.x+width/2,y: target.y)) {
            if let next = Transition.choose(a.border,at: .horizontal,random: &s.random), next > 0 {
                s.position.y = display.usable.y; s.support = nil; try enter(next,&s); return true
            }
        }
        if delta.y > 0, let landing = environment.landing(from: before,to: target,width: width,height: height), let next = Transition.choose(a.border,at: landing.condition,random: &s.random), next > 0 {
            let t = max(0,(landing.y-height-before.y)/delta.y)
            target.x = before.x+delta.x*t; target.y = landing.y-height; s.position = target; s.support = landing
            try enter(next,&s); return true
        }
        s.position = target
        if delta.y != 0 { s.support = nil }
        s.support = environment.support(at: target,width: width,height: height)
        if !a.gravity.isEmpty && s.support == nil, let next = Transition.choose(a.gravity,at: [],random: &s.random), next > 0 { try enter(next,&s); return true }
        return false
    }
    private func toss(_ s: inout SheepState, dt: Double) throws {
        guard var velocity = s.toss else { return }
        // Substeps bound boundary traversal as well as swept ledge tests.
        let n = max(1,Int(ceil(dt/(1.0/120)))), h = dt/Double(n)
        for _ in 0..<n {
            let before = s.position
            var target = Point(x: before.x+velocity.x*h,y: before.y+velocity.y*h+450*h*h)
            if let d = environment.display(at: Point(x: before.x+width/2,y: before.y+height/2)) ?? environment.nearestDisplay(to: before) {
                s.displayID = d.id
                let side = Point(x: velocity.x < 0 ? target.x : target.x+width,y: target.y+height/2)
                if (target.x < d.usable.x || target.x+width > d.usable.right) && !environment.canCross(from: d,to: side) {
                    target.x = max(d.usable.x,min(d.usable.right-width,target.x)); velocity.x *= -0.3
                }
                if target.y < d.usable.y && !environment.canCross(from: d,to: Point(x: target.x+width/2,y: target.y)) { target.y = d.usable.y; velocity.y = abs(velocity.y)*0.3 }
            }
            if let landing = environment.landing(from: before,to: target,width: width,height: height) {
                let t = max(0,(landing.y-height-before.y)/(target.y-before.y))
                s.position = Point(x: before.x+(target.x-before.x)*t,y: landing.y-height); s.support = landing; s.toss = nil
                try enter(velocity.y > 450 ? 10 : 9,&s); return
            }
            s.position = target; velocity.y += 900*h; velocity.x *= exp(-0.35*h)
        }
        s.tossTime += dt
        if s.tossTime > 1.5 && velocity.y > 0 { s.toss = nil; try enter(6,&s) } else { s.toss = velocity }
    }
}
