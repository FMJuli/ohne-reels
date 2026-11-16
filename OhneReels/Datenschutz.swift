import Foundation
import WebKit

/// DATENSPARSAMKEIT: Was behalten wird und was gelöscht wird.
@MainActor
enum Datenschutz {

    // MARK: - Zentrale Cookie-Liste (hier anpassen)

    /// Diese drei Cookies sind nötig, um eingeloggt zu bleiben:
    /// - sessionid:   die eigentliche Anmeldung
    /// - ds_user_id:  die Konto-Nummer; die Webseite erkennt daran "eingeloggt"
    /// - csrftoken:   Schutz-Token, ohne das Aktionen (Senden, Liken, Folgen) abgelehnt werden
    static let loginCookies: Set<String> = ["sessionid", "ds_user_id", "csrftoken"]

    /// Geräte-Kennungen von Instagram. Für den Login technisch NICHT nötig.
    /// Sie bleiben trotzdem erhalten, weil Instagram sonst bei jedem Start einen "neuen Browser"
    /// mit bestehender Sitzung sieht – das kann Sicherheitsabfragen ("Verdächtiger Anmeldeversuch")
    /// oder im schlimmsten Fall eine Kontosperre auslösen. Da du ohnehin eingeloggt bist, verraten
    /// diese Cookies Instagram nichts Zusätzliches.
    /// Für maximale Sparsamkeit: diese Menge leeren ( = [] ). Auf eigenes Risiko.
    static let geraeteCookies: Set<String> = ["mid", "ig_did", "datr"]

    /// Alle Cookies, die NICHT gelöscht werden. Alles andere (rur, wd, dpr, ps_l, ps_n, ig_nrcb,
    /// shbid, shbts … und sämtliche Cookies fremder Domains) wird entfernt.
    static var behalteneCookies: Set<String> { loginCookies.union(geraeteCookies) }

    /// Nur Cookies dieser Domain (und ihrer Unterdomains) dürfen bleiben.
    static let cookieDomain = "instagram.com"

    static func darfBleiben(_ cookie: HTTPCookie) -> Bool {
        var domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") { domain.removeFirst() }
        let istInstagram = domain == cookieDomain || domain.hasSuffix("." + cookieDomain)
        return istInstagram && behalteneCookies.contains(cookie.name)
    }

    // MARK: - Löschen

    /// Löscht Cache, localStorage, sessionStorage, IndexedDB, Service Worker usw. sowie alle Cookies
    /// außer den oben genannten. Wird beim Start und beim Wechsel in den Hintergrund aufgerufen.
    static func bereinigen(_ speicher: WKWebsiteDataStore, fertig: @escaping @MainActor () -> Void) {
        var typen = WKWebsiteDataStore.allWebsiteDataTypes()
        typen.remove(WKWebsiteDataTypeCookies)
        // Hinweis: Die Antworten von WebKit werden jeweils in "Task { @MainActor in … }" verpackt.
        // Das ist unabhängig davon korrekt, wie die jeweilige Xcode-Version die Rückruf-Typen kennzeichnet.
        speicher.removeData(ofTypes: typen, modifiedSince: Date.distantPast) {
            Task { @MainActor in
                speicher.httpCookieStore.getAllCookies { cookies in
                    Task { @MainActor in
                        let ueberfluessig = cookies.filter { !Datenschutz.darfBleiben($0) }
                        Datenschutz.loesche(ueberfluessig, ab: 0, in: speicher.httpCookieStore, fertig: fertig)
                    }
                }
            }
        }
    }

    /// Löscht restlos alles – auch die Login-Cookies. Für "Alle Daten löschen & abmelden".
    static func allesLoeschen(_ speicher: WKWebsiteDataStore, fertig: @escaping @MainActor () -> Void) {
        let typen = WKWebsiteDataStore.allWebsiteDataTypes()
        speicher.removeData(ofTypes: typen, modifiedSince: Date.distantPast) {
            Task { @MainActor in
                fertig()
            }
        }
    }

    /// Löscht die Cookies nacheinander (ohne veränderliche Zähler, damit der Compiler zufrieden ist).
    private static func loesche(_ cookies: [HTTPCookie], ab index: Int, in cookieSpeicher: WKHTTPCookieStore,
                                fertig: @escaping @MainActor () -> Void) {
        guard index < cookies.count else {
            fertig()
            return
        }
        cookieSpeicher.delete(cookies[index]) {
            Task { @MainActor in
                Datenschutz.loesche(cookies, ab: index + 1, in: cookieSpeicher, fertig: fertig)
            }
        }
    }
}
