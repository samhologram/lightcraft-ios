import Foundation
import UniformTypeIdentifiers
@preconcurrency import LightCraftKit

/// Import of Lightroom presets, LUT profiles and LightCraft preset packs (`file.importPresets`):
/// mirrors the desktop split (`.cube`, `.zip` and folders also go to `profile.import`; everything but
/// `.cube` goes to `preset.import`) and reports one summary.
extension LibraryModel {
    static let presetExtensions = ["xmp", "lrtemplate", "zip", "dng", "lmp", "mplumpack", "cube", "lcpreset", "lceffect"]

    /// Content types the preset picker accepts (extensions the system does not know are declared as data
    /// with that filename extension).
    static var presetContentTypes: [UTType] {
        var types = presetExtensions.compactMap { UTType(filenameExtension: $0) }
        if let own = UTType("ca.hologram.lightcraft.presetfile") { types.append(own) }
        types.append(.folder)
        return types
    }

    static func isPresetFile(_ url: URL) -> Bool {
        presetExtensions.contains(url.pathExtension.lowercased())
    }

    /// Copies the picked items (security scoped) into a temp folder, imports them and shows the summary
    /// in `lastNotice`. Returns the summary text.
    @discardableResult
    func importPresets(_ urls: [URL]) async -> String {
        guard !urls.isEmpty else { return "" }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightCraftPresets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var copied: [URL] = []
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (i, url) in urls.enumerated() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let sub = folder.appendingPathComponent("\(i)", isDirectory: true)
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                let dest = sub.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: dest)
                copied.append(dest)
            }
        } catch {
            lastError = error.localizedDescription
            return ""
        }
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let lutPaths = copied.filter { ["cube", "zip"].contains($0.pathExtension.lowercased()) || isDir($0) }.map(\.path)
        let presetPaths = copied.filter { $0.pathExtension.lowercased() != "cube" }.map(\.path)
        let handle = self.handle
        let outcome: (profiles: String?, presets: String?, errors: [String]) = await Task.detached(priority: .userInitiated) {
            func call(_ id: String, _ paths: [String]) -> Result<String, Error> {
                Result {
                    let json = LibraryModel.encode(["paths": paths]) ?? "{}"
                    return try handle.execute(id: id, paramsJson: json)
                }
            }
            var errors: [String] = []
            var profiles: String?
            var presets: String?
            if !lutPaths.isEmpty {
                switch call("profile.import", lutPaths) {
                case .success(let v): profiles = v
                case .failure(let e): errors.append(e.localizedDescription)
                }
            }
            if !presetPaths.isEmpty {
                switch call("preset.import", presetPaths) {
                case .success(let v): presets = v
                case .failure(let e): errors.append(e.localizedDescription)
                }
            }
            return (profiles, presets, errors)
        }.value
        refresh()
        let summary = Self.presetSummary(profiles: outcome.profiles.flatMap(Self.decodeObject), presets: outcome.presets.flatMap(Self.decodeObject), errors: outcome.errors)
        presetImportTick += 1
        lastNotice = summary
        return summary
    }

    private static func presetSummary(profiles: [String: Any]?, presets: [String: Any]?, errors: [String]) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        func failures(_ v: [String: Any]?) -> [String] {
            (v?["failed"] as? [[Any]] ?? []).map { f in
                let name = (f.first as? String) ?? ""
                let reason = f.count > 1 ? ((f[1] as? String) ?? "") : ""
                return "\(name): \(reason)"
            }
        }
        var lines: [String] = []
        let nProfiles = (profiles?["imported"] as? [Any])?.count ?? 0
        let imported = presets?["imported"] as? [[String: Any]] ?? []
        let effects = presets?["effects"] as? [[String: Any]] ?? []
        let nPresets = imported.count
        if nPresets > 0 { lines.append("Imported \(plural(nPresets, "preset"))") }
        if nProfiles > 0 { lines.append("Imported \(plural(nProfiles, "profile"))") }
        if !effects.isEmpty { lines.append("Imported \(plural(effects.count, "mask effect")) (Masking ▸ Effect)") }
        var skipped = Set<String>()
        for row in imported { for u in row["unmapped"] as? [String] ?? [] { skipped.insert(u) } }
        if !skipped.isEmpty { lines.append("Not carried over: " + skipped.sorted().joined(separator: ", ")) }
        let problems = failures(presets) + failures(profiles) + errors
        if !problems.isEmpty { lines.append("\(plural(problems.count, "file")) failed:\n" + problems.joined(separator: "\n")) }
        if lines.isEmpty { lines.append("No new presets") }
        return lines.joined(separator: "\n")
    }
}
