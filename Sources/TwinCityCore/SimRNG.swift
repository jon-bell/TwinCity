/// The simulation's only source of randomness.
///
/// Deliberately **not** `RandomNumberGenerator`: stdlib APIs that accept one
/// (`.random(in:using:)`, `shuffled(using:)`) consume draws in undocumented patterns,
/// and the port must match the original draw for draw.
public protocol SimRNG {
    /// One raw draw, `0...0xFFFF`. C: `sim_rand()` (rand.c).
    mutating func next16() -> Int32
}

/// The original generator: `next = next * 1103515245 + 12345`, bits 8–23.
/// C: `static unsigned QUAD next = 1` in rand.c; `QUAD` is `int` under `-DOSF1` (the spec).
public struct ClassicLCG: SimRNG, Sendable {
    public private(set) var state: UInt32

    /// C: `sim_srand(seed)`.
    public init(seed: UInt32 = 1) { state = seed }

    public mutating func next16() -> Int32 {
        state = state &* 1_103_515_245 &+ 12_345
        return Int32((state % 0x100_0000) >> 8)
    }
}

extension SimRNG {
    /// C: `Rand16()` (s_sim.c).
    public mutating func rand16() -> Int32 { next16() }

    /// C: `Rand16Signed()` (s_sim.c).
    public mutating func rand16Signed() -> Int32 {
        let i = next16()
        return i > 32767 ? 32767 - i : i
    }

    /// C: `short Rand(short range)` (s_sim.c), rejection sampling over `0...range`.
    ///
    /// Reproduced exactly, including `range++` on a `short`: `rand(32767)` wraps the
    /// range to -32768, and the C then returns values in `0..<32768`. That conversion is
    /// implementation-defined in C (gcc wraps), not undefined, so it is behaviour.
    public mutating func rand(_ range: Int16) -> Int16 {
        let r = Int32(range &+ 1)
        let maxMultiple = (0xFFFF / r) &* r
        var rnum: Int32
        repeat { rnum = next16() } while rnum >= maxMultiple
        return Int16(truncatingIfNeeded: rnum % r)
    }
}
