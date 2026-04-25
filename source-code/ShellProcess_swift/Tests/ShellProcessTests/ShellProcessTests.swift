import XCTest
@testable import ShellProcess_swift

final class ShellProcessTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        print("** s1:")
        let s1 = run_in_shell(commandPath: "/bin/ps", argList: ["a"])
        print(s1)
        let s2 = run_in_shell(commandPath: "/bin/ls", argList: ["."])
        print("** s2:")
        print(s2)
        let s3 = run_in_shell(commandPath: "/bin/sleep", argList: ["2"])
        print("** s3:")
        print(s3)

    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
