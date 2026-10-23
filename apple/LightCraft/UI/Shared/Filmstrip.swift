import SwiftUI
@preconcurrency import LightCraftKit

/// Horizontal strip of the photos in view; tapping one makes it the active photo.
struct Filmstrip: View {
    let model: LibraryModel
    var height: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(model.visible, id: \.self) { id in
                        let active = model.state.active == id
                        Button {
                            model.select(id)
                        } label: {
                            ThumbnailView(model: model, id: id, edge: height)
                                .frame(width: height, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(active ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(id)
                        .accessibilityIdentifier("filmstrip.\(id)")
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.state.active, initial: true) { _, new in
                if let new { withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) } }
            }
        }
        .frame(height: height + 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmstrip")
    }
}
