# Swift Command Line Utilities

This chapter contains example code and utilities for writing command line programs, using external shell processes, and using the FileIO library.

## Using Shell Processes

The library for using shell processes is one of my GitHub projects so you can include it in other projects using:

{lang="swift",linenos=on}
~~~~~~~~
 dependencies: [
   .package(url: "git@github.com:mark-watson/ShellProcess_swift.git", .branch("main")),
 ],
~~~~~~~~


{lang="swift",linenos=on}
~~~~~~~~
import Foundation

@available(OSX 10.13, *)
public func run_in_shell(commandPath: String, argList: [String] = []) -> String {
    let task = Process()
    //task.launchPath = command
    task.executableURL = URL(fileURLWithPath: commandPath)
    task.arguments = argList
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
        try! task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String? = String(data: data, encoding: String.Encoding.utf8)
        if let output = output {
          if !output.isEmpty {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
          }
        }
    }
    return ""
}
~~~~~~~~




{lang="swift",linenos=on}
~~~~~~~~
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
~~~~~~~~


The test output (with some text removed for brevity) is:

{lang="swift",linenos=on}
~~~~~~~~
$ swift test
Test Suite 'All tests' started at 2021-08-06 16:36:21.447
** s1:
PID   TT  STAT      TIME COMMAND
 3898 s000  Ss     0:00.01 login -pf markw8
 3899 s000  S+     0:00.18 -zsh
 3999 s001  Ss     0:00.02 login -pfl markw8 /bin/bash -c exec -la zsh /bin/zsh
 4000 s001  S+     0:00.38 -zsh
 5760 s002  Ss     0:00.02 login -pfl markw8 /bin/bash -c exec -la zsh /bin/zsh
 5761 s002  S      0:00.14 -zsh
 8654 s002  S+     0:00.06 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-test
 8665 s002  S      0:00.03 /Applications/Xcode.app/Contents/Developer/usr/bin/xctest /Users/markw_1/GIT_swift_book/ShellProcess_swift/.build/arm64-apple-macosx/debug/ShellProcess_swiftPackageTests.xctest
 8666 s002  R      0:00.00 /bin/ps a
** s2:
Package.swift
README.md
Sources
Tests
** s3:

Test Suite 'All tests' passed at 2021-08-06 16:36:23.468.
	 Executed 1 test, with 0 failures (0 unexpected) in 2.019 (2.021) seconds
~~~~~~~~



## FileIO Examples




{lang="swift",linenos=on}
~~~~~~~~
import Foundation
import ShellProcess_swift

@available(OSX 10.13, *)
func test_files_demo() -> Void {
    // In order to append to an existing file, you need to get a file handle
    // and seek to the end of a file. The following will not work:
    let s = "the dog chased the cat\n"
    try! s.write(toFile: "out.txt", atomically: true, encoding: String.Encoding.ascii)
    let s2 = "a second string\n"
    try! s2.write(toFile: "out.txt", atomically: true, encoding: String.Encoding.ascii)
    let aString = try! String(contentsOfFile: "out.txt")
    print(aString)

    // For simple use cases, simply appending strings, then writing
    // the result atomically works fine:
    var s3 = "the dog chased the cat\n"
    s3 += "a second string\n"
    try! s3.write(toFile: "out2.txt", atomically: true, encoding: String.Encoding.ascii)
    let aString2 = try! String(contentsOfFile: "out2.txt")
    print(aString2)

    // list files in current directory:
    let ls = run_in_shell(commandPath: "/bin/ls", argList: ["."])
    print(ls)

    // remove two temnporary files:
    let shellOutput = run_in_shell(commandPath: "/bin/rm", argList: ["out.txt", "out2.txt"])
    print(shellOutput)
}

if #available(OSX 10.13, *) {
    test_files_demo()
}
~~~~~~~~


{lang="swift",linenos=on}
~~~~~~~~
$ swift run
Fetching git@github.com:mark-watson/ShellProcess_swift.git from cache
Cloning git@github.com:mark-watson/ShellProcess_swift.git
Resolving git@github.com:mark-watson/ShellProcess_swift.git at main
[5/5] Build complete!
a second string

the dog chased the cat
a second string

Package.resolved
Package.swift
README.md
Sources
out.txt
out2.txt
~~~~~~~~



{lang="swift",linenos=on}
~~~~~~~~

~~~~~~~~

