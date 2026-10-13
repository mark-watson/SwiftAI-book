import CoreML
import Foundation

public enum ModelStoreError: Error, CustomStringConvertible {
    case missing(URL)

    public var description: String {
        switch self {
        case .missing(let url):
            "Model not found at \(url.path). Run `uv run python/make_models.py` and `swift run TrainModels` first."
        }
    }
}

/// Compiles .mlmodel and .mlpackage files to .mlmodelc once and caches the result.
///
/// Xcode compiles models at build time. A Swift package command line tool
/// has no such step, so we call `MLModel.compileModel(at:)` ourselves and keep
/// the compiled bundle in models/compiled.
public enum ModelStore {
    public static func compiledURL(for source: URL) async throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw ModelStoreError.missing(source) }

        let cacheDir = Paths.models.appending(path: "compiled")
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent
        let cached = cacheDir.appending(path: "\(name).mlmodelc")

        if let cachedDate = modificationDate(cached), let sourceDate = modificationDate(source),
           cachedDate >= sourceDate {
            return cached
        }
        let temporary = try await MLModel.compileModel(at: source)
        _ = try? fm.removeItem(at: cached)
        try fm.moveItem(at: temporary, to: cached)
        return cached
    }

    public static func load(_ fileName: String,
                            computeUnits: MLComputeUnits = .all,
                            functionName: String? = nil) async throws -> MLModel {
        let url = try await compiledURL(for: Paths.model(fileName))
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        config.functionName = functionName
        return try await MLModel.load(contentsOf: url, configuration: config)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
