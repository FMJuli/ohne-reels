import SwiftUI
import UIKit
import WebKit

/// Hauptbildschirm: WebView im Vollbild, darüber ein dünner Ladebalken, darunter die native Tab-Leiste.
struct HauptAnsicht: View {
    @EnvironmentObject private var modell: WebViewModell
    @State private var zeigeEinstellungen = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // .id(...) sorgt dafür, dass SwiftUI den WebView austauscht, wenn ein neuer erzeugt wurde.
                WebAnsicht(webView: modell.webView)
                    .id(modell.generation)

                if modell.laedt {
                    Ladebalken(fortschritt: modell.fortschritt)
                }

                if let meldung = modell.fehlermeldung {
                    FehlerAnsicht(meldung: meldung) {
                        modell.neuLaden()
                    }
                }

                if let hinweis = modell.hinweis {
                    HinweisAnsicht(text: hinweis)
                }
            }

            // Solange die Tastatur offen ist, macht die Tab-Leiste Platz (z. B. beim Schreiben von Nachrichten).
            if !modell.tastaturSichtbar {
                TabLeiste(
                    aktiv: modell.aktiverBereich,
                    wahl: { bereich in modell.waehle(bereich) },
                    einstellungen: { zeigeEinstellungen = true }
                )
            }
        }
        // Hintergrund bis unter Statusleiste und Home-Balken; Farbe folgt Hell/Dunkel des Systems.
        .background {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        }
        .sheet(isPresented: $zeigeEinstellungen) {
            EinstellungenAnsicht()
                .environmentObject(modell)
        }
    }
}

/// Brücke zwischen SwiftUI und dem WKWebView aus dem Modell.
struct WebAnsicht: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Nichts zu tun – der WebView wird vollständig vom Modell gesteuert.
    }
}

/// Dünner Ladebalken am oberen Rand.
struct Ladebalken: View {
    let fortschritt: Double

    var body: some View {
        GeometryReader { geometrie in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geometrie.size.width * CGFloat(max(0.05, min(1, fortschritt))))
                .animation(.easeOut(duration: 0.2), value: fortschritt)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

/// Wird gezeigt, wenn eine Seite nicht geladen werden konnte (z. B. kein Netz).
struct FehlerAnsicht: View {
    let meldung: String
    let erneut: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.secondary)
            Text("Seite konnte nicht geladen werden")
                .font(.headline)
            Text(meldung)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            Button("Erneut versuchen", action: erneut)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

/// Kleine Einblendung für kurze Hinweise.
struct HinweisAnsicht: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .allowsHitTesting(false)
    }
}

/// Native Tab-Leiste: Feed, Suche, Nachrichten, Profil – und rechts das Zahnrad.
struct TabLeiste: View {
    let aktiv: Bereich
    let wahl: (Bereich) -> Void
    let einstellungen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Bereich.allCases) { bereich in
                Button {
                    wahl(bereich)
                } label: {
                    eintrag(symbol: bereich == aktiv ? bereich.symbolAktiv : bereich.symbol,
                            titel: bereich.titel,
                            hervorgehoben: bereich == aktiv)
                }
                .accessibilityLabel(bereich.titel)
            }

            Button(action: einstellungen) {
                eintrag(symbol: "gearshape", titel: "Optionen", hervorgehoben: false)
            }
            .accessibilityLabel("Einstellungen")
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func eintrag(symbol: String, titel: String, hervorgehoben: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: hervorgehoben ? .semibold : .regular))
            Text(titel)
                .font(.system(size: 10))
        }
        .foregroundStyle(hervorgehoben ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .contentShape(Rectangle())
    }
}
