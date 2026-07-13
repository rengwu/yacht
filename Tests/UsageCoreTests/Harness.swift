import Foundation

/// Minimal assert harness. XCTest ships with Xcode, and this machine has
/// Command Line Tools only, so tests are a plain executable: `swift run UsageCoreTests`.
final class Harness {
    private(set) var passed = 0
    private(set) var failures: [String] = []

    func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else { failures.append(name) }
    }

    func checkEqual<T: Equatable>(_ a: T, _ b: T, _ name: String) {
        check(a == b, "\(name)  (\(a) != \(b))")
    }

    func checkThrows<E: Error & Equatable>(_ expected: E, _ name: String, _ body: () throws -> Void) {
        do {
            try body()
            failures.append("\(name)  (did not throw)")
        } catch let error as E where error == expected {
            passed += 1
        } catch {
            failures.append("\(name)  (threw \(error))")
        }
    }

    /// Prints the summary and exits nonzero on any failure.
    func finish() -> Never {
        for f in failures { print("FAIL: \(f)") }
        print("----")
        print("pass: \(passed)  fail: \(failures.count)")
        exit(failures.isEmpty ? 0 : 1)
    }
}
