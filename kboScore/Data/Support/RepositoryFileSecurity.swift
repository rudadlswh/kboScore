//
//  RepositoryFileSecurity.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

enum RepositoryFileSecurity {
    nonisolated static let protectionType = FileProtectionType.completeUntilFirstUserAuthentication

    nonisolated static func applyProtection(
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: fileURL.path
        )
    }

    nonisolated static func applyProtection(
        toDirectory directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.protectionKey: protectionType],
            ofItemAtPath: directoryURL.path
        )
    }

    nonisolated static func excludeFromBackup(_ fileURL: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableFileURL = fileURL
        try mutableFileURL.setResourceValues(resourceValues)
    }
}
