import SwiftUI

private struct LibraryModelKey: FocusedValueKey {
    typealias Value = LibraryModel
}

extension FocusedValues {
    /// The model of the focused library scene; read by the menu bar (`LibraryCommands`).
    var libraryModel: LibraryModel? {
        get { self[LibraryModelKey.self] }
        set { self[LibraryModelKey.self] = newValue }
    }
}
