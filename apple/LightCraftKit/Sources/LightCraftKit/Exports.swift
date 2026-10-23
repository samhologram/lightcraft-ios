// Re-exports nothing by itself: the UniFFI-generated `lightcraft_apple.swift` (produced by
// apple/scripts/build-xcframework.sh) is compiled into this module, so `import LightCraftKit`
// exposes LibraryHandle, CommandInfo, LibraryState, PhotoInfo, etc.
// This file keeps the source directory present before the first bridge build.
@_exported import Foundation
