import Foundation

/// File locations shared by all executables. Paths are resolved from this
/// source file so `swift run` works from any working directory.
public enum Paths {
    public static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MLSupport
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()

    public static let models = packageRoot.appending(path: "models")
    public static let training = packageRoot.appending(path: "training")
    public static let sharedData = packageRoot.deletingLastPathComponent().appending(path: "data")

    public static func model(_ name: String) -> URL {
        models.appending(path: name)
    }
}
