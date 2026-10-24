import SwiftUI
@preconcurrency import LightCraftKit

/// iPad layout: sidebar (sources) + detail. The detail is the library grid or, for a photo, the loupe
/// with a trailing tabbed inspector dock, the filmstrip and the rating / flag bar.
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
            .toolbar(model.canvasOnly ? .hidden : .automatic, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.canvasOnly) { _, on in
            if on { withAnimation { columns = .detailOnly } }
        }
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

    /// Width of the inspector column: 340 pt, 300 pt in narrow windows so the loupe keeps room.
    private static func inspectorWidth(for windowWidth: CGFloat) -> CGFloat { windowWidth < 900 ? 300 : 340 }

    private var loupe: some View {
        GeometryReader { geo in loupeLayout(width: geo.size.width) }
    }

    private func loupeLayout(width: CGFloat) -> some View {
        // A plain trailing dock (not `.inspector`, which overlays the content in portrait).
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                LoupeView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
                if !model.canvasOnly {
                    Filmstrip(model: model)
                    RatingFlagBar(model: model)
                        .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity)
            if model.inspectorVisible && !model.canvasOnly {
                Divider()
                InspectorColumn(model: model)
                    .frame(width: Self.inspectorWidth(for: width))
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.snappy, value: model.inspectorVisible && !model.canvasOnly)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.mode == .loupe {
                Button {
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
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.mode == .grid && model.samplesMode {
                Button {
                    selecting.toggle()
                } label: {
                    Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityIdentifier("grid.select")
            }
            if model.mode == .grid && !model.samplesMode { MediaImportButton(model: model) }
            if model.mode == .loupe { FullScreenButton(model: model) }
            UndoRedoButtons(model: model)
            ShareButton(model: model)
            PaletteButton(model: model)
            OverflowMenu(model: model)
            if model.mode == .loupe { PanelVisibilityButton(model: model) }
        }
    }
}
