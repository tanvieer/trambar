import SwiftUI

@main
struct TramBarApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
