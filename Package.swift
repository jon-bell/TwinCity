// swift-tools-version: 6.0
import PackageDescription

// TwinCityCore is the port. It depends on NOTHING: no Foundation, no Glibc/Darwin, no C.
// `scripts/check-core-purity.sh` enforces that in CI. The C oracle is linked only into the
// differential test target, and only when TWINCITY_ORACLE=1 (build it first with
// oracle/build-headless.sh). Shipping a Swift wrapper over the C would be the transpiler
// route: faithful because it is still C. See docs/DESIGN.md.

let oracleEnabled = Context.environment["TWINCITY_ORACLE"] == "1"
let oracleLib = Context.packageDirectory + "/oracle/build/headless"

var targets: [Target] = [
    .target(
        name: "TwinCityCore",
        dependencies: [],
        swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
    ),
    .testTarget(name: "TwinCityCoreTests", dependencies: ["TwinCityCore"]),
]

if oracleEnabled {
    targets += [
        .systemLibrary(name: "COracle", path: "Sources/COracle"),
        .testTarget(
            name: "OracleDifferentialTests",
            dependencies: ["TwinCityCore", "COracle"],
            linkerSettings: [.unsafeFlags([
                "-L", oracleLib, "-loracle", "-lm",
                "-Xlinker", "--wrap=gettimeofday", "-Xlinker", "--wrap=sim_rand",
            ])]
        ),
    ]
}

let package = Package(
    name: "TwinCity",
    products: [.library(name: "TwinCityCore", targets: ["TwinCityCore"])],
    targets: targets
)
