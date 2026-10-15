import SwiftUI

@main
struct ClonerApp: App {
    @StateObject private var store = CloneStore()

    var body: some Scene {
        WindowGroup {
            ClonerWindow()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
    }
}
