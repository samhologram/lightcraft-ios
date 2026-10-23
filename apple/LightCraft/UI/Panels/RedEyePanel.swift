import SwiftUI
@preconcurrency import LightCraftKit

/// Red Eye: corrections of the active photo. Corrections are placed on the eye in the photo; the
/// button below adds one at the centre as a starting point (the pupil inside is found automatically).
struct RedEyePanel: View {
    let model: LibraryModel

    private struct EyeRow: Identifiable {
        let id: Int
        let pet: Bool
        let pupil: Double
        let darken: Double
    }

    @State private var eyes: [EyeRow] = []
    @State private var pet = false

    var body: some View {
        if model.activePhoto == nil {
            PanelEmptyState(title: "No Photo", symbol: "photo", message: "Open a photo to correct red eye.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Pet eye", isOn: $pet)
                        .accessibilityIdentifier("redeye.pet")
                    Button {
                        model.run("redeye.add", ["center": [0.5, 0.5], "rx": 0.03, "ry": 0.03, "pet": pet])
                    } label: {
                        Label("Add Correction", systemImage: "plus.circle")
                    }
                    .buttonStyle(.glass)
                    .disabled(!model.isEnabled("redeye.add"))
                    .accessibilityIdentifier("command.redeye.add")
                    Text("Corrections").font(.headline)
                    if eyes.isEmpty {
                        Text("No corrections yet.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(eyes) { eye in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: "\(eye.pet ? "Pet eye" : "Eye") \(eye.id + 1)").font(.subheadline.weight(.medium))
                                Text(verbatim: "Pupil \(Int(eye.pupil)) · Darken \(Int(eye.darken))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                model.run("redeye.delete", ["index": eye.id])
                            } label: {
                                Image(systemName: "trash").frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Delete correction")
                            .accessibilityIdentifier("command.redeye.delete.\(eye.id)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("redeye.\(eye.id)")
                    }
                }
                .padding(16)
            }
            .onChange(of: model.state.revision, initial: true) { _, _ in reload() }
            .onChange(of: model.state.active) { _, _ in reload() }
        }
    }

    private func reload() {
        guard let id = model.state.active,
              let dev = EngineQuery.develop(model, id),
              let list = dev["red_eye"] as? [[String: Any]] else {
            eyes = []
            return
        }
        eyes = list.enumerated().map { i, e in
            EyeRow(id: i, pet: (e["pet"] as? Bool) ?? false, pupil: jsonNumber(e["pupil_size"]) ?? 50, darken: jsonNumber(e["darken"]) ?? 0)
        }
    }
}
