import SwiftUI

@main
struct MenuBarLofiApp: App {
    @State private var radio = Radio()

    var body: some Scene {
        MenuBarExtra {
            PanelView(radio: radio)
        } label: {
            Image(systemName: "headphones")
        }
        .menuBarExtraStyle(.window)
    }
}
