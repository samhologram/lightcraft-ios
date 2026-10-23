import SwiftUI
@preconcurrency import LightCraftKit

/// iPad layout: sidebar (sources) + detail. The detail is the library grid or, for a photo, the loupe
/// with a trailing panel switcher, an inspector column, the filmstrip and the rating / flag bar.
/// (`LibraryRootView` falls back to the iPhone layout when the window is narrower than 700 pt.)
struct PadLibraryView: View {
    @Bindable var model: LibraryModel

    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var selecting = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            AlbumSidebar(model: model)
        } detail: {
            Group {
                if model.mode == .loupe {
                    loupe
                } else {
                    grid
                }
            }
            .navigationTitle(model.mode == .loupe ? (model.activePhoto?.fileName ?? "Photo") : SourceMenuContent.currentTitle(model: model))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.mode) { _, mode in
            withAnimation { columns = mode == .loupe ? .detailOnly : .all }
            if mode == .loupe { selecting = false }
        }
    }

    // MARK: Grid

    @ViewBuilder
    private var grid: some View {
        if model.samplesMode {
            libraryGrid
        } else {
            PhotosGridView(model: model)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer(count: "\(model.photos.count) of \(model.photos.count) photos") }
        }
    }

    private func footer(count: String) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: count)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("grid.count")
            Spacer()
            Image(systemName: "square.grid.3x3").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: Bindable(model).thumbSize, in: 80...260)
                .frame(maxWidth: 180)
                .accessibilityLabel("Thumbnail size")
                .accessibilityIdentifier("grid.thumbSize")
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var libraryGrid: some View {
        PhotoGrid(model: model, selecting: $selecting)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    Text(verbatim: "\(model.state.visibleCount) of \(model.state.photoCount) photos")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("grid.count")
                    Spacer()
                    Image(systemName: "square.grid.3x3").foregroundStyle(.secondary).accessibilityHidden(true)
                    Slider(value: $model.thumbSize, in: 80...260)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Thumbnail size")
                        .accessibilityIdentifier("grid.thumbSize")
                    Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
    }

    // MARK: Loupe

    private var loupe: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                LoupeView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PanelSwitcher(model: model)
            }
            Filmstrip(model: model)
            RatingFlagBar(model: model)
                .padding(.vertical, 6)
        }
        .inspector(isPresented: $model.inspectorVisible) {
            PanelHost(model: model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.mode == .loupe {
                Button {
                    model.inspectorVisible = false
                    model.mode = .grid
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("mode.grid")
            } else {
                Button {
                    if let id = model.state.active { model.open(id) }
                } label: {
                    Label("Open Photo", systemImage: "photo")
                }
                .disabled(model.state.active == nil)
                .accessibilityIdentifier("mode.loupe")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.mode == .grid && model.samplesMode {
                Button {
                    selecting.toggle()
                } label: {
                    Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityIdentifier("grid.select")
            }
            UndoRedoButtons(model: model)
            ShareButton(model: model)
            PaletteButton(model: model)
            OverflowMenu(model: model)
        }
    }
}
