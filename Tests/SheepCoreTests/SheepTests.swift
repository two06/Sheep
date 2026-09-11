import Testing
import AppKit
@testable import SheepCore
@testable import SheepMac

@Suite(.serialized) struct SheepTests {
    let display = Display(id: 1,frame: Rect(x: 0,y: 0,width: 1200,height: 800),usable: Rect(x: 0,y: 25,width: 1200,height: 725))
    func environment(_ windows: [DesktopWindow] = []) -> Environment { Environment(displays: [display],windows: windows) }
    func simulation(_ windows: [DesktopWindow] = [], seed: UInt64 = 1) throws -> Simulation {
        let sim = Simulation(definition: try .bundled(),width: 40,height: 40,environment: environment(windows))
        try sim.add(seed: seed); return sim
    }
    func run(_ sim: Simulation, seconds: Double) throws { for _ in 0..<Int((seconds*60).rounded()) { try sim.advance(by: 1.0/60); _ = sim.drainEvents() } }
    @Test func testRelaunchRestoresEmptyFlockAndPreservesNonemptySettings() throws {
        let domain = "SheepTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = FlockPreferences(defaults: defaults)
        expectEqual(settings.startingCount, 1)
        settings.save(count: 0, scale: 1.5)
        // A new preferences reader models relaunch after removing the last sheep.
        let reopened = FlockPreferences(defaults: defaults)
        expectEqual(reopened.startingCount, 1)
        expectEqual(reopened.scale, 1.5)
        let sim = Simulation(definition: try .bundled(), width: 40, height: 40, environment: environment(), scale: reopened.scale)
        for seed in 0..<reopened.startingCount { try sim.add(seed: UInt64(seed)) }
        expectEqual(sim.count, 1)
        settings.save(count: 8, scale: 2)
        expectEqual(FlockPreferences(defaults: defaults).startingCount, 8)
        expectEqual(FlockPreferences(defaults: defaults).scale, 2)
    }
    @Test func testExpressions() throws {
        expectEqual(try Expression("5+random/10").integer(["random":99]),14)
        expectEqual(try Expression("-(3+5)*2%7").evaluate(),-2)
        expectEqual(try Expression("25+(Convert(screenW/2,System.Int32)%30)/7").integer(["screenW":1203]),25)
        expectEqual(try Expression("Convert(2.5,System.Int32)").evaluate(),2)
        expectEqual(try Expression("Convert(3.5,System.Int32)").evaluate(),4)
        expectEqual(try Expression("-2.9").integer(),-2)
        expectThrows(try Expression("1/0").evaluate())
        expectThrows(try Expression("random + evil"))
        expectThrows(try Expression("1 2"))
        expectThrows(try Expression("(2+3"))
    }
    @Test func testDefinitionReferencesFramesAndAllExpressions() throws {
        let d = try Definition.bundled(); expectEqual(d.animations.count,54); expectEqual(d.columns*d.rows,176); expectEqual(d.children.count,3)
        let vars: [String: Double] = ["screenW":1200,"screenH":800,"areaW":1200,"areaH":750,"imageW":40,"imageH":40,"imageX":500,"imageY":710,"random":99,"randS":99,"scale":1]
        for a in d.animations.values {
            expectGreater(try a.totalSteps(variables: vars),0)
            _ = try a.start.evaluate(vars); _ = try a.end.evaluate(vars)
            for step in 0..<min(500,try a.totalSteps(variables: vars)) { expectTrue((0..<176).contains(a.frame(at: step))) }
        }
    }
    @Test func testRepeatBoundaries() throws {
        let a = try Definition.bundled().animations[11]!
        let vars = ["random":0.0]
        expectEqual(try a.totalSteps(variables: vars),a.frames.count+(a.frames.count-5)*5)
        expectEqual(a.frame(at: a.frames.count),a.frames[5])
        expectEqual(a.frame(at: a.frames.count+(a.frames.count-5)),a.frames[5])
    }
    @Test func testConditionalWeights() {
        let options = [Transition(id:1,weight:10),Transition(id:2,weight:90,condition:.window),Transition(id:3,weight:100,condition:.taskbar)]
        var rng = SeededRandom(seed:42), counts: [Int:Int] = [:]
        for _ in 0..<10000 { counts[Transition.choose(options,at:.window,random:&rng)!,default:0] += 1 }
        expectNil(counts[3]); expectTrue((8500...9500).contains(counts[2]!))
        expectNil(Transition.choose([Transition(id:1,condition:.window)],at:[],random:&rng))
        for _ in 0..<100 { expectEqual(Transition.choose(options,at:[],random:&rng),1) }
    }
    @Test func testOccludedLedgesAndSweptLanding() {
        let front = DesktopWindow(id:1,frame:Rect(x:200,y:100,width:200,height:300)), back = DesktopWindow(id:2,frame:Rect(x:100,y:200,width:500,height:300))
        let e = environment([front,back]), exposed = e.ledges.filter { $0.windowID == 2 }
        expectEqual(exposed.map(\.left),[100,400]); expectEqual(exposed.map(\.right),[200,600])
        expectEqual(e.landing(from:Point(x:430,y:0),to:Point(x:430,y:500),width:40,height:40)?.windowID,2)
        expectEqual(e.landing(from:Point(x:250,y:0),to:Point(x:250,y:500),width:40,height:40)?.windowID,1)
        // End x lies over a window, but x at the crossing did not: must not land there.
        expectNil(e.landing(from:Point(x:0,y:120),to:Point(x:450,y:600),width:40,height:40)?.windowID)
    }
    @Test func testWindowUnderMenuBarNeedsVisibleHeadroom() {
        let maximized = DesktopWindow(id:1,frame:Rect(x:0,y:26,width:1200,height:700))
        let front = DesktopWindow(id:2,frame:Rect(x:100,y:100,width:500,height:500))
        let e = environment([front,maximized])
        expectEqual(e.landing(from:Point(x:200,y:-150),to:Point(x:200,y:200),width:40,height:40)?.windowID,2)
        expectNil(e.support(at:Point(x:200,y:-14),width:40,height:40))
        expectNil(e.landing(from:Point(x:200,y:-150),to:Point(x:200,y:200),width:80,height:80))
    }
    @Test func testMovingClosingAndOccludingSupport() throws {
        let w = DesktopWindow(id:7,frame:Rect(x:100,y:300,width:400,height:300)); let sim = try simulation([w])
        sim.place(1,at:Point(x:200,y:260)); try sim.selectAnimation(15,for:1)
        let moved = DesktopWindow(id:7,frame:Rect(x:180,y:350,width:400,height:300))
        try sim.updateEnvironment(environment([moved])); expectEqual(sim.sheep[1]?.position,Point(x:280,y:310)); expectEqual(sim.sheep[1]?.support?.windowID,7)
        try sim.updateEnvironment(environment()); expectEqual(sim.sheep[1]?.animationID,5); expectNil(sim.sheep[1]?.support)
        sim.place(1,at:Point(x:280,y:310)); try sim.updateEnvironment(environment([moved])); sim.place(1,at:Point(x:280,y:310))
        try sim.updateEnvironment(environment([DesktopWindow(id:8,frame:Rect(x:0,y:100,width:1000,height:500)),moved])); expectEqual(sim.sheep[1]?.animationID,5)
    }
    @Test func testCoordinatesNegativeOriginsAndDisplayDisconnect() throws {
        let rect = Rect(x:-1440,y:-200,width:1440,height:900)
        expectEqual(Coordinates.toAppKit(Coordinates.fromAppKit(rect,primaryTop:900),primaryTop:900),rect)
        let left = Display(id:2,frame:Rect(x:-1200,y:0,width:1200,height:800),usable:Rect(x:-1200,y:25,width:1200,height:725))
        let e = Environment(displays:[display,left],windows:[])
        expectTrue(e.canCross(from:display,to:Point(x:-1,y:500)))
        let gap = Display(id:3,frame:Rect(x:1400,y:0,width:1200,height:800),usable:Rect(x:1400,y:25,width:1200,height:725))
        expectFalse(Environment(displays:[display,gap],windows:[]).canCross(from:display,to:Point(x:1401,y:500)))
        let sim = Simulation(definition:try .bundled(),width:40,height:40,environment:e)
        try sim.add(seed:1,on:2); try sim.updateEnvironment(environment())
        expectEqual(sim.sheep[1]?.displayID,1); expectEqual(sim.sheep[1]?.animationID,5)
    }
    @Test func testTimingFlipsAndPause() throws {
        let sim = try simulation(); sim.place(1,at:Point(x:500,y:710)); try sim.selectAnimation(2,for:1)
        try run(sim,seconds:0.5); expectFalse(sim.sheep[1]!.flipped)
        try run(sim,seconds:0.12); expectTrue(sim.sheep[1]!.flipped); expectEqual(sim.sheep[1]?.animationID,3)
        sim.paused = true; let state = sim.renders[0]
        try run(sim,seconds:5); expectEqual(sim.renders[0].position,state.position); expectEqual(sim.renders[0].frame,state.frame)
    }
    @Test func testDragTossAndLanding() throws {
        let sim = try simulation([DesktopWindow(id:7,frame:Rect(x:100,y:300,width:700,height:300))]); sim.place(1,at:Point(x:300,y:50))
        try sim.interact(.beginDrag(1)); try sim.interact(.drag(1,Point(x:20,y:10))); expectEqual(sim.sheep[1]?.position,Point(x:320,y:60))
        try sim.interact(.release(1,Point(x:0,y:1600))); try run(sim,seconds:0.2)
        expectEqual(sim.sheep[1]?.support?.windowID,7); expectEqual(sim.sheep[1]?.position.y,260); expectEqual(sim.sheep[1]?.animationID,10)
    }
    @Test func testChildrenCleanupAndMirroring() throws {
        let sim = try simulation(); sim.place(1,at:Point(x:500,y:710)); try sim.selectAnimation(26,for:1); try sim.advance(by:0.01)
        expectEqual(sim.count,1); expectEqual(sim.sheep.count,2)
        let effect = sim.sheep.values.first { $0.isEffect }!; expectEqual(effect.position.x,464)
        try sim.selectAnimation(15,for:1); try run(sim,seconds:30); expectNil(sim.sheep[effect.id])
        try sim.selectAnimation(2,for:1); try run(sim,seconds:0.62); try sim.selectAnimation(26,for:1); try sim.advance(by:0.01)
        let mirrored = sim.sheep.values.first { $0.isEffect }!; expectEqual(mirrored.position.x,sim.sheep[1]!.position.x+36)
    }
    @Test func testAllSequencesCanRunAndEffectOpacity() throws {
        let sim = try simulation()
        for id in 1...54 {
            sim.removeEffects(); sim.place(1,at:Point(x:500,y:710)); try sim.selectAnimation(id,for:1); try run(sim,seconds:0.5)
            for render in sim.renders { expectTrue((0..<176).contains(render.frame)); expectTrue(render.position.x.isFinite); expectTrue((0...1).contains(render.opacity)) }
        }
        try sim.selectAnimation(34,for:1); try run(sim,seconds:0.2); expectLess(sim.renders.first { $0.id == 1 }!.opacity,0.7)
    }
    @Test func testAtlasTransparency() throws {
        let atlas = try SpriteAtlas(); expectEqual(atlas.frames.count,176); expectEqual(atlas.width,40); expectEqual(atlas.height,40)
        expectFalse(atlas.isOpaque(frame:2,x:0,y:0)); expectTrue(atlas.masks[2].contains(255)); expectTrue(atlas.masks[2].contains(0))
        for mask in atlas.masks { expectEqual(mask.count,1600) }
    }
    @Test func testIndependentSheepRandomnessAndInactiveDisplay() throws {
        let a = try simulation(seed:42), b = try simulation(seed:42)
        for seed in 2...10 { try b.add(seed:UInt64(seed)) }
        for _ in 0..<7200 {
            try a.advance(by:1.0/60); try b.advance(by:1.0/60)
            expectEqual(a.sheep[1]?.animationID,b.sheep[1]?.animationID)
            expectEqual(a.sheep[1]?.position,b.sheep[1]?.position)
            _ = a.drainEvents(); _ = b.drainEvents()
        }
        a.inactiveDisplays = [1]; let before = a.sheep[1]!.position
        try run(a,seconds:10); expectEqual(a.sheep[1]?.position,before)
    }
    @Test func testAdjacentMonitorTravelAndGapBoundary() throws {
        let second = Display(id:2,frame:Rect(x:1200,y:0,width:1200,height:800),usable:Rect(x:1200,y:25,width:1200,height:725))
        let sim = Simulation(definition:try .bundled(),width:40,height:40,environment:Environment(displays:[display,second],windows:[]))
        try sim.add(seed:1,on:2); sim.place(1,at:Point(x:1210,y:710)); try sim.selectAnimation(1,for:1)
        try run(sim,seconds:8); expectLess(sim.sheep[1]!.position.x,1200); expectEqual(sim.sheep[1]?.displayID,1)
        let gap = Display(id:2,frame:Rect(x:1400,y:0,width:1200,height:800),usable:Rect(x:1400,y:25,width:1200,height:725))
        let blocked = Simulation(definition:try .bundled(),width:40,height:40,environment:Environment(displays:[display,gap],windows:[]))
        try blocked.add(seed:1,on:2); blocked.place(1,at:Point(x:1400,y:710)); try blocked.selectAnimation(1,for:1)
        try run(blocked,seconds:0.25); expectEqual(blocked.sheep[1]?.position.x,1400); expectEqual(blocked.sheep[1]?.displayID,2)
        expectTrue(blocked.sheep[1]!.animationID != 1)
    }
    @Test func testDockBoundaryAndTerminalEffectRemovalEvent() throws {
        let sim = try simulation(); sim.place(1,at:Point(x:500,y:710)); try sim.selectAnimation(15,for:1)
        let dock = Display(id:1,frame:display.frame,usable:Rect(x:0,y:25,width:1200,height:675))
        try sim.updateEnvironment(Environment(displays:[dock],windows:[])); expectEqual(sim.sheep[1]?.position.y,660)
        try sim.selectAnimation(26,for:1); try sim.advance(by:0.01)
        let effectID = sim.sheep.values.first { $0.isEffect }!.id; _ = sim.drainEvents()
        try sim.selectAnimation(34,for:effectID)
        var removed = false
        for _ in 0..<120 { try sim.advance(by:1.0/60); if sim.drainEvents().contains(.removed(effectID)) { removed = true } }
        expectTrue(removed); expectNil(sim.sheep[effectID]); expectEqual(sim.count,1)
    }
    @Test func testCrossingToAdjacentDisplayWithLowerFloorFalls() throws {
        let second = Display(id:2,frame:Rect(x:1200,y:0,width:1200,height:800),usable:Rect(x:1200,y:25,width:1200,height:775))
        let sim = Simulation(definition:try .bundled(),width:40,height:40,environment:Environment(displays:[display,second],windows:[]))
        try sim.add(seed:1); sim.place(1,at:Point(x:1178,y:710))
        try sim.selectAnimation(2,for:1); try run(sim,seconds:0.62)
        try sim.selectAnimation(1,for:1); try run(sim,seconds:3)
        expectEqual(sim.sheep[1]?.displayID,2)
        expectEqual(sim.sheep[1]?.position.y,760)
        expectEqual(sim.sheep[1]?.support?.displayID,2)
    }
    @MainActor @Test func testSpriteInputMaskMatchesMirroredRendering() throws {
        let atlas = try SpriteAtlas(), view = SpriteView(atlas:try SpriteAtlas())
        view.frame = NSRect(x:0,y:0,width:80,height:80); view.frameIndex = 2
        for y in 0..<40 { for x in 0..<40 {
            let point = NSPoint(x:Double(x*2)+1,y:Double((39-y)*2)+1)
            expectEqual(view.opaque(at:point),atlas.isOpaque(frame:2,x:x,y:y))
        } }
        view.mirrored = true
        for y in 0..<40 { for x in 0..<40 {
            let point = NSPoint(x:Double(x*2)+1,y:Double((39-y)*2)+1)
            expectEqual(view.opaque(at:point),atlas.isOpaque(frame:2,x:39-x,y:y))
        } }
        view.opacity = 0; expectFalse(view.opaque(at:NSPoint(x:40,y:40)))
        expectFalse(view.opaque(at:NSPoint(x:-1,y:40)))
    }
    @MainActor @Test func testPanelPreservesSimulationCoordinatesNearMenuBar() throws {
        _ = NSApplication.shared
        let panel = SpritePanel(atlas:try SpriteAtlas())
        defer { panel.close() }
        let top = NSScreen.screens.first?.frame.maxY ?? 900
        for y in [-150.0,-6.0,0.0,33.0,100.0] {
            let requested = NSRect(x:200,y:top-y-40,width:40,height:40)
            expectEqual(panel.constrainFrameRect(requested,to:NSScreen.main),requested)
            panel.setFrame(requested,display:false)
            expectEqual(panel.frame,requested)
        }
        expectFalse(panel.canBecomeKey); expectFalse(panel.canBecomeMain)
    }
    @Test func testThirtyMinuteSimulationOneAndTenSheep() throws {
        for count in [1,10] {
            let sim = try simulation(); for i in 1..<count { try sim.add(seed:UInt64(i+1)) }
            var maxEffects = 0
            for tick in 0..<(30*60*60) {
                try sim.advance(by:1.0/60); _ = sim.drainEvents()
                if tick % 600 == 0 { maxEffects = max(maxEffects,sim.sheep.count-count); expectEqual(sim.count,count) }
            }
            expectLess(maxEffects,30)
        }
    }
    @Test func testCuratedSpriteAnimationsExist() throws {
        let defn = try Definition.bundled()
        for choice in spriteAnimationChoices { expectTrue(defn.animations[choice.id] != nil) }
    }
}

private func expectEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { let value = try a(); #expect(value == b, sourceLocation: sourceLocation) } catch { Issue.record(error,sourceLocation: sourceLocation) }
}
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value,sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value,sourceLocation: sourceLocation) }
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value == nil,sourceLocation: sourceLocation) }
private func expectGreater<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { let value = try a(); #expect(value > b,sourceLocation: sourceLocation) } catch { Issue.record(error,sourceLocation: sourceLocation) }
}
private func expectLess<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a < b,sourceLocation: sourceLocation) }
private func expectThrows<T>(_ action: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try action(); Issue.record("Expected expression to throw",sourceLocation: sourceLocation) } catch { }
}
