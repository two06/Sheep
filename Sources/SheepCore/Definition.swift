import Foundation
import Foundation

public struct Condition: OptionSet, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let taskbar = Condition(rawValue: 1)
    public static let window = Condition(rawValue: 2)
    public static let horizontal = Condition(rawValue: 4)
    public static let vertical = Condition(rawValue: 8)
    static func parse(_ text: String) throws -> Condition {
        switch text.lowercased() {
        case "", "none": return []
        case "taskbar": return .taskbar
        case "window": return .window
        case "horizontal": return [.horizontal, .taskbar]
        case "horizontal+", "horizontal+window": return [.horizontal, .taskbar, .window]
        case "vertical": return .vertical
        default: throw DefinitionError.invalid("Unknown condition \(text)")
        }
    }
}
public struct Transition {
    public let id: Int; public let weight: Int; public let condition: Condition
    public init(id: Int, weight: Int = 1, condition: Condition = []) { self.id = id; self.weight = weight; self.condition = condition }
    public static func choose(_ options: [Transition], at condition: Condition, random: inout SeededRandom) -> Int? {
        let eligible = options.filter { $0.weight > 0 && ($0.condition.isEmpty || !$0.condition.intersection(condition).isEmpty) }
        let sum = eligible.reduce(0) { $0 + $1.weight }; guard sum > 0 else { return nil }
        var ticket = random.integer(sum)
        for item in eligible { if ticket < item.weight { return item.id }; ticket -= item.weight }; return nil
    }
}
public struct Movement {
    public let x: Expression, y: Expression, interval: Expression, offsetY: Expression, opacity: Expression
    func evaluate(_ variables: [String: Double]) throws -> Values {
        try Values(x: Double(x.integer(variables)), y: Double(y.integer(variables)), interval: max(0.01, Double(interval.integer(variables))/1000), offsetY: Double(offsetY.integer(variables)), opacity: opacity.evaluate(variables))
    }
}
public struct Values {
    public var x: Double, y: Double, interval: Double, offsetY: Double, opacity: Double
    func interpolated(to end: Values, movementProgress: Double, visualProgress: Double) -> Values {
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b-a)*t }
        return Values(x: lerp(x,end.x,movementProgress), y: lerp(y,end.y,movementProgress), interval: lerp(interval,end.interval,visualProgress), offsetY: lerp(offsetY,end.offsetY,visualProgress).rounded(.towardZero), opacity: lerp(opacity,end.opacity,visualProgress))
    }
}
public struct Animation {
    public let id: Int, name: String, start: Movement, end: Movement
    public let frames: [Int], repeats: Expression, repeatFrom: Int, flipAtEnd: Bool
    public let next: [Transition], border: [Transition], gravity: [Transition]
    public func totalSteps(variables: [String: Double]) throws -> Int { frames.count + (frames.count-repeatFrom) * max(0, min(100_000, try repeats.integer(variables))) }
    public func frame(at step: Int) -> Int {
        frames[step < frames.count ? max(0,step) : repeatFrom + (step-frames.count) % (frames.count-repeatFrom)]
    }
}
public struct Spawn { public let weight: Int, x: Expression, y: Expression, next: [Transition] }
public struct Child { public let parentAnimation: Int, x: Expression, y: Expression, next: Int }
public enum DefinitionError: Error { case invalid(String) }
public struct Definition {
    public let animations: [Int: Animation], spawns: [Spawn], children: [Child], columns: Int, rows: Int
    public static func bundled() throws -> Definition { try Definition(data: Data(contentsOf: SheepResources.definitionURL)) }
    public init(data: Data) throws {
        let doc = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard let root = doc.rootElement(), let image = root.first("image"), let list = root.first("animations") else { throw DefinitionError.invalid("Missing root, image or animations") }
        columns = try image.integer("tilesx"); rows = try image.integer("tilesy")
        guard columns > 0, rows > 0 else { throw DefinitionError.invalid("Invalid atlas grid") }
        let frameCount = columns * rows
        var parsed: [Int: Animation] = [:]
        func transitions(_ node: XMLElement?) throws -> [Transition] {
            try (node?.elements(forName: "next") ?? []).map {
                guard let id = Int($0.stringValue ?? ""), let weight = Int($0.attribute(forName: "probability")?.stringValue ?? "1"), weight >= 0 else { throw DefinitionError.invalid("Invalid transition") }
                return Transition(id: id, weight: weight, condition: try Condition.parse($0.attribute(forName: "only")?.stringValue ?? "none"))
            }
        }
        func movement(_ node: XMLElement?) throws -> Movement {
            guard let node else { throw DefinitionError.invalid("Missing movement") }
            return try Movement(x: Expression(node.text("x", "0")), y: Expression(node.text("y", "0")), interval: Expression(node.text("interval", "100")), offsetY: Expression(node.text("offsety", "0")), opacity: Expression(node.text("opacity", "1")))
        }
        for a in list.elements(forName: "animation") {
            guard let id = Int(a.attribute(forName: "id")?.stringValue ?? ""), parsed[id] == nil, let seq = a.first("sequence") else { throw DefinitionError.invalid("Missing/duplicate animation ID or sequence") }
            let frames = try seq.elements(forName: "frame").map { e -> Int in
                guard let f = Int(e.stringValue ?? ""), f >= 0, f < frameCount else { throw DefinitionError.invalid("Invalid frame in \(id)") }; return f
            }
            let repeatFrom = Int(seq.attribute(forName: "repeatfrom")?.stringValue ?? "0") ?? -1
            guard !frames.isEmpty, frames.indices.contains(repeatFrom) else { throw DefinitionError.invalid("Invalid repeatfrom in \(id)") }
            let action = seq.text("action", "")
            guard action == "" || action == "flip" else { throw DefinitionError.invalid("Unknown action") }
            parsed[id] = try Animation(id: id, name: a.text("name", "\(id)"), start: movement(a.first("start")), end: movement(a.first("end")), frames: frames, repeats: Expression(seq.attribute(forName: "repeat")?.stringValue ?? "0"), repeatFrom: repeatFrom, flipAtEnd: action == "flip", next: transitions(seq), border: transitions(a.first("border")), gravity: transitions(a.first("gravity")))
        }
        animations = parsed
        spawns = try (root.first("spawns")?.elements(forName: "spawn") ?? []).map { s in
            guard let weight = Int(s.attribute(forName: "probability")?.stringValue ?? "1"), weight > 0 else { throw DefinitionError.invalid("Invalid spawn weight") }
            return try Spawn(weight: weight, x: Expression(s.text("x", "0")), y: Expression(s.text("y", "0")), next: transitions(s))
        }
        children = try (root.first("childs")?.elements(forName: "child") ?? []).map { c in
            guard let id = Int(c.attribute(forName: "animationid")?.stringValue ?? "") else { throw DefinitionError.invalid("Invalid child") }
            return try Child(parentAnimation: id, x: Expression(c.text("x", "0")), y: Expression(c.text("y", "0")), next: c.integer("next"))
        }
        guard !spawns.isEmpty, !parsed.isEmpty else { throw DefinitionError.invalid("Empty definition") }
        var refs: [Int] = []
        for a in parsed.values { refs += (a.next + a.border + a.gravity).map(\.id) }
        for s in spawns { refs += s.next.map(\.id) }
        for c in children { refs += [c.parentAnimation, c.next] }
        for id in refs where id != -1 { guard parsed[id] != nil else { throw DefinitionError.invalid("Unknown animation \(id)") } }
    }
}
private extension XMLElement {
    func first(_ name: String) -> XMLElement? { elements(forName: name).first }
    func text(_ name: String, _ fallback: String) -> String { first(name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback }
    func integer(_ name: String) throws -> Int { guard let n = Int(text(name, "")) else { throw DefinitionError.invalid("Missing integer \(name)") }; return n }
}
