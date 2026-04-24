//
//  File.swift
//
//
//  Created by ML Watson on 7/19/21.
// USING:
//
//  Storage.swift
//  EasyStash-iOS
//
//  Created by khoa on 27/05/2019.
//  Copyright © 2019 Khoa Pham. All rights reserved. MIT License. https://github.com/onmyway133/EasyStash
//

import Foundation

//      Mark's simple wrapper:


var storage: Storage? = nil

public func cacheStoreQuery(key: String, value: String) {
    do { try storage?.save(object: value, forKey: key) } catch {}
}
public func cacheLookupQuery7(key: String) -> String? {
    //do { try storage?.removeAll() } catch { print("ERROR CLEARING CACHE") } // DEBUG: clear cache
    do {
        return try storage?.load(forKey: key, as: String.self)
    } catch { return "" }
}




//       Some code from Khoa Pham's EasyStash projecty. License: MIT License

public struct ESOptions {
    /// By default, files are saved into searchPathDirectory/folder
    public var searchPathDirectory: FileManager.SearchPathDirectory
    public var folder: String = (Bundle.main.bundleIdentifier ?? "").appending("/Default")

    /// Optionally, you can set predefined directory for where to save files
    public var directoryUrl: URL? = nil

    public var encoder: JSONEncoder = JSONEncoder()
    public var decoder: JSONDecoder = JSONDecoder()

    public init() {
        #if os(tvOS)
        searchPathDirectory = .cachesDirectory
        #else
        searchPathDirectory = .applicationSupportDirectory
        #endif
    }
}

//
//  Storage.swift
//  EasyStash-iOS
//
//  Created by khoa on 27/05/2019.
//  Copyright © 2019 Khoa Pham. All rights reserved.
//

import Foundation

public enum StorageError: Error {
    case notFound
    case encodeData
    case decodeData
    case createFile
    case missingFileAttributeKey(key: FileAttributeKey)
    case expired(maxAge: Double)
}

public class Storage {
    public let cache = NSCache<NSString, AnyObject>()
    public let options: ESOptions
    public let folderUrl: URL
    public let fileManager: FileManager = .default

    public init(options: ESOptions) throws {
        self.options = options

        var url: URL
        if let directoryUrl = options.directoryUrl {
            url = directoryUrl
        } else {
            url = try fileManager.url(
                for: options.searchPathDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        self.folderUrl = url
            .appendingPathComponent(options.folder, isDirectory: true)

        try createDirectoryIfNeeded(folderUrl: folderUrl)
        try applyAttributesIfAny(folderUrl: folderUrl)
    }

    public func exists(forKey key: String) -> Bool {
        return fileManager.fileExists(atPath: fileUrl(forKey: key).path)
    }

    public func removeAll() throws {
        cache.removeAllObjects()
        try fileManager.removeItem(at: folderUrl)
        try createDirectoryIfNeeded(folderUrl: folderUrl)
    }

    public func remove(forKey key: String) throws {
        cache.removeObject(forKey: key as NSString)
        try fileManager.removeItem(at: fileUrl(forKey: key))
    }

    public func fileUrl(forKey key: String) -> URL {
        return folderUrl.appendingPathComponent(key, isDirectory: false)
    }
}

extension Storage {
    func createDirectoryIfNeeded(folderUrl: URL) throws {
        var isDirectory = ObjCBool(true)
        guard !fileManager.fileExists(atPath: folderUrl.path, isDirectory: &isDirectory) else {
            return
        }

        try fileManager.createDirectory(
            atPath: folderUrl.path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func applyAttributesIfAny(folderUrl: URL) throws {
        #if os(iOS) || os(tvOS)
            let attributes: [FileAttributeKey: Any] = [
                FileAttributeKey.protectionKey: FileProtectionType.complete
            ]

            try fileManager.setAttributes(attributes, ofItemAtPath: folderUrl.path)
        #endif
    }
    
    func verify(
        maxAge: TimeInterval,
        forKey key: String,
        fromDate date: @escaping (() -> Date) = { Date() }
    ) throws -> Bool {
        true
    }
}

extension Storage {
    func commonSave(object: AnyObject, forKey key: String, toData: () throws -> Data) throws {
        let data = try toData()
        cache.setObject(object, forKey: key as NSString)
        try fileManager
            .createFile(atPath: fileUrl(forKey: key).path, contents: data, attributes: nil)
            .trueOrThrow(StorageError.createFile)
    }

    func commonLoad<T>(forKey key: String,
                       withExpiry expiry: Expiry,
                       fromDate date: @escaping (() -> Date) = { Date() },
                       fromData: (Data) throws -> T) throws -> T {
        switch expiry {
        case .never:
            break
        case .maxAge(let maxAge):
            guard try verify(maxAge: maxAge, forKey: key, fromDate: date) else {
                throw StorageError.expired(maxAge: maxAge)
            }
        }
        
        if let object = cache.object(forKey: key as NSString) as? T {
            return object
        } else {
            let data = try Data(contentsOf: fileUrl(forKey: key))
            let object = try fromData(data)
            cache.setObject(object as AnyObject, forKey: key as NSString)
            return object
        }
    }
}

extension Storage {
    public enum Expiry {
        case never
        case maxAge(maxAge: TimeInterval)
    }
}

public extension Storage {
    func save<T: Codable>(object: T, forKey key: String) throws {
        let encoder = options.encoder
        try commonSave(object: object as AnyObject, forKey: key, toData: {
            do {
                return try encoder.encode(object)
            } catch {
                let typeWrapper = TypeWrapper(object: object)
                return try encoder.encode(typeWrapper)
            }
        })
    }

func load<T: Codable>(forKey key: String, as: T.Type, withExpiry expiry: Expiry = .never) throws -> T {
    // Remove the generic parameter from inner function since we can use T from outer scope
    func loadFromDisk(forKey key: String, as: T.Type) throws -> T {
        let data = try Data(contentsOf: fileUrl(forKey: key))
        let decoder = options.decoder

        do {
            let object = try decoder.decode(T.self, from: data)
            return object
        } catch {
            let typeWrapper = try decoder.decode(TypeWrapper<T>.self, from: data)
            return typeWrapper.object
        }
    }

    return try commonLoad(forKey: key, withExpiry: expiry, fromData: { data in
        return try loadFromDisk(forKey: key, as: T.self)
    })
  }
}

public extension Storage {
    func save(object: Data, forKey key: String) throws {
        try commonSave(object: object as AnyObject, forKey: key, toData: { object })
    }

    func load(forKey key: String, withExpiry expiry: Expiry = .never) throws -> Data {
        return try commonLoad(forKey: key, withExpiry: expiry, fromData: { $0 })
    }
}

#if canImport(UIKit)
import UIKit
public typealias Image = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias Image = NSImage
#endif

func unwrapOrThrow<T>(_ optional: Optional<T>, _ error: Error) throws -> T {
    if let value = optional {
        return value
    } else {
        throw error
    }
}

extension Bool {
    func trueOrThrow(_ error: Error) throws {
        if !self {
            throw error
        }
    }
}

/// Use to wrap primitive Codable
public struct TypeWrapper<T: Codable>: Codable {
    enum CodingKeys: String, CodingKey {
        case object
    }

    public let object: T

    public init(object: T) {
        self.object = object
    }
}

class Utils {
    static func image(data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #else
        return nil
        #endif
    }

    static func data(image: Image) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: 0.9)
        #elseif canImport(AppKit)
        return image.tiffRepresentation
        #else
        return nil
        #endif
    }
}

public struct File {
    public let name: String
    public let url: URL
    public let modificationDate: Date?
    public let size: UInt64?
}


