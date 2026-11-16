import Foundation

/// Alle Einstellungen der App an einer Stelle.
/// Gespeichert wird ausschließlich in UserDefaults (also nur lokal auf dem iPhone).
enum Einstellungen {

    /// Schlüsselnamen in UserDefaults. Die Einstellungs-Ansicht nutzt dieselben Schlüssel über @AppStorage.
    enum Schluessel {
        static let feedAn = "feedAn"
        static let profilRasterAn = "profilRasterAn"
        static let instagramLeisteAus = "instagramLeisteAus"
        static let inkognito = "inkognito"
        static let benutzername = "benutzername"
        static let diagnose = "diagnose"
    }

    /// Standardwerte – hier ändern, wenn die App anders starten soll.
    enum Standard {
        /// Home-Feed anzeigen (immer ohne Reels, Vorschläge und Werbung).
        static let feedAn = true
        /// Beitragsraster auf Profilen anzeigen.
        static let profilRasterAn = true
        /// Instagrams eigene Web-Leiste ausblenden (die native Tab-Leiste ersetzt sie).
        static let instagramLeisteAus = true
        /// Inkognito: nichts dauerhaft speichern, Login bei jedem Start.
        static let inkognito = false
        /// Diagnose-Kasten über der Seite (nur zur Fehlersuche).
        static let diagnose = false
    }

    private static func wahrheitswert(_ schluessel: String, standard: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: schluessel) as? Bool) ?? standard
    }

    static var feedAn: Bool { wahrheitswert(Schluessel.feedAn, standard: Standard.feedAn) }
    static var profilRasterAn: Bool { wahrheitswert(Schluessel.profilRasterAn, standard: Standard.profilRasterAn) }
    static var instagramLeisteAus: Bool { wahrheitswert(Schluessel.instagramLeisteAus, standard: Standard.instagramLeisteAus) }
    static var inkognito: Bool { wahrheitswert(Schluessel.inkognito, standard: Standard.inkognito) }
    static var diagnose: Bool { wahrheitswert(Schluessel.diagnose, standard: Standard.diagnose) }

    /// Optional von Hand eingetragener eigener Benutzername (Ausweichlösung für den Profil-Tab).
    /// Gibt nil zurück, wenn nichts oder etwas Ungültiges eingetragen ist.
    static var benutzername: String? {
        let roh = (UserDefaults.standard.string(forKey: Schluessel.benutzername) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = roh.hasPrefix("@") ? String(roh.dropFirst()) : roh
        return Regelwerk.istBenutzername(name) ? name : nil
    }

    /// Die Schalter als JavaScript-Objekt – wird an das Userscript übergeben.
    static var alsJavaScript: String {
        "{feed:\(feedAn),raster:\(profilRasterAn),navAus:\(instagramLeisteAus),diagnose:\(diagnose)}"
    }
}
