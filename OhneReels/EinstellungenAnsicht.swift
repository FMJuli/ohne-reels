import SwiftUI

/// Kleiner Einstellungsbildschirm (Zahnrad in der Tab-Leiste).
struct EinstellungenAnsicht: View {
    @EnvironmentObject private var modell: WebViewModell
    @Environment(\.dismiss) private var schliessen

    @AppStorage(Einstellungen.Schluessel.feedAn) private var feedAn = Einstellungen.Standard.feedAn
    @AppStorage(Einstellungen.Schluessel.profilRasterAn) private var profilRasterAn = Einstellungen.Standard.profilRasterAn
    @AppStorage(Einstellungen.Schluessel.instagramLeisteAus) private var instagramLeisteAus = Einstellungen.Standard.instagramLeisteAus
    @AppStorage(Einstellungen.Schluessel.inkognito) private var inkognito = Einstellungen.Standard.inkognito
    @AppStorage(Einstellungen.Schluessel.benutzername) private var benutzername = ""

    @State private var zeigeLoeschfrage = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Home-Feed anzeigen", isOn: $feedAn)
                    Toggle("Beitragsraster auf Profilen", isOn: $profilRasterAn)
                } header: {
                    Text("Inhalte")
                } footer: {
                    Text("Immer blockiert: Reels, der Reels-Tab auf Profilen, das Explore-Raster, vorgeschlagene Konten und Beiträge sowie Werbung. Stories und Nachrichten bleiben immer verfügbar.")
                }

                Section {
                    Toggle("Instagrams eigene Leiste ausblenden", isOn: $instagramLeisteAus)
                    TextField("Eigener Benutzername (optional)", text: $benutzername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Bedienung")
                } footer: {
                    Text("Fehlt dir ohne Instagrams Leiste etwas (z. B. das Plus zum Erstellen), schalte sie wieder ein – das Reels-Symbol bleibt verborgen. Der Benutzername wird nur gebraucht, falls der Profil-Tab dein Profil nicht von selbst findet.")
                }

                Section {
                    Toggle("Inkognito-Modus", isOn: $inkognito)
                    Button(role: .destructive) {
                        zeigeLoeschfrage = true
                    } label: {
                        Text("Alle Daten löschen & abmelden")
                    }
                } header: {
                    Text("Datenschutz")
                } footer: {
                    Text("Gespeichert bleiben nur die Login-Cookies von instagram.com. Cache, Website-Speicher und alle übrigen Cookies werden bei jedem Start und beim Verlassen der App gelöscht. Im Inkognito-Modus wird gar nichts dauerhaft gespeichert – du meldest dich dann bei jedem Start neu an. Das Umschalten meldet dich ab.")
                }

                Section {
                    Text("Version \(versionsText)")
                        .foregroundStyle(Color.secondary)
                } footer: {
                    Text("Diese App enthält kein Analytics und kein Crash-Reporting. Sie verbindet sich nur mit Instagram und den Servern, von denen Instagram seine Bilder und Videos lädt.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        schliessen()
                    }
                }
            }
            .confirmationDialog("Wirklich alle Daten löschen?",
                                isPresented: $zeigeLoeschfrage,
                                titleVisibility: .visible) {
                Button("Löschen & abmelden", role: .destructive) {
                    modell.allesLoeschenUndAbmelden()
                    schliessen()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Login, Cookies, Cache und Website-Speicher werden auf diesem iPhone entfernt. Deine Schalter-Einstellungen bleiben erhalten.")
            }
        }
        // Änderungen sofort an den WebView weitergeben.
        .onChange(of: feedAn) { _ in modell.einstellungenGeaendert() }
        .onChange(of: profilRasterAn) { _ in modell.einstellungenGeaendert() }
        .onChange(of: instagramLeisteAus) { _ in modell.einstellungenGeaendert() }
        .onChange(of: inkognito) { _ in modell.inkognitoGeaendert() }
    }

    private var versionsText: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "–"
    }
}
