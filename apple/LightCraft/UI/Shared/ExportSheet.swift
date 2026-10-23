import SwiftUI
@preconcurrency import LightCraftKit

private struct ExportJob: Sendable {
    let id: UInt64
    let name: String
    let longEdge: UInt32
    let quality: UInt32
}

/// Export the selection (or the active photo) as JPEG through the engine, then hand the files to
/// the system share sheet (AirDrop, Save to Files, Save Image, Mail…).
struct ExportSheet: View {
    let model: LibraryModel

    @Environment(\.dismiss) private var dismiss
    @State private var sizeChoice = 0
    @State private var quality = 90.0
    @State private var working = false
    @State private var files: [URL] = []
    @State private var errorText: String?
    @State private var savedText: String?
    @State private var saving = false

    private static let sizes: [(title: String, edge: UInt32?)] = [
        ("Original size", nil), ("Large (4096 px)", 4096), ("Medium (2048 px)", 2048), ("Web (1200 px)", 1200),
    ]

    private var targets: [UInt64] {
        if !model.state.selected.isEmpty { return model.state.selected }
        return model.state.active.map { [$0] } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Size", selection: $sizeChoice) {
                        ForEach(Self.sizes.indices, id: \.self) { i in
                            Text(verbatim: Self.sizes[i].title).tag(i)
                        }
                    }
                    .accessibilityIdentifier("export.size")
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Quality")
                            Spacer()
                            Text(verbatim: "\(Int(quality))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $quality, in: 50...100, step: 1)
                            .accessibilityIdentifier("export.quality")
                    }
                } header: {
                    Text("JPEG")
                } footer: {
                    Text("\(targets.count) photo\(targets.count == 1 ? "" : "s") will be exported with their edits.")
                }
                if let errorText {
                    Section {
                        // Kept: semantic error colour.
                        Text(verbatim: errorText).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section {
                    if files.isEmpty {
                        Button {
                            Task { await export() }
                        } label: {
                            if working {
                                HStack { ProgressView(); Text("Exporting…") }
                            } else {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(working || targets.isEmpty)
                        .accessibilityIdentifier("export.run")
                    } else {
                        ShareLink(items: files) {
                            Label("Share \(files.count) JPEG\(files.count == 1 ? "" : "s")", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export.share")
                        Button {
                            Task { await saveToPhotos() }
                        } label: {
                            if saving {
                                HStack { ProgressView(); Text("Saving…") }
                            } else {
                                Label("Save Copy to Photos", systemImage: "photo.badge.plus")
                            }
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("export.saveToPhotos")
                        if let savedText {
                            Label(savedText, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green) // Kept: semantic success colour.
                                .accessibilityIdentifier("export.saved")
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("export.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: sizeChoice) { _, _ in files = []; savedText = nil }
        .onChange(of: quality) { _, _ in files = []; savedText = nil }
    }

    private func saveToPhotos() async {
        errorText = nil
        saving = true
        defer { saving = false }
        do {
            try await model.photos.saveCopies(files)
            savedText = "Saved \(files.count) cop\(files.count == 1 ? "y" : "ies") to Photos"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func export() async {
        errorText = nil
        working = true
        defer { working = false }
        let edge = Self.sizes[sizeChoice].edge
        let q = UInt32(quality)
        var jobs: [ExportJob] = []
        for id in targets {
            guard let info = model.handle.photoInfo(id: id) else { continue }
            let long = edge ?? max(info.width, info.height)
            let base = (info.fileName as NSString).deletingPathExtension
            jobs.append(ExportJob(id: id, name: base.isEmpty ? "photo-\(id)" : base, longEdge: long, quality: q))
        }
        let handle = model.handle
        do {
            let urls = try await Task.detached(priority: .userInitiated) { () -> [URL] in
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LightCraftExport-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var out: [URL] = []
                var used = Set<String>()
                for job in jobs {
                    let data = try handle.exportJpeg(id: job.id, longEdge: job.longEdge, quality: job.quality)
                    var name = job.name
                    if !used.insert(name).inserted { name = "\(name)-\(job.id)"; used.insert(name) }
                    let url = folder.appendingPathComponent(name).appendingPathExtension("jpg")
                    try data.write(to: url, options: .atomic)
                    out.append(url)
                }
                return out
            }.value
            files = urls
        } catch {
            errorText = error.localizedDescription
        }
    }
}
