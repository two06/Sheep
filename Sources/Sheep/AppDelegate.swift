import AppKit
import ServiceManagement
import SheepCore
import SheepMac

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var atlas: SpriteAtlas!
    private var simulation: Simulation!
    private var snapshot: DesktopSnapshot!
    private var status: NSStatusItem!
    private var panels: [UInt64: SpritePanel] = [:]
    private var animationTimer: Timer?, geometryTimer: Timer?, metricsTimer: Timer?
    private var lastTime = 0.0, pollCount = 0, pollTotal = 0.0, pollMax = 0.0, tickCount = 0
    private var isPaused = false, isHidden = false, sleeping = false, sessionInactive = false
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private let preferences = UserDefaults.standard
    private lazy var flockPreferences = FlockPreferences(defaults: preferences)
    private var pauseItem: NSMenuItem!, hideItem: NSMenuItem!, loginItem: NSMenuItem!
    private var errorMessage: String?
    private var started = 0.0
    private var soakPhase = 0
    private var soakCount: Int? {
        guard let i = CommandLine.arguments.firstIndex(of: "--soak"), CommandLine.arguments.indices.contains(i+1), let count = Int(CommandLine.arguments[i+1]) else { return nil }
        return max(1,min(100,count))
    }
    private var isSuspended: Bool { isPaused || isHidden || sleeping || sessionInactive }
    private var metricsURL: URL? {
        guard let i = CommandLine.arguments.firstIndex(of: "--metrics"), CommandLine.arguments.indices.contains(i+1) else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[i+1])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.register(defaults: ["sheepCount": 1, "sheepScale": 1.0, "launchAtLogin": false])
        do {
            atlas = try SpriteAtlas(); snapshot = DesktopSnapshot.capture()
            simulation = Simulation(definition: try Definition.bundled(),width: Double(atlas.width),height: Double(atlas.height),environment: snapshot.environment,scale: flockPreferences.scale)
            buildMenu()
            started = ProcessInfo.processInfo.systemUptime
            let initialCount = CommandLine.arguments.contains("--fixture-window") ? 1 : (soakCount ?? flockPreferences.startingCount)
            for _ in 0..<initialCount { try addOne() }
            if CommandLine.arguments.contains("--fixture-window"),
               let data = try? Data(contentsOf:URL(fileURLWithPath:"/tmp/sheep-fixture.json")),
               let fixture = try? JSONSerialization.jsonObject(with:data) as? [String:Int],
               let windowID = fixture["windowID"], let window = snapshot.environment.windows.first(where:{ $0.id == UInt32(windowID) }) {
                simulation.place(1,at:Point(x:window.frame.x+window.frame.width/2-20,y:window.frame.y-180))
                try simulation.selectAnimation(5,for:1)
            }
            installObservers(); restartTimers(); render()
            if metricsURL != nil {
                metricsTimer = Timer(timeInterval: CommandLine.arguments.contains("--fixture-window") ? 0.1 : 5,repeats: true) { [weak self] _ in self?.metricsTick() }; RunLoop.main.add(metricsTimer!,forMode: .common)
            }
        } catch { fatalAlert(error) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard simulation != nil else { return false }
        attempt {
            isHidden = false
            isPaused = false
            restartTimers()
            if simulation.count == 0 { try addOne() }
            render()
        }
        return false
    }
    private func buildMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = soakCount.map { "🐑 \($0) test" } ?? "🐑"; status.button?.toolTip = "Sheep"
        let menu = NSMenu(); menu.delegate = self
        func item(_ title: String, _ action: Selector) -> NSMenuItem { let i = menu.addItem(withTitle: title,action: action,keyEquivalent: ""); i.target = self; return i }
        _ = item("Add Sheep",#selector(addSheep)); _ = item("Remove Sheep",#selector(removeSheep)); menu.addItem(.separator())
        pauseItem = item("Pause",#selector(togglePause)); hideItem = item("Hide",#selector(toggleHidden))
        let size = menu.addItem(withTitle: "Size",action: nil,keyEquivalent: ""); let sizes = NSMenu()
        for (title,scale) in [("Original (40 pt)",1.0),("Large (60 pt)",1.5),("Double (80 pt)",2.0)] {
            let i = sizes.addItem(withTitle: title,action: #selector(setSize(_:)),keyEquivalent: ""); i.target = self; i.representedObject = scale
        }
        size.submenu = sizes; menu.addItem(.separator())
        loginItem = item("Launch at Login",#selector(toggleLogin)); _ = item("About Sheep",#selector(about))
        #if DEBUG
        let inspector = menu.addItem(withTitle: "Inspect Animation",action: nil,keyEquivalent: "")
        let animations = NSMenu()
        for a in simulation.definition.animations.values.sorted(by: { $0.id < $1.id }) {
            let i = animations.addItem(withTitle: "\(a.id) · \(a.name)",action: #selector(inspectAnimation(_:)),keyEquivalent: ""); i.target = self; i.tag = a.id
        }
        inspector.submenu = animations
        #endif
        menu.addItem(.separator()); _ = item("Quit Sheep",#selector(quit)); status.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = isPaused ? "Resume" : "Pause"; hideItem.title = isHidden ? "Show" : "Hide"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        preferences.set(SMAppService.mainApp.status == .enabled,forKey: "launchAtLogin")
        if let size = menu.items.first(where: { $0.title == "Size" })?.submenu {
            for item in size.items { item.state = (item.representedObject as? Double) == simulation.scale ? .on : .off }
        }
    }
    private func addOne() throws { try simulation.add(seed: UInt64.random(in: 0...UInt64.max)); persist() }
    private func persist() { guard soakCount == nil && !CommandLine.arguments.contains("--fixture-window") else { return }; flockPreferences.save(count: simulation.count, scale: simulation.scale) }
    @objc private func addSheep() { attempt { if simulation.count < 100 { try addOne(); render() } } }
    @objc private func removeSheep() { if let id = simulation.sheep.values.filter({ !$0.isEffect }).map(\.id).max() { remove(id) } }
    private func remove(_ id: UInt64) { simulation.remove(id); persist(); render() }
    @objc private func togglePause() { isPaused.toggle(); restartTimers() }
    @objc private func toggleHidden() { isHidden.toggle(); restartTimers(); render() }
    @objc private func setSize(_ sender: NSMenuItem) { attempt { try simulation.setScale(sender.representedObject as? Double ?? 1); persist(); render() } }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            preferences.set(SMAppService.mainApp.status == .enabled,forKey: "launchAtLogin")
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { let alert = NSAlert(); alert.messageText = "Could not change Launch at Login"; alert.informativeText = "Run the packaged Sheep.app from a stable location. \(error.localizedDescription)"; alert.runModal() }
    }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "Sheep"
        alert.informativeText = "A private, offline macOS home for the classic eSheep.\n\nOriginal eSheep: Fuji Television / the original creators.\neSheep 64bit definition: Adriano (Adrianotiger).\nImage rip: LiL_Stenly.\n\n54 original animations. No network access, telemetry or updates."
        alert.runModal()
    }
    @objc private func inspectAnimation(_ sender: NSMenuItem) {
        attempt {
            if simulation.count == 0 { try addOne() }
            guard let id = simulation.sheep.values.filter({ !$0.isEffect }).map(\.id).min(), let d = snapshot.environment.displays.first else { return }
            simulation.removeEffects(); simulation.place(id,at: Point(x: d.usable.x+d.usable.width/2,y: d.usable.bottom-simulation.height))
            try simulation.selectAnimation(sender.tag,for: id); isPaused = false; isHidden = false; restartTimers(); render()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ action: @escaping () -> Void) {
            observers.append(workspace.addObserver(forName: name,object: nil,queue: .main) { _ in action() })
        }
        observe(NSWorkspace.willSleepNotification) { [weak self] in self?.sleeping = true; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.didWakeNotification) { [weak self] in self?.sleeping = false; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.sleeping = true; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.sleeping = false; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.sessionInactive = true; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.sessionInactive = false; self?.restartTimers(); self?.render() }
        observe(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            guard let self else { return }; if !self.isSuspended { self.refreshGeometry(); self.render() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,object: nil,queue: .main) { [weak self] _ in
            guard let self else { return }; if !self.isSuspended { self.refreshGeometry(); self.render() }
        })
        // Login-window notifications complement public session/screen-sleep notifications on lock.
        for (name,locked) in [("com.apple.screenIsLocked",true),("com.apple.screenIsUnlocked",false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name),object: nil,queue: .main) { [weak self] _ in
                self?.sessionInactive = locked; self?.restartTimers(); self?.render()
            })
        }
    }
    private func restartTimers() {
        animationTimer?.invalidate(); geometryTimer?.invalidate(); animationTimer = nil; geometryTimer = nil
        simulation.paused = isSuspended
        panels.values.forEach { $0.updateMouseAcceptance(enabled: !isSuspended) }
        guard !isSuspended else { return }
        refreshGeometry(); lastTime = ProcessInfo.processInfo.systemUptime
        animationTimer = Timer(timeInterval: 1.0/60,repeats: true) { [weak self] _ in self?.tick() }
        geometryTimer = Timer(timeInterval: 0.1,repeats: true) { [weak self] _ in self?.refreshGeometry() }
        animationTimer?.tolerance = 0.002; geometryTimer?.tolerance = 0.015
        RunLoop.main.add(animationTimer!,forMode: .common); RunLoop.main.add(geometryTimer!,forMode: .common)
    }
    private func refreshGeometry() {
        snapshot = DesktopSnapshot.capture(); pollCount += 1; pollTotal += snapshot.pollMilliseconds; pollMax = max(pollMax,snapshot.pollMilliseconds)
        attempt { try simulation.updateEnvironment(snapshot.environment); simulation.inactiveDisplays = snapshot.fullScreenDisplays }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now-lastTime; lastTime = now; tickCount += 1
        attempt { try simulation.advance(by: elapsed); render() }
    }
    private func render() {
        guard simulation != nil else { return }
        _ = simulation.drainEvents()
        let states = simulation.renders, ids = Set(states.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) { panels.removeValue(forKey: id)?.close() }
        for state in states {
            let p: SpritePanel
            if let existing = panels[state.id] { p = existing } else {
                p = SpritePanel(atlas: atlas); panels[state.id] = p
                p.sprite.onRemove = { [weak self] in self?.remove(state.id) }
                p.sprite.onDrag = { [weak self] delta,begin in
                    guard let self else { return }; self.attempt {
                        try self.simulation.interact(begin ? .beginDrag(state.id) : .drag(state.id,Point(x: delta.x,y: -delta.y))); self.render()
                    }
                }
                p.sprite.onRelease = { [weak self] velocity in self?.attempt { try self?.simulation.interact(.release(state.id,Point(x: velocity.x,y: -velocity.y))) } }
            }
            let appRect = Coordinates.toAppKit(Rect(x: state.position.x,y: state.position.y,width: state.width,height: state.height),primaryTop: snapshot.primaryTop)
            let newFrame = NSRect(x: appRect.x,y: appRect.y,width: appRect.width,height: appRect.height)
            if p.frame != newFrame { p.setFrame(newFrame,display: false) }
            if p.sprite.frameIndex != state.frame { p.sprite.frameIndex = state.frame }
            if p.sprite.mirrored != state.flipped { p.sprite.mirrored = state.flipped }
            if p.sprite.opacity != state.opacity { p.sprite.opacity = state.opacity }
            let hiddenByFullScreen = snapshot.environment.displays.contains { d in snapshot.fullScreenDisplays.contains(d.id) && d.frame.intersects(Rect(x: state.position.x,y: state.position.y,width: state.width,height: state.height)) }
            let visible = !isHidden && !sleeping && !sessionInactive && !hiddenByFullScreen
            if visible { if !p.isVisible { p.orderFrontRegardless() } } else if p.isVisible { p.orderOut(nil) }
            p.updateMouseAcceptance(enabled: visible && !isSuspended && !state.isEffect)
        }
        status.button?.toolTip = "\(simulation.count) sheep"
    }
    private func attempt(_ body: () throws -> Void) { do { try body() } catch { errorMessage = String(describing: error); isPaused = true; animationTimer?.invalidate(); geometryTimer?.invalidate(); simulation.paused = true; NSLog("Sheep paused: %@",String(describing: error)) } }
    private func fatalAlert(_ error: Error) { let a = NSAlert(); a.messageText = "Sheep could not start"; a.informativeText = String(describing: error); a.runModal(); NSApp.terminate(nil) }
    private func metricsTick() {
        let elapsed = ProcessInfo.processInfo.systemUptime-started
        if soakCount != nil {
            if elapsed >= 10 && soakPhase == 0 { isPaused = true; soakPhase = 1; restartTimers() }
            else if elapsed >= 20 && soakPhase == 1 { isPaused = false; isHidden = true; soakPhase = 2; restartTimers(); render() }
            else if elapsed >= 30 && soakPhase == 2 { isHidden = false; soakPhase = 3; restartTimers(); render() }
        }
        writeMetrics()
        if (soakCount != nil && elapsed >= 1835) || (CommandLine.arguments.contains("--fixture-window") && elapsed >= 35) { NSApp.terminate(nil) }
    }
    private var panelPositionError: Double {
        simulation.renders.compactMap { state -> Double? in
            guard let panel = panels[state.id] else { return nil }
            return max(abs(panel.frame.minX-state.position.x),abs(snapshot.primaryTop-panel.frame.maxY-state.position.y))
        }.max() ?? 0
    }
    private func writeMetrics() {
        guard let url = metricsURL else { return }
        let data: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime,"elapsed": ProcessInfo.processInfo.systemUptime-started,"residentBytes": MemoryUsage.residentBytes,"maxPanelPositionError": panelPositionError,"states": simulation.sheep.values.sorted { $0.id < $1.id }.map { ["id": String($0.id),"animation": String($0.animationID),"step": String($0.step),"x": String($0.position.x),"y": String($0.position.y),"support": $0.support.map { $0.windowID.map(String.init) ?? "floor" } ?? "none"] },"windowCount": snapshot.environment.windows.count,"ledgeCount": snapshot.environment.ledges.count,"soakPhase": soakPhase,"visiblePanels": panels.values.filter { $0.isVisible }.count,"sheep": simulation.count,"effects": simulation.sheep.count-simulation.count,"panels": panels.count,"ticks": tickCount,"polls": pollCount,"pollMeanMs": pollTotal/Double(max(1,pollCount)),"pollMaxMs": pollMax,"suspended": isSuspended,"error": errorMessage ?? ""]
        if let json = try? JSONSerialization.data(withJSONObject: data,options: [.sortedKeys]), let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(json); handle.write(Data([10])); try? handle.close() }
        else if let json = try? JSONSerialization.data(withJSONObject: data,options: [.sortedKeys]) { try? (json+Data([10])).write(to: url) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate(); geometryTimer?.invalidate(); metricsTimer?.invalidate(); writeMetrics()
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token); NotificationCenter.default.removeObserver(token) }
        for token in distributedObservers { DistributedNotificationCenter.default().removeObserver(token) }
    }
}
