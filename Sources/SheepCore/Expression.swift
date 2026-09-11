import Foundation

/// The arithmetic subset used by the pinned definition. No script execution or external lookups.
public struct Expression: Equatable {
    public let source: String
    private let node: Node
    private indirect enum Node: Equatable {
        case number(Double), variable(String), negate(Node), binary(Character, Node, Node), convert(Node)
        func value(_ variables: [String: Double]) throws -> Double {
            switch self {
            case .number(let n): return n
            case .variable(let name): guard let n = variables[name] else { throw Failure.invalid("Unknown variable: \(name)") }; return n
            case .negate(let n): return try -n.value(variables)
            case .convert(let n): return try n.value(variables).rounded(.toNearestOrEven)
            case .binary(let op, let a, let b):
                let x = try a.value(variables), y = try b.value(variables)
                switch op {
                case "+": return x+y
                case "-": return x-y
                case "*": return x*y
                case "/": guard y != 0 else { throw Failure.invalid("Division by zero") }; return x/y
                case "%": guard y != 0 else { throw Failure.invalid("Remainder by zero") }; return x.truncatingRemainder(dividingBy: y)
                default: throw Failure.invalid("Unknown operator")
                }
            }
        }
    }
    public enum Failure: Error, CustomStringConvertible { case invalid(String)
        public var description: String { if case .invalid(let s) = self { return s }; return "Invalid expression" }
    }
    public init(_ source: String) throws {
        self.source = source
        var parser = Parser(chars: Array(source))
        node = try parser.expression()
        _ = parser.peek
        guard parser.index == parser.chars.count else { throw Failure.invalid("Trailing expression: \(source)") }
    }
    public func evaluate(_ variables: [String: Double] = [:]) throws -> Double {
        let n = try node.value(variables)
        guard n.isFinite, abs(n) <= 1e12 else { throw Failure.invalid("Non-finite or excessive result: \(source)") }; return n
    }
    public func integer(_ variables: [String: Double] = [:]) throws -> Int { Int(try evaluate(variables)) }
    private struct Parser {
        let chars: [Character]; var index = 0
        var peek: Character? { mutating get { while index < chars.count && chars[index].isWhitespace { index += 1 }; return index < chars.count ? chars[index] : nil } }
        mutating func consume(_ c: Character) -> Bool { if peek == c { index += 1; return true }; return false }
        mutating func expression() throws -> Node {
            var n = try term()
            while let c = peek, c == "+" || c == "-" { index += 1; n = .binary(c, n, try term()) }; return n
        }
        mutating func term() throws -> Node {
            var n = try atom()
            while let c = peek, c == "*" || c == "/" || c == "%" { index += 1; n = .binary(c, n, try atom()) }; return n
        }
        mutating func atom() throws -> Node {
            if consume("-") { return .negate(try atom()) }
            if consume("+") { return try atom() }
            if consume("(") { let n = try expression(); guard consume(")") else { throw Failure.invalid("Missing )") }; return n }
            guard let c = peek else { throw Failure.invalid("Missing operand") }
            let start = index
            if c.isNumber || c == "." {
                while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
                guard let n = Double(String(chars[start..<index])) else { throw Failure.invalid("Invalid number") }; return .number(n)
            }
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "." || chars[index] == "_" { index += 1 }
            guard index > start else { throw Failure.invalid("Unexpected character: \(c)") }
            let name = String(chars[start..<index])
            if name == "Convert" {
                guard consume("(") else { throw Failure.invalid("Missing Convert (") }
                let n = try expression()
                guard consume(",") else { throw Failure.invalid("Missing Convert type") }
                let typeStart = index
                while let p = peek, p != ")" { index += 1 }
                guard String(chars[typeStart..<index]) == "System.Int32", consume(")") else { throw Failure.invalid("Unsupported Convert type") }
                return .convert(n)
            }
            guard ["screenW", "screenH", "areaW", "areaH", "imageW", "imageH", "imageX", "imageY", "random", "randS", "scale"].contains(name) else { throw Failure.invalid("Unknown variable: \(name)") }
            return .variable(name)
        }
    }
}

public struct SeededRandom {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func integer(_ upper: Int) -> Int { Int(next() % UInt64(max(1, upper))) }
}
