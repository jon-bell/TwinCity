import COracle
import Testing
import TwinCityCore

// Per-function differential gate against the original C, in process.
// The oracle keeps its state in C globals, so suites that touch it must be serialized.
@Suite(.serialized) struct RNGDifferential {
    static let seeds: [UInt32] = [0, 1, 2, 42, 0x7FFF_FFFF, 0xFFFF_FFFF, 631_152_000]
    static let ranges: [Int16] = [0, 1, 2, 3, 7, 9, 99, 255, 1000, 32766, 32767]

    @Test(arguments: seeds) func sim_rand(seed: UInt32) {
        sim_srand(seed)
        var g = ClassicLCG(seed: seed)
        for _ in 0..<10_000 { #expect(g.next16() == COracle.sim_rand()) }
    }

    @Test(arguments: seeds, ranges) func Rand(seed: UInt32, range: Int16) {
        sim_srand(seed)
        var g = ClassicLCG(seed: seed)
        for _ in 0..<2_000 { #expect(g.rand(range) == COracle.Rand(range)) }
    }

    @Test(arguments: seeds) func Rand16Signed(seed: UInt32) {
        sim_srand(seed)
        var g = ClassicLCG(seed: seed)
        for _ in 0..<5_000 { #expect(g.rand16Signed() == Int32(COracle.Rand16Signed())) }
    }

    /// Boundary gate. Random seeds almost never draw exactly `maxMultiple`, so a `>=`/`>`
    /// mutant in the rejection loop survived the tests above (measured 2026-10-03).
    /// Search for seeds whose first draw IS the boundary, then compare.
    @Test(arguments: [Int16(0), 1, 2, 9, 99, 1000, 32766])
    func RandAtRejectionBoundary(range: Int16) throws {
        let r = Int32(range &+ 1)
        let boundary = (0xFFFF / r) &* r
        let seed = try #require((UInt32(0)..<(1 << 24)).first { s in
            var g = ClassicLCG(seed: s); return g.next16() == boundary
        }, "no seed with first draw \(boundary)")
        sim_srand(seed)
        var g = ClassicLCG(seed: seed)
        for _ in 0..<50 { #expect(g.rand(range) == COracle.Rand(range)) }
    }
}
