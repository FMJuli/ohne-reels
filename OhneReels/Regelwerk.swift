import Foundation

/// Ergebnis einer Regelprüfung für eine Adresse.
enum Entscheidung: Equatable {
    /// Seite darf im WebView geladen werden.
    case erlauben
    /// Navigation wird stillschweigend verworfen.
    case blockieren
    /// Statt der gewünschten Seite wird diese Adresse im WebView geladen.
    case umleiten(URL)
    /// Adresse wird in Safari (bzw. Mail, Telefon …) geöffnet.
    case extern(URL)
}

/// NAVIGATIONSREGELN IN SWIFT (erste Sicherung).
///
/// Diese Regeln greifen bei jedem echten Seitenaufruf (decidePolicyFor) und zusätzlich,
/// sobald sich die Adresse des WebViews ändert (auch bei Instagrams Single-Page-Navigation).
/// Dieselben Regeln stehen noch einmal in Ressourcen/userscript.js (zweite Sicherung).
/// Wer hier etwas ändert, sollte es dort ebenfalls ändern.
struct Regelwerk {

    // MARK: - Feste Adressen

    static let startseite = URL(string: "https://www.instagram.com/")!
    static let suche = URL(string: "https://www.instagram.com/explore/")!
    static let nachrichten = URL(string: "https://www.instagram.com/direct/inbox/")!

    // MARK: - Anpassbare Listen

    /// Erste Pfadteile, die KEINE Benutzernamen sind (damit /explore/ nicht als Profil gilt).
    static let reservierteNamen: Set<String> = [
        "about", "accounts", "ads", "api", "ar", "archive", "auth_platform", "challenge", "consent",
        "create", "developer", "direct", "directory", "download", "emails", "explore", "fxcal",
        "graphql", "help", "invites", "legal", "lite", "locations", "nametag", "notifications",
        "oauth", "p", "press", "privacy", "qr", "reel", "reels", "session", "settings", "static",
        "stories", "tags", "terms", "topics", "tv", "two_factor", "web", "your_activity"
    ]

    /// Schemata, die nie geöffnet werden (App-Sprünge und App-Store-Weiterleitungen).
    static let blockierteSchemata: Set<String> = [
        "instagram", "instagram-stories", "barcelona", "fb", "fb-messenger", "fbapi",
        "itms", "itms-apps", "itms-appss", "itms-services", "intent", "market"
    ]

    /// Schemata, die an das System weitergegeben werden.
    static let externeSchemata: Set<String> = ["mailto", "tel", "sms"]

    /// App-Store-Seiten: werden blockiert, nicht in Safari geöffnet.
    static let appStoreHosts: Set<String> = ["apps.apple.com", "itunes.apple.com", "play.google.com"]

    /// So lange (Sekunden) gilt ein Rücksprung von /reel/CODE/ auf /reels/CODE/ als
    /// "Instagram besteht auf dem Reels-Betrachter" (siehe unten).
    static let ruecksprungFrist: TimeInterval = 15

    // MARK: - Zustand

    /// Zuletzt akzeptierte Instagram-Adresse.
    private(set) var letzteURL: URL?
    /// Zuletzt geöffnetes Einzel-Reel (/reel/CODE/).
    private var einzelReel: (code: String, zeit: Date)?
    /// Code des einen Reels, das im Reels-Betrachter (/reels/CODE/) bleiben darf.
    private var betrachterCode: String?

    // MARK: - Hilfsfunktionen

    static func istInstagram(_ host: String) -> Bool {
        host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    /// Pfadteile ohne Schrägstriche: "/reels/abc/" → ["reels", "abc"].
    static func segmente(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    private static let namensZeichen = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
    private static let codeZeichen = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    static func istBenutzername(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 30
            && text.unicodeScalars.allSatisfy { namensZeichen.contains($0) }
            && !reservierteNamen.contains(text.lowercased())
    }

    static func istReelCode(_ text: String) -> Bool {
        text.count >= 5 && text.unicodeScalars.allSatisfy { codeZeichen.contains($0) }
    }

    /// Liefert den Reel-Code, wenn der Pfad ein einzelnes Reel bezeichnet:
    /// /reel/CODE/, /reels/CODE/ oder /name/reel/CODE/.
    static func reelCode(_ teile: [String]) -> String? {
        guard let erstes = teile.first?.lowercased() else { return nil }
        if erstes == "reel", teile.count >= 2, istReelCode(teile[1]) { return teile[1] }
        if erstes == "reels", teile.count == 2, istReelCode(teile[1]) { return teile[1] }
        if teile.count >= 3, teile[1].lowercased() == "reel", istReelCode(teile[2]) { return teile[2] }
        return nil
    }

    static func profilURL(_ name: String) -> URL? {
        guard istBenutzername(name) else { return nil }
        return URL(string: "https://www.instagram.com/\(name)/")
    }

    /// Instagram schickt externe Links über l.instagram.com/?u=ZIEL. Wir holen das echte Ziel heraus,
    /// damit Safari direkt dorthin geht.
    static func zielHinterWeiterleitung(_ url: URL) -> URL? {
        guard let teile = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let wert = teile.queryItems?.first(where: { $0.name == "u" })?.value,
              let ziel = URL(string: wert),
              let schema = ziel.scheme?.lowercased(),
              schema == "http" || schema == "https" else { return nil }
        return ziel
    }

    /// Eingebettete Rahmen (iframes) werden nicht nach Pfad geprüft – nur das Schema muss stimmen.
    /// (Tracking in Rahmen fängt die Blockliste ab.)
    static func unterrahmenErlaubt(_ url: URL) -> Bool {
        let schema = (url.scheme ?? "").lowercased()
        return ["http", "https", "about", "blob", "data"].contains(schema)
    }

    // MARK: - Die eigentliche Prüfung (Hauptrahmen)

    mutating func bewerte(_ url: URL) -> Entscheidung {
        let schema = (url.scheme ?? "").lowercased()

        if schema == "about" || schema == "blob" { return .erlauben }
        if Self.externeSchemata.contains(schema) { return .extern(url) }
        // instagram://, itms-apps:// usw. – und alles Unbekannte – wird verworfen.
        guard schema == "http" || schema == "https" else { return .blockieren }
        guard let host = url.host?.lowercased() else { return .blockieren }

        // App-Store-Weiterleitungen ("App laden") verwerfen.
        if Self.appStoreHosts.contains(host) { return .blockieren }

        // Alles außerhalb von Instagram gehört in Safari.
        guard Self.istInstagram(host) else { return .extern(url) }

        // Link-Weiterleitung von Instagram: echtes Ziel herausholen.
        if host == "l.instagram.com" {
            guard let ziel = Self.zielHinterWeiterleitung(url) else { return .extern(url) }
            if let zielHost = ziel.host?.lowercased(), Self.istInstagram(zielHost), zielHost != "l.instagram.com" {
                return .umleiten(ziel)
            }
            return .extern(ziel)
        }

        let teile = Self.segmente(url)
        let erstes = teile.first?.lowercased() ?? ""
        let neuerCode = Self.reelCode(teile)
        let alterCode = letzteURL.flatMap { Self.reelCode(Self.segmente($0)) }

        // REGEL 1 – Kein Wischen von Reel zu Reel.
        // Wer gerade ein Reel ansieht, kommt von dort nicht direkt zu einem anderen Reel.
        if let neuerCode, let alterCode, neuerCode != alterCode, let zurueck = letzteURL {
            return .umleiten(zurueck)
        }

        // REGEL 2 – Der Reels-Bereich.
        if erstes == "reels" {
            // /reels/ selbst (der Feed), /reels/audio/… usw.: immer gesperrt.
            guard let code = neuerCode else { return .umleiten(Self.startseite) }
            // /reels/CODE/ ist der wischbare Betrachter. Wir leiten auf die Einzelansicht /reel/CODE/ um.
            // Ausnahme: Schickt Instagram uns von /reel/CODE/ sofort wieder zurück auf /reels/CODE/,
            // lassen wir genau dieses eine Reel im Betrachter zu (das Userscript sperrt dort das Wischen).
            if betrachterCode == code { return akzeptiere(url, einzelCode: nil) }
            if let einzel = einzelReel, einzel.code == code,
               Date().timeIntervalSince(einzel.zeit) < Self.ruecksprungFrist {
                betrachterCode = code
                return akzeptiere(url, einzelCode: nil)
            }
            guard let einzelansicht = URL(string: "https://www.instagram.com/reel/\(code)/") else {
                return .umleiten(Self.startseite)
            }
            return .umleiten(einzelansicht)
        }

        // REGEL 3 – Explore: nur die Suche bleibt.
        // Erlaubt: /explore/ (Suchfeld; das Raster blendet das Userscript aus) und /explore/search/.
        // Gesperrt: /explore/tags/…, /explore/locations/…, /explore/people/…, /explore/search/keyword/… usw.
        if erstes == "explore" {
            let erlaubt = teile.count == 1 || (teile.count == 2 && teile[1].lowercased() == "search")
            return erlaubt ? akzeptiere(url, einzelCode: nil) : .umleiten(Self.suche)
        }

        // REGEL 4 – Reels-Tab auf Profilen: /name/reels/ → zurück aufs Profil.
        if teile.count >= 2, teile[1].lowercased() == "reels", let profil = Self.profilURL(teile[0]) {
            return .umleiten(profil)
        }

        // Alles andere auf Instagram ist erlaubt (Feed, Nachrichten, Stories, Profile, Beiträge, Konto …).
        // Ob Feed und Profilraster sichtbar sind, regelt das Userscript per CSS.
        let istEinzelReel = erstes == "reel" || (teile.count >= 3 && teile[1].lowercased() == "reel")
        return akzeptiere(url, einzelCode: istEinzelReel ? neuerCode : nil)
    }

    private mutating func akzeptiere(_ url: URL, einzelCode: String?) -> Entscheidung {
        letzteURL = url
        if let einzelCode {
            einzelReel = (code: einzelCode, zeit: Date())
        }
        return .erlauben
    }
}
