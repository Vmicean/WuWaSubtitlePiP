import SwiftUI

@main
public struct WuWaSubtitlePiPApp: App {
    @State private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView(appState: appState)
                .preferredColorScheme(.dark)
        }
    }
}
