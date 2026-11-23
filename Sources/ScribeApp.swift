import SwiftUI

@main
struct ScribeApp: App {
    @StateObject private var model = ScribeModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
