import Foundation

/// Global desktop points, x rightward and y downward, anchored to the primary display's top left.
public struct Point: Equatable { public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = Point(x: 0, y: 0)
}
public struct Rect: Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var right: Double { x+width }; public var bottom: Double { y+height }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x < right && p.y >= y && p.y < bottom }
    public func intersects(_ b: Rect) -> Bool { x < b.right && right > b.x && y < b.bottom && bottom > b.y }
}
public struct Display: Equatable {
    public let id: UInt32; public let frame: Rect; public let usable: Rect
    public init(id: UInt32, frame: Rect, usable: Rect) { self.id = id; self.frame = frame; self.usable = usable }
}
public struct DesktopWindow: Equatable {
    public let id: UInt32; public let frame: Rect
    public init(id: UInt32, frame: Rect) { self.id = id; self.frame = frame }
}
public struct Ledge: Equatable {
    public let windowID: UInt32?; public let displayID: UInt32; public var left: Double, right: Double, y: Double
    public init(windowID: UInt32?, displayID: UInt32, left: Double, right: Double, y: Double) { self.windowID = windowID; self.displayID = displayID; self.left = left; self.right = right; self.y = y }
    public var condition: Condition { windowID == nil ? .taskbar : .window }
    public func supports(centerX: Double, footY: Double) -> Bool { centerX >= left && centerX < right && abs(footY-y) < 1.5 }
}
public struct Environment {
    public let displays: [Display]; public let windows: [DesktopWindow]; public let ledges: [Ledge]
    public init(displays: [Display], windows: [DesktopWindow]) {
        self.displays = displays; self.windows = windows
        var surfaces: [Ledge] = []
        for display in displays {
            // Remove bottom portions that connect directly into another display.
            var bottomSegments = [(display.usable.x, display.usable.right)]
            for neighbor in displays where neighbor.id != display.id && abs(neighbor.usable.y-display.usable.bottom) < 1 {
                bottomSegments = Self.subtract(bottomSegments, left: neighbor.usable.x, right: neighbor.usable.right)
            }
            surfaces += bottomSegments.map { Ledge(windowID: nil, displayID: display.id, left: $0.0, right: $0.1, y: display.usable.bottom) }
        }
        for (index, window) in windows.enumerated() {
            for display in displays where window.frame.y >= display.usable.y && window.frame.y <= display.usable.bottom {
                let l = max(window.frame.x, display.usable.x), r = min(window.frame.right, display.usable.right)
                guard r > l else { continue }
                var segments = [(l,r)]
                // CGWindowList order is front to back. Covers include the exact top line.
                for cover in windows.prefix(index) where cover.frame.y <= window.frame.y && cover.frame.bottom > window.frame.y {
                    segments = Self.subtract(segments, left: cover.frame.x, right: cover.frame.right)
                }
                surfaces += segments.map { Ledge(windowID: window.id, displayID: display.id, left: $0.0, right: $0.1, y: window.frame.y) }
            }
        }
        ledges = surfaces
    }
    private static func subtract(_ segments: [(Double,Double)], left: Double, right: Double) -> [(Double,Double)] {
        segments.flatMap { a,b -> [(Double,Double)] in
            guard left < b, right > a else { return [(a,b)] }
            var result: [(Double,Double)] = []; if left > a { result.append((a,min(left,b))) }; if right < b { result.append((max(a,right),b)) }; return result
        }
    }
    private func hasHeadroom(_ ledge: Ledge, height: Double) -> Bool {
        guard ledge.windowID != nil, let display = displays.first(where: { $0.id == ledge.displayID }) else { return true }
        // A maximized window just below the menu bar has no visible room for a sheep.
        // Let it fall past that top rather than disappear behind the menu bar.
        return ledge.y-height >= display.usable.y
    }
    public func support(at p: Point, width: Double, height: Double) -> Ledge? { ledges.first { hasHeadroom($0,height: height) && $0.supports(centerX: p.x+width/2, footY: p.y+height) } }
    /// Swept feet test: evaluates x at the actual crossing time, preventing fast toss tunneling.
    public func landing(from a: Point, to b: Point, width: Double, height: Double) -> Ledge? {
        let start = a.y+height, end = b.y+height
        guard end > start else { return nil }
        return ledges.filter { s in
            guard hasHeadroom(s,height: height), s.y >= start-0.01, s.y <= end else { return false }
            let t = max(0,(s.y-start)/(end-start)), x = a.x+(b.x-a.x)*t+width/2
            return x >= s.left && x < s.right
        }.min { $0.y < $1.y }
    }
    public func display(at point: Point) -> Display? { displays.first { $0.frame.contains(point) } }
    public func nearestDisplay(to point: Point) -> Display? {
        displays.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }
    private func distance(_ p: Point, _ r: Rect) -> Double {
        pow(max(r.x-p.x,0,p.x-r.right),2)+pow(max(r.y-p.y,0,p.y-r.bottom),2)
    }
    public func canCross(from display: Display, to point: Point) -> Bool {
        displays.contains { other in
            guard other.id != display.id, other.usable.contains(point) else { return false }
            let a = display.usable, b = other.usable
            return ((abs(a.right-b.x)<1 || abs(b.right-a.x)<1) && min(a.bottom,b.bottom)>max(a.y,b.y)) || ((abs(a.bottom-b.y)<1 || abs(b.bottom-a.y)<1) && min(a.right,b.right)>max(a.x,b.x))
        }
    }
}
public enum Coordinates {
    public static func fromAppKit(_ rect: Rect, primaryTop: Double) -> Rect { Rect(x: rect.x, y: primaryTop-rect.bottom, width: rect.width, height: rect.height) }
    public static func toAppKit(_ rect: Rect, primaryTop: Double) -> Rect { fromAppKit(rect, primaryTop: primaryTop) }
}
