import AppKit
import SwiftUI

@main
struct ZRImporterApp: App {
    @StateObject private var model = CameraImportModel()

    var body: some Scene {
        WindowGroup("Open Nikon Importer") {
            ContentView(model: model)
                .onAppear {
                    model.start()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Aktualisieren") {
                    model.refresh()
                }
                .keyboardShortcut("r")

                Button("Vorschau") {
                    model.previewSelection(openQuickLook: true)
                }
                .keyboardShortcut(.space, modifiers: [])
            }

            CommandMenu("Project") {
                Button("Open GitHub Project") {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                }
            }
        }
    }
}

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/Neekzu/open-nikon-importer")!
}
