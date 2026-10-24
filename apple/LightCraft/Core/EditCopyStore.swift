import CryptoKit
import Foundation

/// One app-owned source copy plus re-editable settings. The Photos asset is never a write target.
struct EditCopyRecord: Codable, Equatable {
    let sourceID: String
    let settingsJSON: String
    let edited: Bool
}

enum EditCopyStore {
    static let settingsName = "Settings.lightcraft.json"

    /// A readable source prefix and a hash keep Photos identifiers with punctuation distinct.
    static func folder(for sourceID: String, under root: URL) -> URL {
        let readable = String(sourceID.prefix(48).map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let hash = SHA256.hash(data: Data(sourceID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(readable)-\(hash)", isDirectory: true)
    }

    static func settingsURL(in folder: URL) -> URL { folder.appendingPathComponent(settingsName) }

    static func sourceFile(in folder: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.first {
            $0.lastPathComponent != settingsName && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
    }

    static func record(in folder: URL) -> EditCopyRecord? {
        guard let data = try? Data(contentsOf: settingsURL(in: folder)) else { return nil }
        return try? JSONDecoder().decode(EditCopyRecord.self, from: data)
    }

    static func save(_ record: EditCopyRecord, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: settingsURL(in: folder), options: .atomic)
    }

    /// Promote a read-only cached original into the user's app folder without modifying the source.
    static func copySource(_ source: URL, into folder: URL) throws -> URL {
        if let existing = sourceFile(in: folder) { return existing }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        let staging = folder.appendingPathComponent(".copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        if let existing = sourceFile(in: folder) { return existing }
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }
}
