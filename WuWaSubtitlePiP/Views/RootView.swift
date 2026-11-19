import SwiftUI
import Translation

public struct RootView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                HomeControlView(appState: appState)
            }
            .tabItem {
                Label("Điều khiển", systemImage: "play.rectangle.on.rectangle")
            }
            .tag(AppTab.control)

            NavigationStack {
                ROICalibrationView(appState: appState)
            }
            .tabItem {
                Label("Vùng quét", systemImage: "crop")
            }
            .tag(AppTab.calibration)

            NavigationStack {
                HistoryAndSettingsView(appState: appState)
            }
            .tabItem {
                Label("Lịch sử & Cài đặt", systemImage: "list.bullet.rectangle")
            }
            .tag(AppTab.historyAndSettings)
        }
        .tint(WuWaTheme.gold)
        .background(WuWaTheme.obsidianBackground.ignoresSafeArea())
        // Persistent offline Apple Translation task mounted at root so switching tabs
        // never interrupts or drops active game dialogue translations.
        .translationTask(appState.translationService.translationConfiguration) { session in
            await appState.translationService.consumeSession(session)
        }
        .task {
            await appState.bootstrap()
        }
    }
}

public enum WuWaTheme {
    public static let obsidianBackground = Color(red: 0.039, green: 0.047, blue: 0.071)
    public static let cardSurface = Color(red: 0.075, green: 0.094, blue: 0.137)
    public static let elevatedSurface = Color(red: 0.106, green: 0.133, blue: 0.192)
    public static let gold = Color(red: 0.902, green: 0.788, blue: 0.478)
    public static let goldMuted = Color(red: 0.902, green: 0.788, blue: 0.478).opacity(0.22)
    public static let textPrimary = Color(red: 0.957, green: 0.965, blue: 0.984)
    public static let textSecondary = Color(red: 0.635, green: 0.686, blue: 0.776)
    public static let emerald = Color(red: 0.251, green: 0.831, blue: 0.541)
    public static let amber = Color(red: 0.961, green: 0.690, blue: 0.255)
    public static let crimson = Color(red: 0.937, green: 0.357, blue: 0.396)
}
