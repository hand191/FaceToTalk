import SwiftUI

@main
struct FaceToTalkApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model, settings: model.settings)
        } label: {
            Image(systemName: model.menuIcon)
                .accessibilityLabel("FaceToTalk")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, settings: model.settings)
        }
    }
}
