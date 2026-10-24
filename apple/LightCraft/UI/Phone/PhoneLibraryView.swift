import SwiftUI
@preconcurrency import LightCraftKit

/// iPhone layout (also iPad windows narrower than 700 pt): a grid with a source menu, and a full-screen
/// loupe with a scrolling tool strip at the bottom. The chosen panel opens in a bottom sheet that
/// leaves the photo visible and interactive.
struct PhoneLibraryView: View {
    @Bindable var model: LibraryModel

    @State private var selecting = false
    @State private var detent: PresentationDetent = .fraction(Self.smallDetent)

    private static let smallDetent: CGFloat = 0.35

    private var panelSheetShown: Binding<Bool> {
        Binding(
            get: { model.mode == .loupe && model.inspectorVisible && !model.canvasOnly },
            set: { if !model.canvasOnly { model.inspectorVisible = $0 } }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.mode == .loupe {
                    loupe
                } else if !model.samplesMode {
                    PhotosGridView(model: model)
                        .safeAreaInset(edge: .bottom, spacing: 0) { thumbBar }
                } else {
                    PhotoGrid(model: model, selecting: $selecting)
                        .safeAreaInset(edge: .bottom, spacing: 0) { thumbBar }
                }
            }
            .navigationTitle(model.mode == .loupe ? (model.activePhoto?.fileName ?? "Photo") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbar(model.canvasOnly ? .hidden : .automatic, for: .navigationBar)
        }
        .sheet(isPresented: panelSheetShown) {
            PanelHost(model: model)
                .presentationDetents([.fraction(Self.smallDetent), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    private var thumbBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: $model.thumbSize, in: 70...220)
                .accessibilityLabel("Thumbnail size")
                .accessibilityIdentifier("grid.thumbSize")
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Loupe

    /// Share of the height the panel sheet covers at its current detent; the photo is fitted above it
    /// (a full-height sheet hides the photo anyway).
    private var sheetCover: CGFloat {
        guard panelSheetShown.wrappedValue else { return 0 }
        if detent == .fraction(Self.smallDetent) { return Self.smallDetent }
        return detent == .medium ? 0.5 : 0
    }

    private var loupe: some View {
        GeometryReader { geo in
            LoupeView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, max(0, sheetCover * (geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom) - geo.safeAreaInsets.bottom))
                .animation(.snappy, value: sheetCover)
        }
            .background(Color(uiColor: .systemBackground))
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard model.zoomToFit, abs(dx) > 70, abs(dx) > abs(dy) * 2 else { return }
                        if model.samplesMode {
                            model.run(dx < 0 ? "library.next" : "library.previous")
                        } else {
                            model.stepPhoto(dx < 0 ? 1 : -1)
                        }
                    }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The panel sheet has its own panel strip and covers this one.
                if !panelSheetShown.wrappedValue && !model.canvasOnly {
                    VStack(spacing: 4) {
                        RatingFlagBar(model: model, compact: true)
                        ToolStrip(model: model)
                    }
                    .padding(.bottom, 2)
                    .background(.bar)
                }
            }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.mode == .loupe {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.inspectorVisible = false
                    model.mode = .grid
                } label: {
                    Label("Library", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("mode.grid")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                FullScreenButton(model: model)
                UndoRedoButtons(model: model)
                ShareButton(model: model)
                OverflowMenu(model: model)
                PanelVisibilityButton(model: model)
            }
        } else {
            ToolbarItem(placement: .principal) {
                Menu {
                    SourceMenuContent(model: model)
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: SourceMenuContent.currentTitle(model: model)).font(.headline)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                }
                .accessibilityIdentifier("menu.source")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.samplesMode { MediaImportButton(model: model) }
                if model.samplesMode {
                    Button {
                        selecting.toggle()
                    } label: {
                        Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .accessibilityIdentifier("grid.select")
                }
                Menu {
                    PaletteButton(model: model)
                    Divider()
                    CommandMenuContent(model: model, path: ["Photo"])
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("menu.more")
            }
        }
    }
}
