import SwiftUI
@preconcurrency import LightCraftKit

/// Versions: named snapshots of the active photo's edit settings.
struct VersionsPanel: View {
    let model: LibraryModel

    private struct VersionRow: Identifiable {
        let id: Int
        let name: String
        let created: String
    }

    @State private var versions: [VersionRow] = []
    @State private var renaming: VersionRow?
    @State private var newName = ""

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to save versions of its edit.")
        } else {
            VStack(spacing: 0) {
                if versions.isEmpty {
                    PanelEmptyState(title: "No Versions", symbol: "square.on.square", message: "Create a version to return to this edit later.")
                } else {
                    List(versions) { v in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: v.name).font(.subheadline.weight(.medium))
                                Text(verbatim: v.created).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Menu {
                                Button { model.run("version.restore", ["index": v.id]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                    .accessibilityIdentifier("command.version.restore")
                                Button { model.run("version.update", ["index": v.id]) } label: { Label("Update with Current Edit", systemImage: "arrow.triangle.2.circlepath") }
                                    .accessibilityIdentifier("command.version.update")
                                Button {
                                    newName = v.name
                                    renaming = v
                                } label: { Label("Rename", systemImage: "pencil") }
                                    .accessibilityIdentifier("command.version.rename")
                                Button(role: .destructive) { model.run("version.delete", ["index": v.id]) } label: { Label("Delete", systemImage: "trash") }
                                    .accessibilityIdentifier("command.version.delete")
                            } label: {
                                Label("Version Options", systemImage: "ellipsis.circle").labelStyle(.iconOnly).frame(width: 34, height: 34)
                            }
                            .accessibilityLabel("Version Options")
                            .accessibilityIdentifier("version.menu.\(v.id)")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.run("version.restore", ["index": v.id]) }
                        .accessibilityIdentifier("version.\(v.id)")
                    }
                    .listStyle(.plain)
                }
            }
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: model.state.active) { _, _ in reload() }
            .alert("Rename Version", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let v = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        model.run("version.rename", ["index": v.id, "name": newName])
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func reload() {
        guard let h = EngineQuery.json(model, "history.list") as? [String: Any],
              let list = h["versions"] as? [[String: Any]] else {
            versions = []
            return
        }
        versions = list.enumerated().map { i, v in
            VersionRow(id: i, name: (v["name"] as? String) ?? "Version \(i + 1)", created: (v["created"] as? String) ?? "")
        }
    }
}
