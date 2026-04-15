import SwiftUI

@main
struct control_panelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
