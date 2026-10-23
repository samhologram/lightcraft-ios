import SwiftUI
@preconcurrency import LightCraftKit

/// Crop & Rotate: aspect presets, straighten angle, rotate / flip, reset.
struct CropPanel: View {
    let model: LibraryModel

    private static let aspects: [(id: String, title: String)] = [
        ("original", "Original"), ("free", "Free"), ("current", "Current"), ("1x1", "1:1"), ("4x5", "4:5"),
        ("5x7", "5:7"), ("2x3", "2:3"), ("4x3", "4:3"), ("16x9", "16:9"), ("16x10", "16:10"),
    ]
    private static let angle: ControlInfo? = developControls().first { $0.id == "crop.angle" }

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to crop it.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Aspect").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(Self.aspects, id: \.id) { a in
                            Button {
                                model.run("crop.aspect", ["aspect": a.id])
                            } label: {
                                Text(verbatim: a.title).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("crop.aspect.\(a.id)")
                        }
                    }
                    if let angle = Self.angle {
                        DevelopSlider(model: model, control: angle)
                    }
                    Text("Rotate & Flip").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        action("photo.rotateLeft", "Rotate Left", "rotate.left")
                        action("photo.rotateRight", "Rotate Right", "rotate.right")
                        action("photo.flipHorizontal", "Flip Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        action("photo.flipVertical", "Flip Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down")
                        action("crop.rotateAspect", "Rotate Crop", "rectangle.landscape.rotate")
                        action("crop.autoStraighten", "Auto Straighten", "wand.and.stars")
                    }
                    HStack {
                        Button {
                            model.runUI("tool.guidedUpright")
                        } label: {
                            Label("Guided Upright", systemImage: "grid")
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("tool.guidedUpright")
                        Spacer()
                        Button(role: .destructive) {
                            model.run("crop.reset")
                        } label: {
                            Label("Reset Crop", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.glass)
                        .disabled(!model.isEnabled("crop.reset"))
                        .accessibilityIdentifier("command.crop.reset")
                    }
                }
                .padding(16)
            }
        }
    }

    private func action(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button {
            model.run(id)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .disabled(!model.isEnabled(id))
        .accessibilityIdentifier("command.\(id)")
    }
}
