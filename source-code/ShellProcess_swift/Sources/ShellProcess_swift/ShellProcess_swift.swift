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
