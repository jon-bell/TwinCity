import Testing
@testable import TwinCityCore

// Golden values produced by the original rand.c/s_sim.c code (gcc -std=gnu89 -fwrapv,
// QUAD=int). These pin the port without needing the oracle; the oracle-backed suite in
// OracleDifferentialTests checks the same functions across many seeds and ranges.
@Suite struct SimRNGGolden {
    @Test func rawSequenceFromDefaultSeed() {
        var g = ClassicLCG()
        #expect((0..<8).map { _ in g.next16() } == [50814, 32432, 33252, 27547, 19423, 64372, 58038, 64430])
    }

    @Test func randSmallRange() {
        var g = ClassicLCG(seed: 42)
        #expect((0..<8).map { _ in g.rand(9) } == [6, 9, 9, 6, 4, 3, 5, 8])
    }

    @Test func randWrapsShortRange() {
        // range++ on 32767 wraps to -32768 in the C; results stay in 0..<32768.
        var g = ClassicLCG(seed: 7)
        #expect((0..<4).map { _ in g.rand(32767) } == [27733, 20047, 29776, 5008])
    }
}
