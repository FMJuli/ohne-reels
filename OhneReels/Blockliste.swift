import Foundation
import WebKit

/// TRACKING-BLOCKER auf Netzwerkebene (WKContentRuleList).
///
/// Diese Regeln wertet WebKit selbst aus – noch bevor eine Anfrage das iPhone verlässt.
/// Die Muster sind KEINE vollwertigen regulären Ausdrücke. Erlaubt sind nur:
///   .  .*  ?  +  *  [abc]  [^abc]  (gruppen)  ^ am Anfang  $ am Ende
/// NICHT erlaubt: |  \d  \w  {2,3}
@MainActor
enum Blockliste {

    // MARK: - Anpassbare Listen

    /// Anfragen, die blockiert werden (reines Tracking / Analyse).
    /// Wenn nach einer Änderung von Instagram etwas nicht mehr funktioniert (z. B. Login hängt),
    /// hier testweise Zeilen auskommentieren.
    static let blockierteAnfragen: [String] = [
        // Instagrams eigene Ereignis-Protokollierung ("Banzai" / "Falco")
        #"^[^:]+://+([^:/]+\.)?instagram\.com/ajax/bz"#,
        #"^[^:]+://+([^:/]+\.)?instagram\.com/logging/"#,
        #"^[^:]+://+([^:/]+\.)?instagram\.com/logging_client_events"#,
        #"^[^:]+://+graph\.instagram\.com/logging_client_events"#,
        // Facebook-Pixel und Facebook-Protokollierung
        #"^[^:]+://+([^:/]+\.)?facebook\.com/tr[/?]"#,
        #"^[^:]+://+([^:/]+\.)?facebook\.com/ajax/bz"#,
        #"^[^:]+://+pixel\.facebook\.com/"#,
        // Analyse-Dienste Dritter (falls Instagram sie je einbindet)
        #"^[^:]+://+([^:/]+\.)?google-analytics\.com/"#,
        #"^[^:]+://+([^:/]+\.)?googletagmanager\.com/"#,
        #"^[^:]+://+([^:/]+\.)?doubleclick\.net/"#,
        #"^[^:]+://+([^:/]+\.)?scorecardresearch\.com/"#
        // Bewusst NICHT blockiert: connect.facebook.net (Facebook-SDK). Die Login-Seite lädt es;
        // ich konnte nicht testen, ob der Login ohne es sauber funktioniert.
    ]

    /// Elemente, die WebKit selbst ausblendet – unabhängig vom Userscript (dritte Sicherung).
    /// Nur einfache, stabile Selektoren über href. Feinheiten stehen in userscript.js.
    static let versteckteSelektoren: [String] = [
        "a[href='/reels/']",
        "a[href$='/reels/']",
        "a[href^='instagram://']",
        "a[href*='apps.apple.com']",
        "a[href*='itunes.apple.com']"
    ]

    // MARK: - Kompilieren

    private static var kompiliert: [WKContentRuleList]?

    /// Liefert die kompilierten Listen (beim ersten Aufruf wird kompiliert, danach zwischengespeichert).
    /// Schlägt das Kompilieren fehl, kommt eine leere Liste zurück – die App läuft dann ohne diesen Schutz weiter.
    static func laden(_ fertig: @escaping @MainActor ([WKContentRuleList]) -> Void) {
        if let kompiliert {
            fertig(kompiliert)
            return
        }

        var netzRegeln: [[String: Any]] = []
        for muster in blockierteAnfragen {
            let ausloeser: [String: Any] = ["url-filter": muster]
            let aktion: [String: Any] = ["type": "block"]
            netzRegeln.append(["trigger": ausloeser, "action": aktion])
        }

        var cssRegeln: [[String: Any]] = []
        let cssAusloeser: [String: Any] = ["url-filter": ".*", "if-domain": ["*instagram.com"]]
        let cssAktion: [String: Any] = ["type": "css-display-none", "selector": versteckteSelektoren.joined(separator: ", ")]
        cssRegeln.append(["trigger": cssAusloeser, "action": cssAktion])

        // Zwei getrennte Listen: Ist eine fehlerhaft, gilt die andere trotzdem.
        Blockliste.kompiliere("ohne-reels-netz", netzRegeln) { netz in
            Blockliste.kompiliere("ohne-reels-css", cssRegeln) { css in
                let listen: [WKContentRuleList] = [netz, css].compactMap { $0 }
                Blockliste.kompiliert = listen
                fertig(listen)
            }
        }
    }

    private static func kompiliere(_ kennung: String, _ regeln: [[String: Any]],
                                   fertig: @escaping @MainActor (WKContentRuleList?) -> Void) {
        guard let daten = try? JSONSerialization.data(withJSONObject: regeln),
              let json = String(data: daten, encoding: .utf8),
              let ablage = WKContentRuleListStore.default() else {
            fertig(nil)
            return
        }
        ablage.compileContentRuleList(forIdentifier: kennung, encodedContentRuleList: json) { liste, _ in
            Task { @MainActor in
                fertig(liste)
            }
        }
    }
}
