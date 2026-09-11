import AppKit
import SheepCore

public struct DesktopSnapshot {
    public let environment: Environment
    public let primaryTop: Double
    public let fullScreenDisplays: Set<UInt32>
    public let pollMilliseconds: Double
    public static func capture() -> DesktopSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        let displays = screens.compactMap { screen -> Display? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            func convert(_ r: NSRect) -> Rect { Coordinates.fromAppKit(Rect(x: r.minX,y: r.minY,width: r.width,height: r.height),primaryTop: primaryTop) }
            return Display(id: id,frame: convert(screen.frame),usable: convert(screen.visibleFrame))
        }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [DesktopWindow] = [], fullscreen: Set<UInt32> = []
        let excluded = Set(["Dock", "Window Server", "SystemUIServer", "Control Center", "Notification Center", "Spotlight"])
        for info in raw {
            guard (info[kCGWindowOwnerPID as String] as? Int32) != getpid(),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  !excluded.contains(info[kCGWindowOwnerName as String] as? String ?? ""),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1 else { continue }
            let r = Rect(x: rect.minX,y: rect.minY,width: rect.width,height: rect.height)
            windows.append(DesktopWindow(id: id,frame: r))
            // Public window metadata has no Space/fullscreen flag. Conservatively hide on any
            // display covered edge-to-edge by an ordinary window, including borderless video.
            for d in displays where r.x <= d.frame.x+1 && r.y <= d.frame.y+1 && r.right >= d.frame.right-1 && r.bottom >= d.frame.bottom-1 { fullscreen.insert(d.id) }
        }
        return DesktopSnapshot(environment: Environment(displays: displays,windows: windows),primaryTop: primaryTop,fullScreenDisplays: fullscreen,pollMilliseconds: (ProcessInfo.processInfo.systemUptime-started)*1000)
    }
}
