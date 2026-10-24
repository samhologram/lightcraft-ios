import SwiftUI
@preconcurrency import LightCraftKit

/// The library grid: adaptive cells sized by `model.thumbSize`. Tap opens the photo in the loupe
/// (or toggles it in selection mode); long-press shows the photo menu.
struct PhotoGrid: View {
    let model: LibraryModel
    @Binding var selecting: Bool

    var body: some View {
        Group {
            if model.visible.isEmpty {
                ContentUnavailableView {
                    Label("No Photos", systemImage: "photo.on.rectangle")
                } description: {
                    Text("This source has no photos.")
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: max(60, model.thumbSize), maximum: max(60, model.thumbSize) * 1.6), spacing: 3)],
                        spacing: 3
                    ) {
                        ForEach(model.visible, id: \.self) { id in
                            PhotoCell(model: model, id: id, selecting: selecting)
                        }
                    }
                    .padding(3)
                }
            }
        }
        .desktopShortcuts(model: model)
        .multiFingerUndoRedo(model: model)
    }
}

struct PhotoCell: View {
    let model: LibraryModel
    let id: UInt64
    let selecting: Bool

    @State private var info: PhotoInfo?

    private var isSelected: Bool { model.state.selected.contains(id) }

    var body: some View {
        Button {
            if selecting {
                model.run("library.select", ["ids": [id], "mode": "toggle", "active": id])
            } else {
                model.open(id)
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { ThumbnailView(model: model, id: id, edge: max(60, model.thumbSize)) }
                .clipped()
                .overlay(alignment: .bottom) { badges }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .symbolRenderingMode(.palette)
                            // Kept: white glyph on a dark scrim over the photo.
                            .foregroundStyle(Color.white, isSelected ? Color.accentColor : Color.black.opacity(0.3))
                            .font(.title3)
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { PhotoContextMenu(model: model, id: id) }
        .accessibilityLabel(info?.fileName ?? "Photo \(id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("photo.\(id)")
        .onChange(of: model.state.revision, initial: true) { _, _ in
            info = model.handle.photoInfo(id: id)
        }
    }

    @ViewBuilder
    private var badges: some View {
        if let info, info.flag != "none" || info.rating > 0 || info.edited {
            // Kept: badges and legibility scrim over photo content, system colours.
            HStack(spacing: 4) {
                if info.flag == "pick" { Image(systemName: "flag.fill").foregroundStyle(.green) }
                if info.flag == "reject" { Image(systemName: "flag.slash.fill").foregroundStyle(.red) }
                if info.rating > 0 {
                    HStack(spacing: 0) {
                        Image(systemName: "star.fill")
                        Text(verbatim: "\(info.rating)").monospacedDigit()
                    }
                    .foregroundStyle(.yellow)
                }
                Spacer(minLength: 0)
                if info.edited { Image(systemName: "slider.horizontal.3").foregroundStyle(.white) }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45))
        }
    }
}

/// Context menu of a photo: rating, flag, rotate, Add to Album, Reset Edits, Delete.
/// The photo is selected first when it is not already part of the selection, so the engine's
/// selection-based commands act on exactly what the menu was opened on.
struct PhotoContextMenu: View {
    let model: LibraryModel
    let id: UInt64

    private var albums: [AlbumInfo] { model.albums.filter { $0.kind == "album" } }

    var body: some View {
        Menu {
            ForEach(0...5, id: \.self) { n in
                Button {
                    act("photo.rate", ["rating": n])
                } label: {
                    Label(n == 0 ? "No Rating" : "\(n) Star\(n == 1 ? "" : "s")", systemImage: n == 0 ? "star.slash" : "star")
                }
                .accessibilityIdentifier("command.photo.rate.\(n)")
            }
        } label: {
            Label("Rating", systemImage: "star")
        }
        Menu {
            Button { act("photo.pick") } label: { Label("Pick", systemImage: "flag.fill") }
                .accessibilityIdentifier("command.photo.pick")
            Button { act("photo.reject") } label: { Label("Reject", systemImage: "flag.slash.fill") }
                .accessibilityIdentifier("command.photo.reject")
            Button { act("photo.unflag") } label: { Label("Unflag", systemImage: "flag") }
                .accessibilityIdentifier("command.photo.unflag")
        } label: {
            Label("Flag", systemImage: "flag")
        }
        Divider()
        Button { act("photo.rotateLeft") } label: { Label("Rotate Left", systemImage: "rotate.left") }
            .accessibilityIdentifier("command.photo.rotateLeft")
        Button { act("photo.rotateRight") } label: { Label("Rotate Right", systemImage: "rotate.right") }
            .accessibilityIdentifier("command.photo.rotateRight")
        Divider()
        Menu {
            ForEach(albums, id: \.id) { album in
                Button {
                    act("album.addPhotos", ["id": album.id])
                } label: {
                    Text(verbatim: album.name)
                }
                .accessibilityIdentifier("command.album.addPhotos.\(album.id)")
            }
            if !albums.isEmpty { Divider() }
            Button {
                prepareSelection()
                model.present("album.create")
            } label: {
                Label("New Album…", systemImage: "plus")
            }
            .accessibilityIdentifier("command.album.create")
        } label: {
            Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
        }
        Button { act("develop.reset") } label: { Label("Reset Edits", systemImage: "arrow.counterclockwise") }
            .accessibilityIdentifier("command.develop.reset")
        Divider()
        Button { act("develop.copy", ids: false) } label: { Label("Copy Edit Settings", systemImage: "doc.on.doc") }
            .accessibilityIdentifier("command.develop.copy")
        Button { act("develop.paste") } label: { Label("Paste Edit Settings", systemImage: "doc.on.clipboard") }
            .disabled(!model.isEnabled("develop.paste"))
            .accessibilityIdentifier("command.develop.paste")
        Button {
            prepareSelection()
            model.showExport = true
        } label: { Label("Export / Share\u{2026}", systemImage: "square.and.arrow.up") }
            .accessibilityIdentifier("command.dialog.export")
        Divider()
        Button(role: .destructive) { act("photo.delete") } label: { Label("Delete", systemImage: "trash") }
            .accessibilityIdentifier("command.photo.delete")
    }

    private func prepareSelection() {
        if !model.state.selected.contains(id) { model.select(id) }
    }

    private func act(_ command: String, _ extra: [String: Any] = [:], ids: Bool = true) {
        prepareSelection()
        var params = extra
        if ids {
            let sel = model.state.selected
            params["ids"] = sel.contains(id) ? sel : [id]
        }
        model.run(command, params)
    }
}
