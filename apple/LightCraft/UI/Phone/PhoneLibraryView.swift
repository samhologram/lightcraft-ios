import SwiftUI
@preconcurrency import LightCraftKit

/// iPhone layout (also iPad windows narrower than 700 pt): a grid with a source menu, and a full-screen
/// loupe with a scrolling tool strip at the bottom. The chosen panel opens in a bottom sheet that
/// leaves the photo visible and interactive.
struct PhoneLibraryView: View {
    @Bindable var model: LibraryModel

    @State private var selecting = false

    private var panelSheetShown: Binding<Bool> {
        Binding(
            get: { model.mode == .loupe && model.inspectorVisible },
            set: { model.inspectorVisible = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.mode == .loupe {
                    loupe
                } else {
                    PhotoGrid(model: model, selecting: $selecting)
                        .safeAreaInset(edge: .bottom, spacing: 0) { thumbBar }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(isPresented: panelSheetShown) {
            PanelHost(model: model, showsSwitcher: true)
                .presentationDetents([.fraction(0.35), .medium, .large])
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

    private var loupe: some View {
        LoupeView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard model.zoomToFit, abs(dx) > 70, abs(dx) > abs(dy) * 2 else { return }
                        model.run(dx < 0 ? "library.next" : "library.previous")
                    }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    RatingFlagBar(model: model, compact: true)
                    ToolStrip(model: model)
                }
                .padding(.bottom, 2)
                .background(.bar)
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
                    Label("Library", systemImage: "chevron.backward")
                }
                .accessibilityIdentifier("mode.grid")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                UndoRedoButtons(model: model)
                ShareButton(model: model)
                OverflowMenu(model: model)
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
                ImportButton(model: model)
                Button {
                    selecting.toggle()
                } label: {
                    Label(selecting ? "Done" : "Select", systemImage: selecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityIdentifier("grid.select")
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
