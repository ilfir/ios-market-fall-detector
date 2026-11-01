// Minimal stand-in for XCTest, used only by scripts/run-tests.sh on machines that
// have the Command Line Tools but no Xcode. In Xcode the real XCTest is used.
@_exported import Foundation

open class XCTestCase {
    public required init() {}
    open func setUp() {}
    open func tearDown() {}
}

public enum XCTestShim {
    public static var failures: [String] = []
    static func fail(_ message: String, _ file: StaticString, _ line: UInt) {
        failures.append("\((("\(file)") as NSString).lastPathComponent):\(line): \(message)")
    }
}

public struct XCTUnwrapError: Error {}

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTestShim.fail("XCTFail \(message)", file, line)
}

public func XCTAssertTrue(_ expr: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    if (try? expr()) != true { XCTestShim.fail("XCTAssertTrue failed \(message())", file, line) }
}

public func XCTAssertFalse(_ expr: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    if (try? expr()) != false { XCTestShim.fail("XCTAssertFalse failed \(message())", file, line) }
}

public func XCTAssertNil<T>(_ expr: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    if let v = try? expr() { XCTestShim.fail("XCTAssertNil failed: \(v) \(message())", file, line) }
}

public func XCTAssertNotNil<T>(_ expr: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    if (try? expr()) == nil { XCTestShim.fail("XCTAssertNotNil failed \(message())", file, line) }
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        if x != y { XCTestShim.fail("XCTAssertEqual failed: (\(x)) is not equal to (\(y)) \(message())", file, line) }
    } catch { XCTestShim.fail("threw \(error)", file, line) }
}

public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                             accuracy: T, _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        if abs(x - y) > accuracy { XCTestShim.fail("XCTAssertEqual failed: (\(x)) is not equal to (\(y)) +/- \(accuracy) \(message())", file, line) }
    } catch { XCTestShim.fail("threw \(error)", file, line) }
}

public func XCTUnwrap<T>(_ expr: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let v = try expr() else { XCTestShim.fail("XCTUnwrap failed", file, line); throw XCTUnwrapError() }
    return v
}

public func runShimTests<T: XCTestCase>(_ type: T.Type, _ tests: [(String, (T) -> () async throws -> Void)]) async -> (Int, Int) {
    var failed = 0
    for (name, test) in tests {
        let before = XCTestShim.failures.count
        let instance = T()
        instance.setUp()
        do { try await test(instance)() } catch { XCTestShim.failures.append("\(name) threw \(error)") }
        instance.tearDown()
        let newFailures = XCTestShim.failures[before...]
        if newFailures.isEmpty {
            print("  ✓ \(T.self).\(name)")
        } else {
            failed += 1
            print("  ✗ \(T.self).\(name)")
            newFailures.forEach { print("      \($0)") }
        }
    }
    return (tests.count, failed)
}
