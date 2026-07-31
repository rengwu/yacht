// UsageCore test runner: `swift run UsageCoreTests`.
// (Executable, not XCTest — this machine has Command Line Tools only.)

let t = Harness()
runInstallerTests(t)
runDisplayTests(t)
runConfigTests(t)
runKimiProviderTests(t)
runStaleFigureTests(t)
t.finish()
