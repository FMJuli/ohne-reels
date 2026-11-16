import SwiftUI

/// Einstiegspunkt der App.
/// Die App enthält bewusst KEIN Analytics, KEIN Crash-Reporting und stellt selbst
/// keine Netzwerkanfragen – alles Netzwerk läuft ausschließlich über den WKWebView.
@main
struct OhneReelsApp: App {
    @StateObject private var modell = WebViewModell()

    var body: some Scene {
        WindowGroup {
            HauptAnsicht()
                .environmentObject(modell)
        }
    }
}
